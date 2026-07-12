import 'dart:convert';

enum DriveFailureKind {
  authRequired,
  accessDenied,
  fileMissing,
  network,
  rateLimited,
  server,
  unknown,
}

enum SyncPhase { idle, syncing, synced, offline, reconnectRequired, failed }

enum PlaybackFailurePolicy { ask, skip, stop }

enum PlayerRepeatMode { off, all, one }

DateTime _date(Object? value, {DateTime? fallback}) {
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  return (fallback ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
      .toUtc();
}

int? _int(Object? value) => value is num ? value.toInt() : null;

Map<String, Object?> _stringMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};

List<Map<String, Object?>> _mapList(Object? value) => value is List
    ? value.whereType<Map>().map(Map<String, Object?>.from).toList()
    : <Map<String, Object?>>[];

class CloudVideoState {
  const CloudVideoState({
    required this.id,
    required this.title,
    required this.uri,
    required this.updatedAt,
    required this.updatedByDeviceId,
    this.size,
    this.modifiedTime,
    this.durationMs,
    this.addedAt,
    this.lastPlayedAt,
    this.lastPositionMs = 0,
    this.isFavorite = false,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.deletedAt,
    this.driveSubtitle,
  });

  factory CloudVideoState.fromJson(
    Map<String, Object?> json, {
    String fallbackDeviceId = '',
  }) {
    return CloudVideoState(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled video',
      uri: json['uri'] as String? ?? '',
      size: _int(json['size']),
      modifiedTime: DateTime.tryParse(json['modifiedTime'] as String? ?? ''),
      durationMs: _int(json['durationMs'] ?? json['duration']),
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? ''),
      lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? ''),
      lastPositionMs: _int(json['lastPositionMs']) ?? 0,
      isFavorite: json['isFavorite'] as bool? ?? false,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      width: _int(json['width']),
      height: _int(json['height']),
      updatedAt: _date(json['updatedAt']),
      updatedByDeviceId:
          json['updatedByDeviceId'] as String? ?? fallbackDeviceId,
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
      driveSubtitle: json['driveSubtitle'] is Map
          ? SubtitleReference.fromJson(_stringMap(json['driveSubtitle']))
          : null,
    );
  }

  final String id;
  final String title;
  final String uri;
  final int? size;
  final DateTime? modifiedTime;
  final int? durationMs;
  final DateTime? addedAt;
  final DateTime? lastPlayedAt;
  final int lastPositionMs;
  final bool isFavorite;
  final String? thumbnailUrl;
  final int? width;
  final int? height;
  final DateTime updatedAt;
  final String updatedByDeviceId;
  final DateTime? deletedAt;
  final SubtitleReference? driveSubtitle;

  bool get isDeleted => deletedAt != null;

  CloudVideoState copyWith({
    String? title,
    String? uri,
    int? size,
    DateTime? modifiedTime,
    int? durationMs,
    DateTime? addedAt,
    DateTime? lastPlayedAt,
    int? lastPositionMs,
    bool? isFavorite,
    String? thumbnailUrl,
    int? width,
    int? height,
    DateTime? updatedAt,
    String? updatedByDeviceId,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    SubtitleReference? driveSubtitle,
    bool clearDriveSubtitle = false,
  }) {
    return CloudVideoState(
      id: id,
      title: title ?? this.title,
      uri: uri ?? this.uri,
      size: size ?? this.size,
      modifiedTime: modifiedTime ?? this.modifiedTime,
      durationMs: durationMs ?? this.durationMs,
      addedAt: addedAt ?? this.addedAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      isFavorite: isFavorite ?? this.isFavorite,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      width: width ?? this.width,
      height: height ?? this.height,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedByDeviceId: updatedByDeviceId ?? this.updatedByDeviceId,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      driveSubtitle: clearDriveSubtitle
          ? null
          : driveSubtitle ?? this.driveSubtitle,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'uri': uri,
    'source': 'drive',
    'size': size,
    'modifiedTime': modifiedTime?.toUtc().toIso8601String(),
    'durationMs': durationMs,
    'addedAt': addedAt?.toUtc().toIso8601String(),
    'lastPlayedAt': lastPlayedAt?.toUtc().toIso8601String(),
    'lastPositionMs': lastPositionMs,
    'isFavorite': isFavorite,
    'thumbnailUrl': thumbnailUrl,
    'width': width,
    'height': height,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'updatedByDeviceId': updatedByDeviceId,
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
    'driveSubtitle': driveSubtitle?.toJson(),
  };
}

