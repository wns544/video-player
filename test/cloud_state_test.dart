import 'dart:convert';

import 'package:drive_shuffle_player/cloud_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudLibraryState.merge', () {
    test('keeps the newest record and propagates tombstones', () {
      final older = _library(
        deviceId: 'phone-a',
        videos: [
          _video(
            id: 'drive:movie',
            title: 'Old title',
            updatedAt: DateTime.utc(2026, 7, 1),
            deviceId: 'phone-a',
          ),
        ],
      );
      final deletedAt = DateTime.utc(2026, 7, 2);
      final newer = _library(
        deviceId: 'pc-b',
        videos: [
          _video(
            id: 'drive:movie',
            title: 'Deleted title',
            updatedAt: deletedAt,
            deviceId: 'pc-b',
            deletedAt: deletedAt,
          ),
        ],
      );

      final merged = CloudLibraryState.merge(
        [older, newer],
        outputDeviceId: 'phone-a',
        outputDeviceName: 'Phone A',
        outputPlatform: 'android',
        now: DateTime.utc(2026, 7, 3),
      );

      expect(merged.videos, hasLength(1));
      expect(merged.videos.single.title, 'Deleted title');
      expect(merged.videos.single.deletedAt, deletedAt);
    });

    test('uses device id as deterministic tie breaker', () {
      final time = DateTime.utc(2026, 7, 1);
      final merged = CloudLibraryState.merge(
        [
          _library(
            deviceId: 'device-a',
            videos: [
              _video(
                id: 'drive:same',
                title: 'A',
                updatedAt: time,
                deviceId: 'device-a',
              ),
            ],
          ),
          _library(
            deviceId: 'device-z',
            videos: [
              _video(
                id: 'drive:same',
                title: 'Z',
                updatedAt: time,
                deviceId: 'device-z',
              ),
            ],
          ),
        ],
        outputDeviceId: 'device-a',
        outputDeviceName: 'A',
        outputPlatform: 'android',
      );

      expect(merged.videos.single.title, 'Z');
    });

    test('limits recent queues to ten per device', () {
      final queues = List.generate(15, (index) {
        return RecentQueueSnapshot(
          id: 'queue-$index',
          deviceId: 'phone-a',
          deviceName: 'Phone A',
          queueIds: ['drive:$index'],
          originalQueueIds: ['drive:$index'],
          currentIndex: 0,
          currentVideoId: 'drive:$index',
          positionMs: index * 1000,
          durationMs: 100000,
          repeatMode: PlayerRepeatMode.all,
          shuffleEnabled: false,
          updatedAt: DateTime.utc(2026, 7, 1).add(Duration(minutes: index)),
        );
      });
      final merged = CloudLibraryState.merge(
        [_library(deviceId: 'phone-a', recentQueues: queues)],
        outputDeviceId: 'phone-a',
        outputDeviceName: 'Phone A',
        outputPlatform: 'android',
      );

      expect(merged.recentQueues, hasLength(10));
      expect(merged.recentQueues.first.id, 'queue-14');
      expect(merged.recentQueues.last.id, 'queue-5');
    });
  });

  test('serializes and restores a 1000 item queue', () {
    final ids = List.generate(1000, (index) => 'drive:video-$index');
    final queue = RecentQueueSnapshot(
      id: queueSignature(ids),
      deviceId: 'stress-device',
      deviceName: 'Stress device',
      queueIds: ids,
      originalQueueIds: ids.reversed.toList(growable: false),
      currentIndex: 731,
      currentVideoId: ids[731],
      positionMs: 123456,
      durationMs: 999999,
      repeatMode: PlayerRepeatMode.all,
      shuffleEnabled: true,
      updatedAt: DateTime.utc(2026, 7, 11),
    );
    final state = CloudPlaybackState(
      deviceId: 'stress-device',
      deviceName: 'Stress device',
      platform: 'android',
      updatedAt: DateTime.utc(2026, 7, 11),
      queue: queue,
      queueItems: const [],
    );

    final stopwatch = Stopwatch()..start();
    final decoded = CloudPlaybackState.fromJson(
      Map<String, Object?>.from(jsonDecode(jsonEncode(state.toJson())) as Map),
    );
    stopwatch.stop();

    expect(decoded.queue.queueIds, hasLength(1000));
    expect(decoded.queue.currentVideoId, ids[731]);
    expect(decoded.queue.originalQueueIds.first, ids.last);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

CloudLibraryState _library({
  required String deviceId,
  List<CloudVideoState> videos = const [],
  List<RecentQueueSnapshot> recentQueues = const [],
}) {
  final time = DateTime.utc(2026, 7, 1);
  return CloudLibraryState(
    deviceId: deviceId,
    deviceName: deviceId,
    platform: 'test',
    updatedAt: time,
    videos: videos,
    playlists: const [],
    imports: const [],
    recentQueues: recentQueues,
    resumePlayback: CloudSettingValue<bool>(
      value: true,
      updatedAt: time,
      updatedByDeviceId: deviceId,
    ),
  );
}

CloudVideoState _video({
  required String id,
  required String title,
  required DateTime updatedAt,
  required String deviceId,
  DateTime? deletedAt,
}) {
  return CloudVideoState(
    id: id,
    title: title,
    uri: 'https://example.invalid/$id',
    updatedAt: updatedAt,
    updatedByDeviceId: deviceId,
    deletedAt: deletedAt,
  );
}
