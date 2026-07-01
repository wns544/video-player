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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _playback = MethodChannel('drive_shuffle_player/playback');

  final _folderController = TextEditingController();
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

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
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
      });

      setState(() {
        _videos.addAll(picked);
        _status = '로컬 영상 ${result.length}개 추가됨';
      });
    });
  }

  Future<void> _loadDriveFolder() async {
    await _guarded(() async {
      final folderId = _folderController.text.trim();
      if (folderId.isEmpty) {
        _showMessage('Google Drive 폴더 ID를 입력하세요.');
        return;
      }
      if (_user == null || _accessToken == null) {
        _showMessage('먼저 Google 계정으로 로그인하세요.');
        return;
      }

      final encodedQuery = Uri.encodeQueryComponent(
        "'$folderId' in parents and trashed=false and mimeType contains 'video/'",
      );
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        '?q=$encodedQuery'
        '&fields=files(id,name,mimeType,size,modifiedTime)'
        '&pageSize=1000'
        '&supportsAllDrives=true'
        '&includeItemsFromAllDrives=true',
      );
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
        throw StateError('Drive 목록 조회 실패 (${response.statusCode})');
      }

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final files = (body['files'] as List<Object?>? ?? const []);
      final driveItems = files.cast<Map<String, Object?>>().map((file) {
        final id = file['id']! as String;
        return VideoItem(
          id: 'drive:$id',
          title: file['name'] as String? ?? 'Drive video',
          uri: 'https://www.googleapis.com/drive/v3/files/$id?alt=media',
          source: VideoSource.drive,
        );
      }).toList();

      setState(() {
        _videos.removeWhere((item) => item.source == VideoSource.drive);
        _videos.addAll(driveItems);
        _status = 'Drive 영상 ${driveItems.length}개 불러옴';
      });
    });
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
              onPlay: _playShuffled,
              onPause: () => _invokePlayer('playPause'),
              onNext: () => _invokePlayer('next'),
              onStop: () => _invokePlayer('stop'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _folderController,
              decoration: InputDecoration(
                labelText: 'Google Drive 폴더 ID',
                hintText: 'drive.google.com/drive/folders/ 뒤의 값',
                suffixIcon: IconButton(
                  tooltip: 'Drive 영상 불러오기',
                  onPressed: _busy ? null : _loadDriveFolder,
                  icon: const Icon(Icons.cloud_sync_outlined),
                ),
              ),
              onSubmitted: (_) => _loadDriveFolder(),
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
          Text(
            status,
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
    required this.onPlay,
    required this.onPause,
    required this.onNext,
    required this.onStop,
  });

  final bool busy;
  final VoidCallback onAddLocal;
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