class CloudPlaylistState {
  const CloudPlaylistState({
    required this.id,
    required this.name,
    required this.driveVideoIds,
    required this.createdAt,
    required this.updatedAt,
    required this.updatedByDeviceId,
    required this.sourceLabel,
    this.deletedAt,
  });

  factory CloudPlaylistState.fromJson(
    Map<String, Object?> json, {
    String fallbackDeviceId = '',
  }) {
    return CloudPlaylistState(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Playlist',
      driveVideoIds:
          (json['driveVideoIds'] as List? ??
                  json['videoIds'] as List? ??
                  const [])
              .whereType<String>()
              .toList(growable: false),
      createdAt: _date(json['createdAt'], fallback: DateTime.now()),
      updatedAt: _date(json['updatedAt']),
      updatedByDeviceId:
          json['updatedByDeviceId'] as String? ?? fallbackDeviceId,
      sourceLabel: json['sourceLabel'] as String? ?? '',
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    );
  }

  final String id;
  final String name;
  final List<String> driveVideoIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String updatedByDeviceId;
  final String sourceLabel;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'driveVideoIds': driveVideoIds,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'updatedByDeviceId': updatedByDeviceId,
    'sourceLabel': sourceLabel,
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };
}

class DriveImportRecord {
  const DriveImportRecord({
    required this.id,
    required this.folderId,
    required this.name,
    required this.videoIds,
    required this.importedAt,
    required this.updatedAt,
    required this.updatedByDeviceId,
    this.playlistId,
    this.deletedAt,
  });

  factory DriveImportRecord.fromJson(
    Map<String, Object?> json, {
    String fallbackDeviceId = '',
  }) {
    return DriveImportRecord(
      id: json['id'] as String? ?? json['folderId'] as String? ?? '',
      folderId: json['folderId'] as String? ?? '',
      name: json['name'] as String? ?? 'Drive import',
      videoIds: (json['videoIds'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      playlistId: json['playlistId'] as String?,
      importedAt: _date(json['importedAt'], fallback: DateTime.now()),
      updatedAt: _date(json['updatedAt']),
      updatedByDeviceId:
          json['updatedByDeviceId'] as String? ?? fallbackDeviceId,
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
    );
  }

  final String id;
  final String folderId;
  final String name;
  final List<String> videoIds;
  final String? playlistId;
  final DateTime importedAt;
  final DateTime updatedAt;
  final String updatedByDeviceId;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'folderId': folderId,
    'name': name,
    'videoIds': videoIds,
    'playlistId': playlistId,
    'importedAt': importedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'updatedByDeviceId': updatedByDeviceId,
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };
}

class SubtitleReference {
  const SubtitleReference({
    required this.kind,
    required this.uri,
    required this.mimeType,
    this.fileId,
    this.label,
    this.language,
  });

  factory SubtitleReference.fromJson(Map<String, Object?> json) {
    return SubtitleReference(
      kind: json['kind'] as String? ?? 'local',
      uri: json['uri'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? 'application/x-subrip',
      fileId: json['fileId'] as String?,
      label: json['label'] as String?,
      language: json['language'] as String?,
    );
  }

  final String kind;
  final String uri;
  final String mimeType;
  final String? fileId;
  final String? label;
  final String? language;

  bool get isDrive => kind == 'drive';

  Map<String, Object?> toJson() => {
    'kind': kind,
    'uri': uri,
    'mimeType': mimeType,
    'fileId': fileId,
    'label': label,
    'language': language,
  };
}

class RecentQueueSnapshot {
  const RecentQueueSnapshot({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.queueIds,
    required this.originalQueueIds,
    required this.currentIndex,
    required this.currentVideoId,
    required this.positionMs,
    required this.durationMs,
    required this.repeatMode,
    required this.shuffleEnabled,
    required this.updatedAt,
    this.title,
  });

