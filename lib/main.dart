import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const DriveShuffleApp());
}

const _driveScopes = <String>[
  'https://www.googleapis.com/auth/drive.readonly',
];
const _serverClientId =
    '160619668600-gmrtfcj8gfv3q5t3qr3936qifj453ccb.apps.googleusercontent.com';
const _driveFolderMimeType = 'application/vnd.google-apps.folder';

class DriveShuffleApp extends StatelessWidget {
  const DriveShuffleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Drive Shuffle',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff176b87),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101314),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

enum VideoSource { local, drive }

class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.uri,
    required this.source,
  });

  final String id;
  final String title;
  final String uri;
  final VideoSource source;

  Map<String, Object?> toPlaybackMap() => {
    'id': id,
    'title': title,
    'uri': uri,
    'source': source.name,
  };
}

enum DriveEntryType { folder, video }

class DriveEntry {
  const DriveEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.mimeType,
    this.modifiedTime,
    this.size,
  });

  final String id;
  final String name;
  final DriveEntryType type;
  final String mimeType;
  final DateTime? modifiedTime;
  final int? size;

  bool get isFolder => type == DriveEntryType.folder;
  bool get isVideo => type == DriveEntryType.video;

  VideoItem toVideoItem() {
    return VideoItem(
      id: 'drive:$id',
      title: name,
      uri: 'https://www.googleapis.com/drive/v3/files/$id?alt=media',
      source: VideoSource.drive,
    );
  }
}

class DriveImportResult {
  const DriveImportResult({
    required this.items,
    required this.sourceName,
  });

  final List<VideoItem> items;
  final String sourceName;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _playback = MethodChannel('drive_shuffle_player/playback');

  final _signIn = GoogleSignIn.instance;
  final _random = Random();

  GoogleSignInAccount? _user;
  String? _accessToken;
  final List<VideoItem> _videos = [];
  bool _initializing = true;
  bool _busy = false;
  String _status = '초기화 중...';

  @override
  void initState() {
    super.initState();
    unawaited(_initializeGoogleSignIn());
  }

