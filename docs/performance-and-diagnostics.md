# Performance and diagnostics runbook

This project keeps playback quality, background audio, and PiP behavior unchanged. The checks below are intended to detect leaks and unnecessary work without changing the user experience.

## Built-in limits

- Mobile thumbnail memory cache: at most 80 decoded images and 32 MiB.
- Mobile playback position: memory updates continue normally; SharedPreferences writes occur after about 10 seconds of movement or immediately on pause, video transition, completion, and dispose.
- PC playback position: IndexedDB and Drive queue writes are throttled to 10 seconds and flushed on pause, stream transition, and player close.
- Recent cloud queues: at most 10 snapshots per device.
- Cloud records use `(updatedAt, deviceId)` ordering and deletion tombstones, so concurrent devices do not silently overwrite one another.

## Automated checks

Mobile:

```powershell
flutter analyze
flutter test
flutter build apk --release
```

The cloud-state test includes a 1,000-item queue JSON round trip, deterministic conflict resolution, tombstone propagation, and recent-queue limits.

PC:

```powershell
npm run lint
npm run build
npm run perf:queue
```

`perf:queue` performs 50 round trips of a 1,000-item queue and 20 merges of 8,000 cloud video records, then prints elapsed time and Node heap usage.

## Android long-run measurement

Use a release build. Record the package memory before playback, after 15 minutes, and after one hour:

```powershell
adb shell dumpsys meminfo com.example.drive_shuffle_player
adb shell dumpsys batterystats com.example.drive_shuffle_player
adb shell dumpsys media_session
```

Run these scenarios separately:

1. Scroll a 1,000-video library repeatedly, then leave the list idle for five minutes.
2. Play Drive video for one hour with automatic next-video transitions.
3. Leave PiP playing for one hour, then return to the full player.
4. Switch between background audio, PiP, and the full player at least 20 times.
5. Expire the Drive token once and confirm that only one reconnect prompt appears.

Healthy behavior:

- Java/native heap rises while thumbnails and codecs warm up, then reaches a plateau. After repeating the same scenario three times, retained memory should not grow by more than roughly 15% each cycle.
- Only one `PlaybackService` and one active MediaSession remain.
- PiP/background playback has no five-second auth or UI retry loop.
- Returning to the app preserves the queue, current item, repeat/shuffle mode, and position.
- Cache diagnostics never exceed 80 entries or 32 MiB.

## In-app diagnostics

On mobile, open Settings and tap the app version seven times. The diagnostic screen includes:

- app and Android versions
- account and Drive token state
- current/recent queue counts
- thumbnail cache entries and decoded bytes
- last HTTP, playback, and sync errors
- sanitized event log copy

On PC, open **Sync & backup** in the sidebar. It includes the app/Windows versions, device ID, account/token state, queue count, last sync error, device queues, recent queues, import history, backups, and a diagnostic-copy action.

Diagnostic logs mask account addresses and do not include access tokens or full media URLs.