  factory RecentQueueSnapshot.fromJson(Map<String, Object?> json) {
    final queueIds = (json['queueIds'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    return RecentQueueSnapshot(
      id: json['id'] as String? ?? queueSignature(queueIds),
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Unknown device',
      title: json['title'] as String?,
      queueIds: queueIds,
      originalQueueIds: (json['originalQueueIds'] as List? ?? queueIds)
          .whereType<String>()
          .toList(growable: false),
      currentIndex: _int(json['currentIndex']) ?? 0,
      currentVideoId: json['currentVideoId'] as String?,
      positionMs: _int(json['positionMs']) ?? 0,
      durationMs: _int(json['durationMs']) ?? 0,
      repeatMode: PlayerRepeatMode.values.firstWhere(
        (value) => value.name == json['repeatMode'],
        orElse: () => PlayerRepeatMode.all,
      ),
      shuffleEnabled: json['shuffleEnabled'] as bool? ?? false,
      updatedAt: _date(json['updatedAt']),
    );
  }

  final String id;
  final String deviceId;
  final String deviceName;
  final String? title;
  final List<String> queueIds;
  final List<String> originalQueueIds;
  final int currentIndex;
  final String? currentVideoId;
  final int positionMs;
  final int durationMs;
  final PlayerRepeatMode repeatMode;
  final bool shuffleEnabled;
  final DateTime updatedAt;

  String get signature => queueSignature(queueIds);

  Map<String, Object?> toJson() => {
    'id': id,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'title': title,
    'queueIds': queueIds,
    'originalQueueIds': originalQueueIds,
    'currentIndex': currentIndex,
    'currentVideoId': currentVideoId,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'repeatMode': repeatMode.name,
    'shuffleEnabled': shuffleEnabled,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static String queueSignature(Iterable<String> ids) =>
      base64Url.encode(utf8.encode(ids.join('\u001f'))).replaceAll('=', '');
}

String queueSignature(Iterable<String> ids) =>
    RecentQueueSnapshot.queueSignature(ids);

class CloudSettingValue<T> {
  const CloudSettingValue({
    required this.value,
    required this.updatedAt,
    required this.updatedByDeviceId,
  });

  final T value;
  final DateTime updatedAt;
  final String updatedByDeviceId;

  Map<String, Object?> toJson() => {
    'value': value,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'updatedByDeviceId': updatedByDeviceId,
  };
}

class CloudLibraryState {
  const CloudLibraryState({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.updatedAt,
    required this.videos,
    required this.playlists,
    required this.imports,
    required this.recentQueues,
    required this.resumePlayback,
    this.schemaVersion = 1,
  });

  factory CloudLibraryState.fromJson(Map<String, Object?> json) {
    final deviceId = json['deviceId'] as String? ?? '';
    final resumeJson = _stringMap(json['resumePlayback']);
    return CloudLibraryState(
      schemaVersion: _int(json['schemaVersion']) ?? 1,
      deviceId: deviceId,
      deviceName: json['deviceName'] as String? ?? 'Unknown device',
      platform: json['platform'] as String? ?? 'unknown',
      updatedAt: _date(json['updatedAt']),
      videos: _mapList(json['videos'])
          .map(
            (item) =>
                CloudVideoState.fromJson(item, fallbackDeviceId: deviceId),
          )
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      playlists: _mapList(json['playlists'])
          .map(
            (item) =>
                CloudPlaylistState.fromJson(item, fallbackDeviceId: deviceId),
          )
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      imports: _mapList(json['imports'])
          .map(
            (item) =>
                DriveImportRecord.fromJson(item, fallbackDeviceId: deviceId),
          )
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      recentQueues: _mapList(json['recentQueues'])
          .map(RecentQueueSnapshot.fromJson)
          .where((item) => item.queueIds.isNotEmpty)
          .toList(growable: false),
      resumePlayback: CloudSettingValue<bool>(
        value: resumeJson['value'] as bool? ?? true,
        updatedAt: _date(resumeJson['updatedAt']),
        updatedByDeviceId:
            resumeJson['updatedByDeviceId'] as String? ?? deviceId,
      ),
    );
  }

  final int schemaVersion;
  final String deviceId;
  final String deviceName;
  final String platform;
  final DateTime updatedAt;
  final List<CloudVideoState> videos;
  final List<CloudPlaylistState> playlists;
  final List<DriveImportRecord> imports;
  final List<RecentQueueSnapshot> recentQueues;
  final CloudSettingValue<bool> resumePlayback;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'videos': videos.map((item) => item.toJson()).toList(growable: false),
    'playlists': playlists.map((item) => item.toJson()).toList(growable: false),
    'imports': imports.map((item) => item.toJson()).toList(growable: false),
    'recentQueues': recentQueues
        .map((item) => item.toJson())
        .toList(growable: false),
    'resumePlayback': resumePlayback.toJson(),
  };

  static CloudLibraryState merge(
    Iterable<CloudLibraryState> states, {
    required String outputDeviceId,
    required String outputDeviceName,
    required String outputPlatform,
    DateTime? now,
  }) {
    final all = states.toList(growable: false);
    final videos = <String, CloudVideoState>{};
    final playlists = <String, CloudPlaylistState>{};
    final imports = <String, DriveImportRecord>{};
    final recentQueues = <String, RecentQueueSnapshot>{};
    CloudSettingValue<bool>? resumePlayback;

    for (final state in all) {
      for (final item in state.videos) {
        final existing = videos[item.id];
        if (existing == null ||
            _isNewer(
              item.updatedAt,
              item.updatedByDeviceId,
              existing.updatedAt,
              existing.updatedByDeviceId,
            )) {
          videos[item.id] = item;
        }
      }
      for (final item in state.playlists) {
        final existing = playlists[item.id];
        if (existing == null ||
            _isNewer(
              item.updatedAt,
              item.updatedByDeviceId,
              existing.updatedAt,
              existing.updatedByDeviceId,
            )) {
          playlists[item.id] = item;
        }
      }
      for (final item in state.imports) {
        final existing = imports[item.id];
        if (existing == null ||
            _isNewer(
              item.updatedAt,
              item.updatedByDeviceId,
              existing.updatedAt,
              existing.updatedByDeviceId,
            )) {
          imports[item.id] = item;
        }
      }
      for (final item in state.recentQueues) {
        final key = '${item.deviceId}:${item.signature}';
        final existing = recentQueues[key];
        if (existing == null || item.updatedAt.isAfter(existing.updatedAt)) {
          recentQueues[key] = item;
        }
      }
      final incomingResume = state.resumePlayback;
      final currentResume = resumePlayback;
      if (currentResume == null ||
          _isNewer(
            incomingResume.updatedAt,
            incomingResume.updatedByDeviceId,
            currentResume.updatedAt,
            currentResume.updatedByDeviceId,
          )) {
        resumePlayback = incomingResume;
      }
    }

    final queues = recentQueues.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final limitedQueues = <RecentQueueSnapshot>[];
    final counts = <String, int>{};
    for (final queue in queues) {
      final count = counts[queue.deviceId] ?? 0;
      if (count >= 10) continue;
      counts[queue.deviceId] = count + 1;
      limitedQueues.add(queue);
    }

    final timestamp = (now ?? DateTime.now()).toUtc();
    return CloudLibraryState(
      deviceId: outputDeviceId,
      deviceName: outputDeviceName,
      platform: outputPlatform,
      updatedAt: timestamp,
      videos: videos.values.toList(growable: false),
      playlists: playlists.values.toList(growable: false),
      imports: imports.values.toList(growable: false),
      recentQueues: limitedQueues,
      resumePlayback:
          resumePlayback ??
          CloudSettingValue<bool>(
            value: true,
            updatedAt: timestamp,
            updatedByDeviceId: outputDeviceId,
          ),
    );
  }
}

bool _isNewer(
  DateTime candidateTime,
  String candidateDevice,
  DateTime currentTime,
  String currentDevice,
) {
  final comparison = candidateTime.compareTo(currentTime);
  if (comparison != 0) return comparison > 0;
  return candidateDevice.compareTo(currentDevice) > 0;
}

class CloudPlaybackState {
  const CloudPlaybackState({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.updatedAt,
    required this.queue,
    required this.queueItems,
    this.schemaVersion = 2,
  });

  factory CloudPlaybackState.fromJson(Map<String, Object?> json) {
    final queueJson = json['queue'] is Map
        ? _stringMap(json['queue'])
        : _stringMap(json['queueState']);
    final deviceId = json['deviceId'] as String? ?? 'legacy';
    final queue = RecentQueueSnapshot.fromJson({
      ...queueJson,
      'deviceId': queueJson['deviceId'] ?? deviceId,
      'deviceName':
          queueJson['deviceName'] ??
          json['deviceName'] ??
          (deviceId == 'legacy' ? 'Legacy device' : 'Unknown device'),
      'updatedAt': queueJson['updatedAt'] ?? json['updatedAt'],
    });
    return CloudPlaybackState(
      schemaVersion: _int(json['schemaVersion']) ?? 1,
      deviceId: deviceId,
      deviceName: json['deviceName'] as String? ?? queue.deviceName,
      platform: json['platform'] as String? ?? 'unknown',
      updatedAt: _date(json['updatedAt'], fallback: queue.updatedAt),
      queue: queue,
      queueItems: _mapList(json['queueItems'])
          .map(
            (item) =>
                CloudVideoState.fromJson(item, fallbackDeviceId: deviceId),
          )
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  final int schemaVersion;
  final String deviceId;
  final String deviceName;
  final String platform;
  final DateTime updatedAt;
  final RecentQueueSnapshot queue;
  final List<CloudVideoState> queueItems;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'queue': queue.toJson(),
    'queueItems': queueItems
        .map((item) => item.toJson())
        .toList(growable: false),
  };

  static CloudPlaybackState? latest(Iterable<CloudPlaybackState> states) {
    CloudPlaybackState? latest;
    for (final state in states) {
      if (state.queue.queueIds.isEmpty) continue;
      if (latest == null || state.updatedAt.isAfter(latest.updatedAt)) {
        latest = state;
      }
    }
    return latest;
  }
}

class CloudBackupPayload {
  const CloudBackupPayload({
    required this.createdAt,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.library,
    this.queue,
    this.schemaVersion = 1,
  });

  factory CloudBackupPayload.fromJson(Map<String, Object?> json) {
    final libraryJson = _stringMap(json['library']);
    final queueJson = _stringMap(json['queue']);
    return CloudBackupPayload(
      schemaVersion: _int(json['schemaVersion']) ?? 1,
      createdAt: _date(json['createdAt']),
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? 'Unknown device',
      platform: json['platform'] as String? ?? 'unknown',
      library: CloudLibraryState.fromJson(libraryJson),
      queue: queueJson.isEmpty ? null : CloudPlaybackState.fromJson(queueJson),
    );
  }

  final int schemaVersion;
  final DateTime createdAt;
  final String deviceId;
  final String deviceName;
  final String platform;
  final CloudLibraryState library;
  final CloudPlaybackState? queue;

  int get activeVideoCount =>
      library.videos.where((item) => !item.isDeleted).length;
  int get activePlaylistCount =>
      library.playlists.where((item) => !item.isDeleted).length;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'deviceId': deviceId,
    'deviceName': deviceName,
    'platform': platform,
    'library': library.toJson(),
    'queue': queue?.toJson(),
  };
}

class SyncHealth {
  const SyncHealth({
    this.phase = SyncPhase.idle,
    this.lastAttemptAt,
    this.lastSuccessAt,
    this.failureKind,
    this.httpStatus,
    this.message,
    this.retryable = false,
  });

  final SyncPhase phase;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final DriveFailureKind? failureKind;
  final int? httpStatus;
  final String? message;
  final bool retryable;

  SyncHealth copyWith({
    SyncPhase? phase,
    DateTime? lastAttemptAt,
    DateTime? lastSuccessAt,
    DriveFailureKind? failureKind,
    int? httpStatus,
    String? message,
    bool? retryable,
    bool clearFailure = false,
  }) {
    return SyncHealth(
      phase: phase ?? this.phase,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      failureKind: clearFailure ? null : failureKind ?? this.failureKind,
      httpStatus: clearFailure ? null : httpStatus ?? this.httpStatus,
      message: clearFailure ? null : message ?? this.message,
      retryable: retryable ?? this.retryable,
    );
  }
}

class DiagnosticEvent {
  const DiagnosticEvent({
    required this.timestamp,
    required this.category,
    required this.message,
    this.failureKind,
    this.httpStatus,
  });

  factory DiagnosticEvent.fromJson(Map<String, Object?> json) {
    return DiagnosticEvent(
      timestamp: _date(json['timestamp']),
      category: json['category'] as String? ?? 'app',
      message: json['message'] as String? ?? '',
      failureKind: DriveFailureKind.values
          .where((value) => value.name == json['failureKind'])
          .firstOrNull,
      httpStatus: _int(json['httpStatus']),
    );
  }

  final DateTime timestamp;
  final String category;
  final String message;
  final DriveFailureKind? failureKind;
  final int? httpStatus;

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toUtc().toIso8601String(),
    'category': category,
    'message': message,
    'failureKind': failureKind?.name,
    'httpStatus': httpStatus,
  };
}