  Future<void> _initializeGoogleSignIn() async {
    try {
      await _signIn.initialize(serverClientId: _serverClientId);
      _signIn.authenticationEvents.listen((event) async {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn(:final user):
            await _setUser(user);
          case GoogleSignInAuthenticationEventSignOut():
            setState(() {
              _user = null;
              _accessToken = null;
              _status = 'Google Drive를 쓰려면 로그인하세요.';
            });
        }
      });
      unawaited(_signIn.attemptLightweightAuthentication());
      setState(() {
        _initializing = false;
        _status = '로컬 영상을 추가하거나 Google Drive에 로그인하세요.';
      });
    } catch (error) {
      setState(() {
        _initializing = false;
        _status = 'Google 로그인 초기화 실패: $error';
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    await _guarded(() async {
      final user = await _signIn.authenticate();
      await _setUser(user);
    });
  }

  Future<void> _switchGoogleAccount() async {
    await _guarded(() async {
      await _signIn.signOut();
      setState(() {
        _user = null;
        _accessToken = null;
        _status = '다른 Google 계정을 선택하세요.';
      });
      final user = await _signIn.authenticate();
      await _setUser(user);
    });
  }

  Future<void> _setUser(GoogleSignInAccount user) async {
    final headers = await user.authorizationClient.authorizationHeaders(
      _driveScopes,
      promptIfNecessary: true,
    );
    final authorization = headers?['Authorization'];
    setState(() {
      _user = user;
      _accessToken = authorization?.replaceFirst('Bearer ', '');
      _status = authorization == null
          ? 'Drive 권한을 받지 못했습니다.'
          : '${user.email} 계정으로 로그인됨';
    });
  }

  Future<void> _addLocalVideos() async {
    await _guarded(() async {
      final result = await _playback.invokeListMethod<Map<Object?, Object?>>(
        'pickLocalVideos',
      );
      if (result == null || result.isEmpty) return;

      final picked = result.map((file) {
        final uri = file['uri']! as String;
        final name = file['name'] as String? ?? 'Local video';
        return VideoItem(
          id: uri,
          title: name,
          uri: uri,
          source: VideoSource.local,
        );
      }).toList();

      final added = _addUniqueVideos(picked);
      setState(() {
        _status = added == 0 ? '이미 추가된 로컬 영상입니다.' : '로컬 영상 $added개 추가됨';
      });
    });
  }

  Future<void> _openDriveBrowser() async {
    await _guarded(() async {
      if (!await _ensureDriveReady()) return;
      if (!mounted) return;

      final result = await showDialog<DriveImportResult>(
        context: context,
        builder: (context) => _DriveBrowserDialog(
          loadEntries: _listDriveEntries,
          loadFolderTreeVideos: _collectDriveVideosRecursively,
        ),
      );
      if (result == null || result.items.isEmpty) return;

      final added = _addUniqueVideos(result.items);
      setState(() {
        _status = added == 0
            ? '이미 추가된 Drive 영상입니다.'
            : '${result.sourceName}에서 Drive 영상 $added개 추가됨';
      });
    });
  }

  int _addUniqueVideos(List<VideoItem> items) {
    final knownIds = _videos.map((item) => item.id).toSet();
    final uniqueItems = items.where((item) => knownIds.add(item.id)).toList();
    setState(() => _videos.addAll(uniqueItems));
    return uniqueItems.length;
  }

  Future<bool> _ensureDriveReady() async {
    if (_user == null || _accessToken == null) {
      _showMessage('먼저 Google 계정으로 로그인하세요.');
      return false;
    }
    return true;
  }

  Future<List<DriveEntry>> _listDriveEntries(String parentId) async {
    final query =
        "'$parentId' in parents and trashed=false and "
        "(mimeType='$_driveFolderMimeType' or mimeType contains 'video/')";
    return _listDriveEntriesByQuery(query);
  }

  Future<List<VideoItem>> _collectDriveVideosRecursively(String folderId) async {
    final queue = <String>[folderId];
    final videos = <VideoItem>[];

    while (queue.isNotEmpty) {
      final currentFolderId = queue.removeAt(0);
      final entries = await _listDriveEntries(currentFolderId);
      for (final entry in entries) {
        if (entry.isFolder) {
          queue.add(entry.id);
        } else if (entry.isVideo) {
          videos.add(entry.toVideoItem());
        }
      }
    }

    return videos;
  }

  Future<List<DriveEntry>> _listDriveEntriesByQuery(String query) async {
    final entries = <DriveEntry>[];
    String? pageToken;

    do {
      final queryParameters = <String, String>{
        'q': query,
        'fields': 'nextPageToken,files(id,name,mimeType,size,modifiedTime)',
        'orderBy': 'name',
        'pageSize': '1000',
        'supportsAllDrives': 'true',
        'includeItemsFromAllDrives': 'true',
      };
      if (pageToken != null) queryParameters['pageToken'] = pageToken;
      final url = Uri.https(
        'www.googleapis.com',
        '/drive/v3/files',
        queryParameters,
      );
      final body = await _driveGet(url);
      final files = body['files'] as List<Object?>? ?? const [];
      entries.addAll(files.cast<Map<String, Object?>>().map((file) {
        final mimeType = file['mimeType'] as String? ?? '';
        return DriveEntry(
          id: file['id']! as String,
          name: file['name'] as String? ?? '이름 없음',
          mimeType: mimeType,
          type: mimeType == _driveFolderMimeType
              ? DriveEntryType.folder
              : DriveEntryType.video,
          modifiedTime:
              DateTime.tryParse(file['modifiedTime'] as String? ?? ''),
          size: int.tryParse(file['size'] as String? ?? ''),
        );
      }));
      pageToken = body['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);

    entries.sort((a, b) {
      if (a.type != b.type) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<Map<String, Object?>> _driveGet(Uri url) async {
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $_accessToken'},
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      await _user!.authorizationClient.clearAuthorizationToken(
        accessToken: _accessToken!,
      );
      await _setUser(_user!);
      throw StateError('Drive 권한이 만료됐습니다. 다시 시도하세요.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Drive 요청 실패 (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, Object?>;
  }

  Future<void> _playShuffled() async {
    await _guarded(() async {
      if (_videos.isEmpty) {
        _showMessage('재생할 영상을 먼저 추가하세요.');
        return;
      }
      final queue = [..._videos]..shuffle(_random);
      await _playback.invokeMethod('playQueue', {
        'accessToken': _accessToken,
        'items': queue.map((item) => item.toPlaybackMap()).toList(),
      });
      await _playback.invokeMethod('openPlayer');
      setState(() => _status = '셔플 재생 중: ${queue.first.title}');
    });
  }

  Future<void> _invokePlayer(String method) async {
    await _guarded(() => _playback.invokeMethod(method));
  }

  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _showMessage(error.toString());
      setState(() => _status = '오류: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localCount = _videos
        .where((item) => item.source == VideoSource.local)
        .length;
    final driveCount = _videos
        .where((item) => item.source == VideoSource.drive)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drive Shuffle'),
        actions: [
          if (_user != null)
            IconButton(
              tooltip: '계정 바꾸기',
              onPressed: _busy || _initializing ? null : _switchGoogleAccount,
              icon: const Icon(Icons.switch_account_outlined),
            ),
          IconButton(
            tooltip: 'Google 로그인',
            onPressed: _busy || _initializing ? null : _signInWithGoogle,
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusPanel(
              status: _status,
              userEmail: _user?.email,
              localCount: localCount,
              driveCount: driveCount,
            ),
            const SizedBox(height: 16),
            _ActionGrid(
              busy: _busy || _initializing,
              onAddLocal: _addLocalVideos,
              onAddDrive: _openDriveBrowser,
              onOpenPlayer: () => _invokePlayer('openPlayer'),
              onPlay: _playShuffled,
              onPause: () => _invokePlayer('playPause'),
              onNext: () => _invokePlayer('next'),
              onStop: () => _invokePlayer('stop'),
            ),
            const SizedBox(height: 16),
            Text(
              '재생 목록',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_videos.isEmpty)
              const _EmptyLibrary()
            else
              ..._videos.map((item) => _VideoTile(item: item)),
          ],
        ),
      ),
    );
  }
}

class _DriveBrowserDialog extends StatefulWidget {
  const _DriveBrowserDialog({
    required this.loadEntries,
    required this.loadFolderTreeVideos,
  });

  final Future<List<DriveEntry>> Function(String parentId) loadEntries;
  final Future<List<VideoItem>> Function(String folderId) loadFolderTreeVideos;

  @override
  State<_DriveBrowserDialog> createState() => _DriveBrowserDialogState();
}

class _DriveBrowserDialogState extends State<_DriveBrowserDialog> {
  final List<DriveEntry> _path = const [
    DriveEntry(
      id: 'root',
      name: '내 드라이브',
      type: DriveEntryType.folder,
      mimeType: _driveFolderMimeType,
    ),
  ].toList();
  late Future<List<DriveEntry>> _entries = widget.loadEntries(_current.id);
  List<DriveEntry> _visibleEntries = const [];
  bool _collecting = false;
  String _collectingName = '';

  DriveEntry get _current => _path.last;

  void _openFolder(DriveEntry folder) {
    setState(() {
      _path.add(folder);
      _visibleEntries = const [];
      _entries = widget.loadEntries(folder.id);
    });
  }

  void _goUp() {
    if (_path.length <= 1) return;
    setState(() {
      _path.removeLast();
      _visibleEntries = const [];
      _entries = widget.loadEntries(_current.id);
    });
  }

  void _refresh() {
    setState(() {
      _visibleEntries = const [];
      _entries = widget.loadEntries(_current.id);
    });
  }

  void _selectVideo(DriveEntry entry) {
    Navigator.pop(
      context,
      DriveImportResult(items: [entry.toVideoItem()], sourceName: entry.name),
    );
  }

  Future<void> _addFolderTree(DriveEntry folder) async {
    setState(() {
      _collecting = true;
      _collectingName = folder.name;
    });
    try {
      final videos = await widget.loadFolderTreeVideos(folder.id);
      if (!mounted) return;
      Navigator.pop(
        context,
        DriveImportResult(items: videos, sourceName: folder.name),
      );
    } catch (_) {
      rethrow;
    } finally {
      if (mounted) setState(() => _collecting = false);
    }
  }

  Future<void> _addCurrentFolderTree() => _addFolderTree(_current);

  @override
  Widget build(BuildContext context) {
    final currentFolderVideos =
        _visibleEntries.where((entry) => entry.isVideo).length;

    return AlertDialog(
      title: const Text('Google Drive에서 가져오기'),
      content: SizedBox(
        width: double.maxFinite,
        height: 540,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DrivePathBar(
                  path: _path,
                  onGoUp: _path.length > 1 ? _goUp : null,
                  onRefresh: _refresh,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _collecting ? null : _addCurrentFolderTree,
                  icon: const Icon(Icons.playlist_add),
                  label: Text(
                    '이 폴더 전체 추가 ($currentFolderVideos개 표시됨)',
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: FutureBuilder<List<DriveEntry>>(
                    future: _entries,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text(snapshot.error.toString()));
                      }

                      final entries = snapshot.data ?? const [];
                      _visibleEntries = entries;
                      if (entries.isEmpty) {
                        return const Center(
                          child: Text('이 폴더에는 하위 폴더나 영상이 없습니다.'),
                        );
                      }

                      return ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _DriveEntryTile(
                            entry: entry,
                            onTap: entry.isFolder
                                ? () => _openFolder(entry)
                                : () => _selectVideo(entry),
                            onAddFolderTree: entry.isFolder && !_collecting
                                ? () => _addFolderTree(entry)
                                : null,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
            if (_collecting)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text('$_collectingName 하위 폴더까지 수집 중...'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _collecting ? null : () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
      ],
    );
  }
}

class _DrivePathBar extends StatelessWidget {
  const _DrivePathBar({
    required this.path,
    required this.onGoUp,
    required this.onRefresh,
  });

  final List<DriveEntry> path;
  final VoidCallback? onGoUp;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '상위 폴더',
          onPressed: onGoUp,
          icon: const Icon(Icons.arrow_upward),
        ),
        IconButton(
          tooltip: '새로고침',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              path.map((entry) => entry.name).join(' / '),
              maxLines: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _DriveEntryTile extends StatelessWidget {
  const _DriveEntryTile({
    required this.entry,
    required this.onTap,
    required this.onAddFolderTree,
  });

  final DriveEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onAddFolderTree;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        entry.isFolder ? Icons.folder_outlined : Icons.movie_outlined,
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: entry.isFolder ? const Text('폴더') : Text(_videoDescription(entry)),
      trailing: entry.isFolder
          ? Wrap(
              spacing: 2,
              children: [
                IconButton(
                  tooltip: '하위 폴더까지 전체 추가',
                  onPressed: onAddFolderTree,
                  icon: const Icon(Icons.playlist_add),
                ),
                const Icon(Icons.chevron_right),
              ],
            )
          : const Icon(Icons.add_circle),
      onTap: onTap,
    );
  }

  String _videoDescription(DriveEntry entry) {
    final parts = <String>[];
    if (entry.size != null) parts.add(_formatBytes(entry.size!));
    if (entry.modifiedTime != null) parts.add(_formatDate(entry.modifiedTime!));
    return parts.isEmpty ? '영상 파일' : parts.join(' · ');
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    final digits = unitIndex == 0 ? 0 : 1;
    return '${size.toStringAsFixed(digits)} ${units[unitIndex]}';
  }

  String _formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.year}.${_two(local.month)}.${_two(local.day)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.status,
    required this.userEmail,
    required this.localCount,
    required this.driveCount,
  });

  final String status;
  final String? userEmail;
  final int localCount;
  final int driveCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(userEmail ?? 'Google 계정 연결 안 됨'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('로컬 $localCount')),
              Chip(label: Text('Drive $driveCount')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.busy,
    required this.onAddLocal,
    required this.onAddDrive,
    required this.onOpenPlayer,
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onStop,
  });

  final bool busy;
  final VoidCallback onAddLocal;
  final VoidCallback onAddDrive;
  final VoidCallback onOpenPlayer;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onNext;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.25,
      children: [
        _ToolButton(
          icon: Icons.video_library_outlined,
          label: '로컬',
          onPressed: busy ? null : onAddLocal,
        ),
        _ToolButton(
          icon: Icons.cloud_outlined,
          label: 'Drive',
          onPressed: busy ? null : onAddDrive,
        ),
        _ToolButton(
          icon: Icons.fullscreen,
          label: '플레이어',
          onPressed: busy ? null : onOpenPlayer,
        ),
        _ToolButton(
          icon: Icons.shuffle,
          label: '셔플',
          onPressed: busy ? null : onPlay,
        ),
        _ToolButton(
          icon: Icons.pause_circle_outline,
          label: '재생/정지',
          onPressed: busy ? null : onPause,
        ),
        _ToolButton(
          icon: Icons.skip_next,
          label: '다음',
          onPressed: busy ? null : onNext,
        ),
        _ToolButton(
          icon: Icons.stop_circle_outlined,
          label: '중지',
          onPressed: busy ? null : onStop,
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(height: 6),
          Text(label, maxLines: 1),
        ],
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.item});

  final VideoItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        item.source == VideoSource.drive
            ? Icons.cloud_outlined
            : Icons.movie_outlined,
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(item.source == VideoSource.drive ? 'Google Drive' : 'Local'),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('아직 영상이 없습니다.'),
    );
  }
}
