import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_state.dart';
import 'drive_app_data.dart';

void main() {
  runApp(const DriveShuffleApp());
}

const _driveScopes = <String>[
  'https://www.googleapis.com/auth/drive.readonly',
  'https://www.googleapis.com/auth/drive.appdata',
];
const _serverClientId =
    '160619668600-gmrtfcj8gfv3q5t3qr3936qifj453ccb.apps.googleusercontent.com';
const _driveFolderMimeType = 'application/vnd.google-apps.folder';
const _prefsVideosKey = 'library_videos';
const _prefsPlaylistsKey = 'playlists';
const _prefsRecentIdsKey = 'recent_video_ids';
const _prefsTabKey = 'library_tab';
const _prefsSortKey = 'sort_mode';
const _prefsViewModeKey = 'view_mode';
const _prefsPortraitViewModeKey = 'portrait_view_mode';
const _prefsLandscapeViewModeKey = 'landscape_view_mode';
const _prefsResumePlaybackKey = 'resume_playback';
const _prefsTabBarPlacementKey = 'tab_bar_placement';
const _prefsLanguageKey = 'app_language';
const _prefsThemeKey = 'app_theme';
const _prefsPlaybackQueueStateKey = 'playback_queue_state';
const _prefsLastGoogleEmailKey = 'last_google_email';
const _prefsDriveAuthStateKey = 'drive_auth_state';
const _prefsDeviceIdKey = 'cloud_device_id';
const _prefsDeviceNameKey = 'cloud_device_name';
const _prefsCloudSyncMetadataKey = 'cloud_sync_metadata';
const _prefsRecentQueuesKey = 'recent_playback_queues';
const _prefsDriveImportsKey = 'drive_import_history';
const _prefsDiagnosticsKey = 'diagnostic_events';
const _prefsPlaybackFailurePolicyKey = 'playback_failure_policy';
const _prefsRepeatModeKey = 'player_repeat_mode';
const _prefsShuffleEnabledKey = 'player_shuffle_enabled';
const _prefsResizeModeKey = 'player_resize_mode';
const _prefsResumePlaybackUpdatedAtKey = 'resume_playback_updated_at';
const _prefsLastCloudBackupAtKey = 'last_cloud_backup_at';
const _driveImportConcurrency = 4;
const _cloudPlaybackQueueFileName = 'cloud_playback_queue.json';
const _cloudQueuePrefix = 'cloud_playback_queue_v2.';
const _cloudLibraryPrefix = 'cloud_library_state_v1.';
const _cloudBackupPrefix = 'cloud_backup_v1.';

final _themeChoiceNotifier = ValueNotifier(AppThemeChoice.light);

class _Ui {
  static AppThemeChoice themeChoice = AppThemeChoice.light;

  static bool get isDark => themeChoice == AppThemeChoice.dark;

  static Color get bg =>
      isDark ? const Color(0xff101113) : const Color(0xffF5F5F7);
  static Color get card =>
      isDark ? const Color(0xff1A1B1F) : const Color(0xffFFFFFF);
  static Color get surface2 =>
      isDark ? const Color(0xff25272C) : const Color(0xffEFEFEF);
  static Color get text =>
      isDark ? const Color(0xffF4F4F6) : const Color(0xff1C1C1E);
  static Color get text2 =>
      isDark ? const Color(0xffB7B8BE) : const Color(0xff6C6C70);
  static Color get text3 =>
      isDark ? const Color(0xff777A82) : const Color(0xffAEAEB2);
  static const accent = Color(0xff32BF5E);
  static const accentDark = Color(0xff25A34A);
  static const red = Color(0xffFF3B30);
  static const yellow = Color(0xffFF9500);
  static Color get border =>
      isDark ? const Color(0x22FFFFFF) : const Color(0x14000000);
  static Color get accentDim =>
      isDark ? const Color(0x2632BF5E) : const Color(0x1A32BF5E);
}

class DriveShuffleApp extends StatelessWidget {
  const DriveShuffleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeChoice>(
      valueListenable: _themeChoiceNotifier,
      builder: (context, themeChoice, _) {
        _Ui.themeChoice = themeChoice;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '클라우드플레이어',
          theme: ThemeData(
            useMaterial3: false,
            brightness: _Ui.isDark ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor: _Ui.bg,
            fontFamily: 'Inter',
            primaryColor: _Ui.accent,
            colorScheme: ColorScheme(
              brightness: _Ui.isDark ? Brightness.dark : Brightness.light,
              primary: _Ui.accent,
              secondary: _Ui.accentDark,
              tertiary: _Ui.accent,
              surface: _Ui.card,
              error: _Ui.red,
              onPrimary: Colors.white,
              onSecondary: Colors.white,
              onTertiary: Colors.white,
              onSurface: _Ui.text,
              onError: Colors.white,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: _Ui.bg,
              foregroundColor: _Ui.text,
              elevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                color: _Ui.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
              iconTheme: IconThemeData(color: _Ui.text),
            ),
            dividerTheme: DividerThemeData(
              color: _Ui.border,
              thickness: 1,
              space: 1,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: _Ui.surface2,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _Ui.accent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              hintStyle: TextStyle(color: _Ui.text3, fontSize: 13),
            ),
            textTheme: TextTheme(
              headlineSmall: TextStyle(
                color: _Ui.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
              titleMedium: TextStyle(
                color: _Ui.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
              titleSmall: TextStyle(
                color: _Ui.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
              bodyMedium: TextStyle(color: _Ui.text2, fontSize: 13),
              bodySmall: TextStyle(color: _Ui.text2, fontSize: 11),
              labelLarge: TextStyle(
                color: _Ui.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              labelMedium: TextStyle(
                color: _Ui.text2,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              labelSmall: TextStyle(
                color: _Ui.text2,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

enum VideoSource { local, drive }

enum LibraryTab { all, local, drive, playlist, recent }

enum VideoSortMode {
  recentlyAdded,
  name,
  recentlyPlayed,
  source,
  size,
  duration,
}

enum LibraryViewMode { list, grid, grouped }

enum TabBarPlacement { automatic, bottom, landscapeLeft, landscapeRight }

enum AppThemeChoice { light, dark }

enum AppLanguage { ko, en }

class AppStrings {
  const AppStrings(this.language);

  final AppLanguage language;

  bool get isKo => language == AppLanguage.ko;

  String get languageName => isKo ? '\uD55C\uAD6D\uC5B4' : 'English';
  String get settings => isKo ? '\uC124\uC815' : 'Settings';
  String get languageSetting => isKo ? '\uC5B8\uC5B4' : 'Language';
  String get themeSetting => isKo ? '\uD14C\uB9C8' : 'Theme';
  String get lightTheme => isKo ? '\uB77C\uC774\uD2B8' : 'Light';
  String get darkTheme => isKo ? '\uB2E4\uD06C' : 'Dark';
  String get tabBarPlacement =>
      isKo ? '\uD0ED\uBC14 \uC704\uCE58' : 'Tab bar position';
  String get tabBarAutomatic => isKo ? '\uC790\uB3D9' : 'Automatic';
  String get tabBarBottom =>
      isKo ? '\uD56D\uC0C1 \uD558\uB2E8' : 'Always bottom';
  String get tabBarLandscapeLeft =>
      isKo ? '\uAC00\uB85C\uBAA8\uB4DC \uC67C\uCABD' : 'Landscape left';
  String get tabBarLandscapeRight =>
      isKo ? '\uAC00\uB85C\uBAA8\uB4DC \uC624\uB978\uCABD' : 'Landscape right';
  String get portraitViewMode => isKo
      ? '\uC138\uB85C\uBAA8\uB4DC \uBAA9\uB85D \uBCF4\uAE30'
      : 'Portrait view';
  String get landscapeViewMode => isKo
      ? '\uAC00\uB85C\uBAA8\uB4DC \uBAA9\uB85D \uBCF4\uAE30'
      : 'Landscape view';
  String get listViewMode => isKo ? '\uAC00\uB85C \uBAA9\uB85D' : 'List';
  String get gridViewMode => isKo ? '\uADF8\uB9AC\uB4DC' : 'Grid';
  String get resumePlayback =>
      isKo ? '\uC774\uC5B4\uBCF4\uAE30 \uC0AC\uC6A9' : 'Resume playback';
  String get resumePlaybackDescription => isKo
      ? '\uB9C8\uC9C0\uB9C9 \uC7AC\uC0DD \uC704\uCE58\uBD80\uD130 \uB2E4\uC2DC \uC2DC\uC791\uD569\uB2C8\uB2E4.'
      : 'Start again from the last playback position.';
  String get clearResumePositions => isKo
      ? '\uC774\uC5B4\uBCF4\uAE30 \uC704\uCE58 \uCD08\uAE30\uD654'
      : 'Clear resume positions';
  String get clearResumePositionsDescription => isKo
      ? '\uC601\uC0C1 \uBAA9\uB85D\uC740 \uC720\uC9C0\uD558\uACE0 \uC800\uC7A5\uB41C \uC7AC\uC0DD \uC704\uCE58\uB9CC \uC9C0\uC6C1\uB2C8\uB2E4.'
      : 'Keep videos and clear only saved playback positions.';
  String get clearLibrary => isKo
      ? '\uB77C\uC774\uBE0C\uB7EC\uB9AC \uBE44\uC6B0\uAE30'
      : 'Clear library';
  String get clearLibraryDescription => isKo
      ? '\uCD94\uAC00\uD55C \uB85C\uCEEC/Drive \uC601\uC0C1\uC744 \uBAA8\uB450 \uBAA9\uB85D\uC5D0\uC11C \uC81C\uAC70\uD569\uB2C8\uB2E4.'
      : 'Remove all added local and Drive videos.';
  String get playlistCleared => isKo
      ? '\uC7AC\uC0DD \uBAA9\uB85D\uC744 \uBE44\uC6E0\uC2B5\uB2C8\uB2E4.'
      : 'Playlist cleared.';
  String get resumePositionsCleared => isKo
      ? '\uC774\uC5B4\uBCF4\uAE30 \uC704\uCE58\uB97C \uCD08\uAE30\uD654\uD588\uC2B5\uB2C8\uB2E4.'
      : 'Resume positions cleared.';
  String get driveSignInRequired => isKo
      ? 'Google Drive \uB85C\uADF8\uC778\uC774 \uD544\uC694\uD569\uB2C8\uB2E4.'
      : 'Google Drive sign-in is required.';
  String get drivePermissionRequired => isKo
      ? 'Google Drive \uAD8C\uD55C\uC774 \uD544\uC694\uD569\uB2C8\uB2E4.'
      : 'Google Drive permission is required.';
  String get googleAccountNotConnected => isKo
      ? 'Google \uACC4\uC815\uC774 \uC5F0\uACB0\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4.'
      : 'Google account not connected';
  String previousAccount(String email) =>
      isKo ? '\uC774\uC804 \uACC4\uC815: $email' : 'Previous account: $email';
  String connectedAccount(String email) =>
      isKo ? '\uC5F0\uACB0\uB428: $email' : 'Connected: $email';
  String get drivePermissionExpired => isKo
      ? 'Drive \uAD8C\uD55C\uC774 \uB9CC\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uC5F0\uACB0\uD558\uC138\uC694.'
      : 'Drive permission expired. Reconnect.';
  String get reconnectDrivePrompt => isKo
      ? 'Drive\uB97C \uC0AC\uC6A9\uD558\uB824\uBA74 \uB2E4\uC2DC \uC5F0\uACB0\uD558\uC138\uC694.'
      : 'Reconnect to use Drive.';
  String get noVideos =>
      isKo ? '\uC601\uC0C1\uC774 \uC5C6\uC2B5\uB2C8\uB2E4' : 'No videos';
  String get noVideosToPlay => isKo
      ? '\uC7AC\uC0DD\uD560 \uC601\uC0C1\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.'
      : 'No videos to play.';
  String noVideosIn(String tab) => isKo
      ? '$tab\uC5D0 \uC7AC\uC0DD\uD560 \uC601\uC0C1\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.'
      : 'No videos to play in $tab.';
  String get searchVideos =>
      isKo ? '\uC601\uC0C1 \uAC80\uC0C9' : 'Search videos';
  String get playInOrder =>
      isKo ? '\uC21C\uC11C\uB300\uB85C \uC7AC\uC0DD' : 'Play in order';
  String get shufflePlay => isKo ? '\uC154\uD50C \uC7AC\uC0DD' : 'Shuffle play';
  String get importFromDrive =>
      isKo ? 'Drive\uC5D0\uC11C \uAC00\uC838\uC624\uAE30' : 'Import from Drive';
  String get addLocalVideos =>
      isKo ? '\uB85C\uCEEC \uC601\uC0C1 \uCD94\uAC00' : 'Add local videos';
  String get switchAccount =>
      isKo ? '\uACC4\uC815 \uC804\uD658' : 'Switch account';
  String get reconnect => isKo ? '\uB2E4\uC2DC \uC5F0\uACB0' : 'Reconnect';
  String get googleSignIn =>
      isKo ? 'Google \uB85C\uADF8\uC778' : 'Google sign in';
  String get cancelSelection =>
      isKo ? '\uC120\uD0DD \uCDE8\uC18C' : 'Cancel selection';
  String get selectAllVisible => isKo
      ? '\uBCF4\uC774\uB294 \uD56D\uBAA9 \uC804\uCCB4 \uC120\uD0DD'
      : 'Select all visible';
  String get favorite => isKo ? '\uC990\uACA8\uCC3E\uAE30' : 'Favorite';
  String get removeFavorite =>
      isKo ? '\uC990\uACA8\uCC3E\uAE30 \uD574\uC81C' : 'Remove favorite';
  String get removeFromList =>
      isKo ? '\uBAA9\uB85D\uC5D0\uC11C \uC81C\uAC70' : 'Remove from list';
  String get modified => isKo ? '\uC218\uC815\uC77C' : 'Modified';
  String get recentlyPlayed =>
      isKo ? '\uCD5C\uADFC \uC7AC\uC0DD' : 'Recently played';
  String get resumeAt => isKo ? '\uC774\uC5B4\uBCF4\uAE30' : 'Resume';
  String get resume => isKo ? '\uC774\uC5B4\uBCF4\uAE30' : 'Resume';
  String get continueLastVideo => isKo
      ? '\uB9C8\uC9C0\uB9C9 \uC601\uC0C1 \uC774\uC5B4\uBCF4\uAE30'
      : 'Continue last video';
  String get lastWatchedVideo =>
      isKo ? '\uCD5C\uADFC \uBCF8 \uC601\uC0C1' : 'Recently watched';
  String get currentPosition =>
      isKo ? '\uD604\uC7AC \uC704\uCE58' : 'Current position';
  String get noVideoPlaying => isKo
      ? '\uC7AC\uC0DD \uC911\uC778 \uC601\uC0C1\uC774 \uC5C6\uC2B5\uB2C8\uB2E4'
      : 'No video is playing';
  String get currentQueue => isKo ? '\uD604\uC7AC \uD050' : 'Current queue';
  String get queueEmpty => isKo
      ? '\uD604\uC7AC \uD050\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4'
      : 'Queue is empty';
  String get nowPlaying =>
      isKo ? '\uD604\uC7AC \uC7AC\uC0DD \uC911' : 'Now playing';
  String get tapToPlay =>
      isKo ? '\uD0ED\uD574\uC11C \uC7AC\uC0DD' : 'Tap to play';
  String get videoFile => isKo ? '\uC601\uC0C1 \uD30C\uC77C' : 'Video file';
  String get myVideos => isKo ? '\uB0B4 \uC601\uC0C1' : 'My videos';
  String get all => isKo ? '\uC804\uCCB4' : 'All';
  String get local => isKo ? '\uB85C\uCEEC' : 'Local';
  String get drive => 'Drive';
  String get playlist => isKo ? '\uC7AC\uC0DD \uBAA9\uB85D' : 'Playlist';
  String get playlists => isKo ? '\uC7AC\uC0DD \uBAA9\uB85D' : 'Playlists';
  String get createPlaylist =>
      isKo ? '\uC7AC\uC0DD \uBAA9\uB85D \uB9CC\uB4E4\uAE30' : 'Create playlist';
  String get addToPlaylist =>
      isKo ? '\uC7AC\uC0DD \uBAA9\uB85D\uC5D0 \uCD94\uAC00' : 'Add to playlist';
  String get newPlaylist =>
      isKo ? '\uC0C8 \uC7AC\uC0DD \uBAA9\uB85D' : 'New playlist';
  String get playlistName =>
      isKo ? '\uC7AC\uC0DD \uBAA9\uB85D \uC774\uB984' : 'Playlist name';
  String get rename => isKo ? '\uC774\uB984 \uBC14\uAFB8\uAE30' : 'Rename';
  String get delete => isKo ? '\uC0AD\uC81C' : 'Delete';
  String get removeFromPlaylist => isKo
      ? '\uC7AC\uC0DD \uBAA9\uB85D\uC5D0\uC11C \uC81C\uAC70'
      : 'Remove from playlist';
  String get emptyPlaylist =>
      isKo ? '\uBE48 \uC7AC\uC0DD \uBAA9\uB85D' : 'Empty playlist';
  String get localImport =>
      isKo ? '\uB85C\uCEEC \uAC00\uC838\uC624\uAE30' : 'Local import';
  String get driveImport =>
      isKo ? 'Drive \uAC00\uC838\uC624\uAE30' : 'Drive import';
  String get recent => isKo ? '\uCD5C\uADFC' : 'Recent';
  String get recentlyAddedSort =>
      isKo ? '\uCD5C\uADFC \uCD94\uAC00\uC21C' : 'Recently added';
  String get nameSort => isKo ? '\uC774\uB984\uC21C' : 'Name';
  String get recentlyPlayedSort =>
      isKo ? '\uCD5C\uADFC \uC7AC\uC0DD\uC21C' : 'Recently played';
  String get sourceSort => isKo ? '\uCD9C\uCC98\uBCC4' : 'Source';
  String get sizeSort => isKo ? '\uD06C\uAE30\uC21C' : 'Size';
  String get durationSort => isKo ? '\uAE38\uC774\uC21C' : 'Duration';
  String get listView => isKo ? '\uBAA9\uB85D' : 'List';
  String get groupedView => isKo ? '\uADF8\uB8F9' : 'Grouped';
  String get importVideosFromDrive => isKo
      ? 'Google Drive\uC5D0\uC11C \uC601\uC0C1\uC744 \uAC00\uC838\uC624\uC138\uC694'
      : 'Import videos from Google Drive';
  String get noRecentVideos => isKo
      ? '\uC544\uC9C1 \uC7AC\uC0DD\uD55C \uC601\uC0C1\uC774 \uC5C6\uC2B5\uB2C8\uB2E4'
      : 'No recently played videos';
  String get playlistEmpty => isKo
      ? '\uC7AC\uC0DD \uBAA9\uB85D\uC774 \uBE44\uC5B4 \uC788\uC2B5\uB2C8\uB2E4'
      : 'Playlist is empty';
  String playing(String title) =>
      isKo ? '\uC7AC\uC0DD \uC911: $title' : 'Playing: $title';
  String selectedCount(int count) =>
      isKo ? '$count\uAC1C \uC120\uD0DD\uB428' : '$count selected';
  String get unknownError => isKo
      ? '\uC54C \uC218 \uC5C6\uB294 \uC624\uB958\uAC00 \uBC1C\uC0DD\uD588\uC2B5\uB2C8\uB2E4.'
      : 'An unknown error occurred.';
  String get playbackStopped => isKo
      ? '\uC7AC\uC0DD\uC744 \uC911\uC9C0\uD588\uC2B5\uB2C8\uB2E4.'
      : 'Playback stopped.';
  String get playerOpenFailed => isKo
      ? '\uD50C\uB808\uC774\uC5B4\uB97C \uC5F4 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.'
      : 'Player could not be opened.';
  String get driveEmpty => isKo
      ? 'Drive \uD3F4\uB354\uC5D0 \uC601\uC0C1\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.'
      : 'No videos found in Drive.';
  String get driveImportFailed => isKo
      ? 'Drive \uC601\uC0C1 \uAC00\uC838\uC624\uAE30\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.'
      : 'Failed to import Drive videos.';
  String favoriteMarked(int count) => isKo
      ? '$count\uAC1C \uC601\uC0C1\uC744 \uC990\uACA8\uCC3E\uAE30\uC5D0 \uCD94\uAC00\uD588\uC2B5\uB2C8\uB2E4.'
      : '$count videos marked as favorite.';
  String videosRemoved(int count) => isKo
      ? '$count\uAC1C \uC601\uC0C1\uC744 \uC81C\uAC70\uD588\uC2B5\uB2C8\uB2E4.'
      : '$count videos removed.';
  String videoCount(int count) =>
      isKo ? '$count\uAC1C \uC601\uC0C1' : '$count videos';
  String playlistCreated(String name) => isKo
      ? '$name \uC7AC\uC0DD \uBAA9\uB85D\uC744 \uB9CC\uB4E4\uC5C8\uC2B5\uB2C8\uB2E4.'
      : 'Created playlist $name.';
  String addedToPlaylist(int count, String name) => isKo
      ? '$count\uAC1C \uC601\uC0C1\uC744 $name\uC5D0 \uCD94\uAC00\uD588\uC2B5\uB2C8\uB2E4.'
      : 'Added $count videos to $name.';
}

extension on LibraryTab {
  IconData get icon => switch (this) {
    LibraryTab.all => Icons.video_library_outlined,
    LibraryTab.local => Icons.folder_open_outlined,
    LibraryTab.drive => Icons.cloud_outlined,
    LibraryTab.playlist => Icons.queue_music_outlined,
    LibraryTab.recent => Icons.history,
  };
}

class VideoItem {
  const VideoItem({
    required this.id,
    required this.title,
    required this.uri,
    required this.source,
    this.size,
    this.modifiedTime,
    this.duration,
    this.addedAt,
    this.lastPlayedAt,
    this.lastPositionMs = 0,
    this.isFavorite = false,
    this.thumbnailBase64,
    this.thumbnailUrl,
    this.width,
    this.height,
    this.subtitle,
  });

  factory VideoItem.fromJson(Map<String, Object?> json) {
    return VideoItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? "Untitled video",
      uri: json['uri'] as String,
      source: VideoSource.values.byName(json['source'] as String? ?? 'local'),
      size: json['size'] as int?,
      modifiedTime: DateTime.tryParse(json['modifiedTime'] as String? ?? ''),
      duration: json['duration'] as int?,
      addedAt: DateTime.tryParse(json['addedAt'] as String? ?? ''),
      lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? ''),
      lastPositionMs: json['lastPositionMs'] as int? ?? 0,
      isFavorite: json['isFavorite'] as bool? ?? false,
      thumbnailBase64: json['thumbnailBase64'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      subtitle: json['subtitle'] is Map
          ? SubtitleReference.fromJson(
              Map<String, Object?>.from(json['subtitle'] as Map),
            )
          : null,
    );
  }

  final String id;
  final String title;
  final String uri;
  final VideoSource source;
  final int? size;
  final DateTime? modifiedTime;
  final int? duration;
  final DateTime? addedAt;
  final DateTime? lastPlayedAt;
  final int lastPositionMs;
  final bool isFavorite;
  final String? thumbnailBase64;
  final String? thumbnailUrl;
  final int? width;
  final int? height;
  final SubtitleReference? subtitle;

  VideoItem copyWith({
    String? title,
    String? uri,
    int? size,
    DateTime? modifiedTime,
    int? duration,
    DateTime? addedAt,
    DateTime? lastPlayedAt,
    int? lastPositionMs,
    bool? isFavorite,
    String? thumbnailBase64,
    String? thumbnailUrl,
    int? width,
    int? height,
    SubtitleReference? subtitle,
    bool clearSubtitle = false,
  }) {
    return VideoItem(
      id: id,
      title: title ?? this.title,
      uri: uri ?? this.uri,
      source: source,
      size: size ?? this.size,
      modifiedTime: modifiedTime ?? this.modifiedTime,
      duration: duration ?? this.duration,
      addedAt: addedAt ?? this.addedAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      isFavorite: isFavorite ?? this.isFavorite,
      thumbnailBase64: thumbnailBase64 ?? this.thumbnailBase64,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      width: width ?? this.width,
      height: height ?? this.height,
      subtitle: clearSubtitle ? null : subtitle ?? this.subtitle,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'uri': uri,
    'source': source.name,
    'size': size,
    'modifiedTime': modifiedTime?.toIso8601String(),
    'duration': duration,
    'addedAt': addedAt?.toIso8601String(),
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    'lastPositionMs': lastPositionMs,
    'isFavorite': isFavorite,
    'thumbnailBase64': thumbnailBase64,
    'thumbnailUrl': thumbnailUrl,
    'width': width,
    'height': height,
    'subtitle': subtitle?.toJson(),
  };

  Map<String, Object?> toPlaybackMap() => {
    'id': id,
    'title': title,
    'uri': uri,
    'source': source.name,
    'subtitle': subtitle?.toJson(),
  };
}

class VideoPlaylist {
  const VideoPlaylist({
    required this.id,
    required this.name,
    required this.videoIds,
    required this.createdAt,
    required this.updatedAt,
    required this.sourceLabel,
  });

  factory VideoPlaylist.fromJson(Map<String, Object?> json) {
    return VideoPlaylist(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Playlist',
      videoIds: (json['videoIds'] as List<Object?>? ?? const []).cast<String>(),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      sourceLabel: json['sourceLabel'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final List<String> videoIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String sourceLabel;

  VideoPlaylist copyWith({
    String? name,
    List<String>? videoIds,
    DateTime? updatedAt,
    String? sourceLabel,
  }) {
    return VideoPlaylist(
      id: id,
      name: name ?? this.name,
      videoIds: videoIds ?? this.videoIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceLabel: sourceLabel ?? this.sourceLabel,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'videoIds': videoIds,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'sourceLabel': sourceLabel,
  };
}

class PlaybackStateSummary {
  const PlaybackStateSummary({
    required this.queue,
    required this.currentIndex,
    required this.isPlaying,
    this.positionMs = 0,
    this.durationMs = 0,
    this.repeatMode = PlayerRepeatMode.all,
    this.shuffleEnabled = false,
    this.originalQueue = const [],
  });

  final List<VideoItem> queue;
  final int currentIndex;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final PlayerRepeatMode repeatMode;
  final bool shuffleEnabled;
  final List<VideoItem> originalQueue;

  VideoItem? get current =>
      queue.isEmpty || currentIndex < 0 || currentIndex >= queue.length
      ? null
      : queue[currentIndex];

  Map<String, Object?> toQueueStateJson({DateTime? updatedAt}) {
    final safeIndex = queue.isEmpty
        ? 0
        : currentIndex.clamp(0, queue.length - 1).toInt();
    return {
      'queueIds': queue.map((item) => item.id).toList(growable: false),
      'currentIndex': safeIndex,
      'currentVideoId': queue.isEmpty ? null : queue[safeIndex].id,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'isPlaying': isPlaying,
      'repeatMode': repeatMode.name,
      'shuffleEnabled': shuffleEnabled,
      'originalQueueIds': (originalQueue.isEmpty ? queue : originalQueue)
          .map((item) => item.id)
          .toList(growable: false),
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  static PlaybackStateSummary? fromQueueStateJson(
    Map<String, Object?> json,
    List<VideoItem> library,
  ) {
    final queueIds = (json['queueIds'] as List?)?.whereType<String>().toList(
      growable: false,
    );
    if (queueIds == null || queueIds.isEmpty) return null;
    final libraryById = {for (final item in library) item.id: item};
    final queue = queueIds
        .map((id) => libraryById[id])
        .whereType<VideoItem>()
        .toList(growable: false);
    if (queue.isEmpty) return null;

    final currentVideoId = json['currentVideoId'] as String?;
    final savedIndex = (json['currentIndex'] as num?)?.toInt() ?? 0;
    final currentIndexFromId = currentVideoId == null
        ? -1
        : queue.indexWhere((item) => item.id == currentVideoId);
    final currentIndex = currentIndexFromId >= 0
        ? currentIndexFromId
        : savedIndex.clamp(0, queue.length - 1).toInt();
    final originalQueueIds =
        (json['originalQueueIds'] as List?)?.whereType<String>().toList() ??
        queueIds;
    final originalQueue = originalQueueIds
        .map((id) => libraryById[id])
        .whereType<VideoItem>()
        .toList(growable: false);
    return PlaybackStateSummary(
      queue: queue,
      currentIndex: currentIndex,
      isPlaying: json['isPlaying'] as bool? ?? false,
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      repeatMode: PlayerRepeatMode.values.firstWhere(
        (value) => value.name == json['repeatMode'],
        orElse: () => PlayerRepeatMode.all,
      ),
      shuffleEnabled: json['shuffleEnabled'] as bool? ?? false,
      originalQueue: originalQueue,
    );
  }
}

enum DriveEntryType { folder, video, subtitle }

class DriveEntry {
  const DriveEntry({
    required this.id,
    required this.name,
    required this.type,
    required this.mimeType,
    this.modifiedTime,
    this.size,
    this.duration,
    this.thumbnailUrl,
    this.width,
    this.height,
  });

  final String id;
  final String name;
  final DriveEntryType type;
  final String mimeType;
  final DateTime? modifiedTime;
  final int? size;
  final int? duration;
  final String? thumbnailUrl;
  final int? width;
  final int? height;

  bool get isFolder => type == DriveEntryType.folder;
  bool get isVideo => type == DriveEntryType.video;
  bool get isSubtitle => type == DriveEntryType.subtitle;

  VideoItem toVideoItem({SubtitleReference? subtitle}) {
    return VideoItem(
      id: 'drive:$id',
      title: name,
      uri: 'https://www.googleapis.com/drive/v3/files/$id?alt=media',
      source: VideoSource.drive,
      size: size,
      modifiedTime: modifiedTime,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      width: width,
      height: height,
      subtitle: subtitle,
      addedAt: DateTime.now(),
    );
  }
}

class DriveImportResult {
  const DriveImportResult({
    required this.items,
    required this.sourceName,
    required this.sourceFolders,
    required this.foldersScanned,
    required this.videosFound,
    required this.createPlaylist,
  });

  factory DriveImportResult.singleVideo(DriveEntry entry) {
    return DriveImportResult(
      items: [entry.toVideoItem()],
      sourceName: entry.name,
      sourceFolders: const {},
      foldersScanned: 0,
      videosFound: 1,
      createPlaylist: false,
    );
  }

  final List<VideoItem> items;
  final String sourceName;
  final Map<String, String> sourceFolders;
  final int foldersScanned;
  final int videosFound;
  final bool createPlaylist;
}

class DriveImportProgress {
  const DriveImportProgress({
    required this.foldersScanned,
    required this.videosFound,
    required this.currentFolderName,
  });

  final int foldersScanned;
  final int videosFound;
  final String currentFolderName;
}

class _CloudBackupEntry {
  const _CloudBackupEntry({required this.file, required this.payload});

  final DriveAppDataFile file;
  final CloudBackupPayload payload;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _playback = MethodChannel('drive_shuffle_player/playback');

  final _signIn = GoogleSignIn.instance;
  final _random = Random();
  final _searchController = TextEditingController();
  late final DriveAppDataStore _driveAppData;
  Timer? _playbackSyncTimer;
  Timer? _cloudPullTimer;
  Timer? _cloudUploadDebounce;
  DateTime? _lastPlaybackStatePersistAt;
  DateTime? _lastDriveReconnectPromptAt;
  DateTime? _lastLocalPlaybackQueueUpdatedAt;
  String? _lastPersistedPlaybackMediaId;
  int? _lastPersistedPlaybackPositionMs;
  String? _lastPersistedPlaybackQueueSignature;
  String? _lastNativePlaybackErrorSignature;
  String? _cloudQueueFileId;
  String? _cloudLibraryFileId;
  String? _lastUploadedCloudQueueSignature;
  String? _lastUploadedCloudLibrarySignature;
  Completer<void>? _cloudSyncCompleter;
  String? _visibleVideosCacheKey;
  List<VideoItem>? _visibleVideosCache;

  GoogleSignInAccount? _user;
  String? _accessToken;
  final List<VideoItem> _videos = [];
  final List<VideoPlaylist> _playlists = [];
  final List<String> _recentIds = [];
  final List<RecentQueueSnapshot> _recentQueues = [];
  final List<DriveImportRecord> _driveImports = [];
  final List<DiagnosticEvent> _diagnosticEvents = [];
  final Map<String, DateTime> _videoSyncUpdatedAt = {};
  final Map<String, DateTime> _videoDeletedAt = {};
  final Map<String, DateTime> _playlistDeletedAt = {};
  final Set<String> _selectedIds = {};
  PlaybackStateSummary? _playbackSummary;
  CloudPlaybackState? _remoteQueueCandidate;
  List<CloudPlaybackState> _knownDeviceQueues = const [];
  SyncHealth _syncHealth = const SyncHealth();
  String _deviceId = '';
  String _deviceName = 'Android device';
  String _appVersion = '1.0.0+1';
  String _androidVersion = 'Unknown';
  bool _diagnosticsUnlocked = false;
  int _versionTapCount = 0;
  DateTime? _resumePlaybackUpdatedAt;
  DateTime? _lastCloudBackupAt;
  PlaybackFailurePolicy _playbackFailurePolicy = PlaybackFailurePolicy.ask;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.all;
  bool _shuffleEnabled = false;
  String _resizeMode = 'fit';
  LibraryTab _selectedTab = LibraryTab.all;
  String? _selectedPlaylistId;
  VideoSortMode _sortMode = VideoSortMode.recentlyAdded;
  LibraryViewMode _portraitViewMode = LibraryViewMode.list;
  LibraryViewMode _landscapeViewMode = LibraryViewMode.grid;
  TabBarPlacement _tabBarPlacement = TabBarPlacement.automatic;
  AppLanguage _language = AppLanguage.ko;
  AppThemeChoice _themeChoice = AppThemeChoice.light;
  bool _resumePlayback = true;
  bool _searchActive = false;
  bool _refreshingDriveToken = false;
  bool _syncingCloudQueue = false;
  bool _syncingCloudLibrary = false;
  bool _driveReconnectDialogOpen = false;
  String? _lastGoogleEmail;
  bool _driveAuthExpired = false;
  bool _initializing = true;
  bool _busy = false;
  String _query = '';
  String _status = '클라우드플레이어';

  AppStrings get t => AppStrings(_language);
  static const _playbackPersistInterval = Duration(seconds: 10);
  static const _driveReconnectPromptCooldown = Duration(seconds: 60);

  String _tabLabel(LibraryTab tab) => switch (tab) {
    LibraryTab.all => t.all,
    LibraryTab.local => t.local,
    LibraryTab.drive => t.drive,
    LibraryTab.playlist => t.playlist,
    LibraryTab.recent => t.recent,
  };

  VideoItem? get _lastPlaybackCandidate {
    final candidates =
        _videos.where((item) => item.lastPlayedAt != null).toList()
          ..sort((a, b) => _compareDateDesc(a.lastPlayedAt, b.lastPlayedAt));
    return candidates.isEmpty ? null : candidates.first;
  }

  @override
  void initState() {
    super.initState();
    _driveAppData = DriveAppDataStore(tokenProvider: _provideDriveToken);
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim());
    });
    _playbackSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_videos.isNotEmpty && (_playbackSummary?.current != null)) {
        unawaited(_syncPlaybackState());
      }
    });
    _cloudPullTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_accessToken != null && !_busy) {
        unawaited(_syncAllCloudState(pullOnly: true));
      }
    });
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    unawaited(_syncPlaybackState(forcePersist: true));
    _playbackSyncTimer?.cancel();
    _cloudPullTimer?.cancel();
    _cloudUploadDebounce?.cancel();
    _driveAppData.close();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(
        _syncPlaybackState(forcePersist: state != AppLifecycleState.resumed),
      );
    }
  }

  Future<void> _bootstrap() async {
    await _loadLibraryState();
    await _loadPlatformInfo();
    await _initializeGoogleSignIn();
  }

  Future<void> _loadPlatformInfo() async {
    try {
      final info = await _playback.invokeMapMethod<String, Object?>(
        'getPlatformInfo',
      );
      final model = info?['model'] as String?;
      final appVersion = info?['appVersion'] as String?;
      final androidVersion = info?['androidVersion'] as String?;
      if (mounted) {
        setState(() {
          if (model != null && model.trim().isNotEmpty) {
            _deviceName = model.trim();
          }
          if (appVersion != null && appVersion.isNotEmpty) {
            _appVersion = appVersion;
          }
          if (androidVersion != null && androidVersion.isNotEmpty) {
            _androidVersion = androidVersion;
          }
        });
      }
    } catch (_) {
      // The persisted fallback remains usable on older native builds.
    }
  }

  Future<void> _loadLibraryState() async {
    final prefs = await SharedPreferences.getInstance();
    final videosJson = prefs.getString(_prefsVideosKey);
    final playlistsJson = prefs.getString(_prefsPlaylistsKey);
    final recentIds = prefs.getStringList(_prefsRecentIdsKey) ?? const [];
    final tabName = prefs.getString(_prefsTabKey);
    final sortName = prefs.getString(_prefsSortKey);
    final legacyViewModeName = prefs.getString(_prefsViewModeKey);
    final portraitViewModeName = prefs.getString(_prefsPortraitViewModeKey);
    final landscapeViewModeName = prefs.getString(_prefsLandscapeViewModeKey);
    final tabBarPlacementName = prefs.getString(_prefsTabBarPlacementKey);
    final languageName = prefs.getString(_prefsLanguageKey);
    final themeName = prefs.getString(_prefsThemeKey);
    final playbackQueueJson = prefs.getString(_prefsPlaybackQueueStateKey);
    final lastGoogleEmail = prefs.getString(_prefsLastGoogleEmailKey);
    final driveAuthState = prefs.getString(_prefsDriveAuthStateKey);
    final resumePlayback = prefs.getBool(_prefsResumePlaybackKey) ?? true;
    final persistedDeviceId = prefs.getString(_prefsDeviceIdKey);
    final persistedDeviceName = prefs.getString(_prefsDeviceNameKey);
    final syncMetadataJson = prefs.getString(_prefsCloudSyncMetadataKey);
    final recentQueuesJson = prefs.getString(_prefsRecentQueuesKey);
    final driveImportsJson = prefs.getString(_prefsDriveImportsKey);
    final diagnosticsJson = prefs.getString(_prefsDiagnosticsKey);
    final failurePolicyName = prefs.getString(_prefsPlaybackFailurePolicyKey);
    final repeatModeName = prefs.getString(_prefsRepeatModeKey);
    final shuffleEnabled = prefs.getBool(_prefsShuffleEnabledKey) ?? false;
    final resizeMode = prefs.getString(_prefsResizeModeKey) ?? 'fit';
    final resumePlaybackUpdatedAt = DateTime.tryParse(
      prefs.getString(_prefsResumePlaybackUpdatedAtKey) ?? '',
    );
    final lastCloudBackupAt = DateTime.tryParse(
      prefs.getString(_prefsLastCloudBackupAtKey) ?? '',
    );
    final generatedDeviceId =
        persistedDeviceId ??
        'android:${DateTime.now().microsecondsSinceEpoch}:${_random.nextInt(1 << 31)}';

    setState(() {
      if (videosJson != null && videosJson.isNotEmpty) {
        final decoded = jsonDecode(videosJson) as List<Object?>;
        _videos
          ..clear()
          ..addAll(
            decoded.cast<Map<String, Object?>>().map(VideoItem.fromJson),
          );
      }
      if (playlistsJson != null && playlistsJson.isNotEmpty) {
        final decoded = jsonDecode(playlistsJson) as List<Object?>;
        _playlists
          ..clear()
          ..addAll(
            decoded.cast<Map<String, Object?>>().map(VideoPlaylist.fromJson),
          );
      }
      _recentIds
        ..clear()
        ..addAll(recentIds);
      _selectedTab = LibraryTab.values.firstWhere(
        (tab) => tab.name == tabName,
        orElse: () => LibraryTab.all,
      );
      _sortMode = VideoSortMode.values.firstWhere(
        (mode) => mode.name == sortName,
        orElse: () => VideoSortMode.recentlyAdded,
      );
      _portraitViewMode = LibraryViewMode.values.firstWhere(
        (mode) => mode.name == (portraitViewModeName ?? legacyViewModeName),
        orElse: () => LibraryViewMode.list,
      );
      _landscapeViewMode = LibraryViewMode.values.firstWhere(
        (mode) => mode.name == landscapeViewModeName,
        orElse: () => LibraryViewMode.grid,
      );
      _tabBarPlacement = TabBarPlacement.values.firstWhere(
        (placement) => placement.name == tabBarPlacementName,
        orElse: () => TabBarPlacement.automatic,
      );
      _language = AppLanguage.values.firstWhere(
        (language) => language.name == languageName,
        orElse: () => AppLanguage.ko,
      );
      _themeChoice = AppThemeChoice.values.firstWhere(
        (choice) => choice.name == themeName,
        orElse: () => AppThemeChoice.light,
      );
      _themeChoiceNotifier.value = _themeChoice;
      _lastGoogleEmail = lastGoogleEmail;
      _driveAuthExpired = driveAuthState == 'expired';
      _resumePlayback = resumePlayback;
      _deviceId = generatedDeviceId;
      _deviceName = persistedDeviceName?.trim().isNotEmpty == true
          ? persistedDeviceName!.trim()
          : 'Android device';
      _resumePlaybackUpdatedAt =
          resumePlaybackUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      _lastCloudBackupAt = lastCloudBackupAt;
      _playbackFailurePolicy = PlaybackFailurePolicy.values.firstWhere(
        (value) => value.name == failurePolicyName,
        orElse: () => PlaybackFailurePolicy.ask,
      );
      _repeatMode = PlayerRepeatMode.values.firstWhere(
        (value) => value.name == repeatModeName,
        orElse: () => PlayerRepeatMode.all,
      );
      _shuffleEnabled = shuffleEnabled;
      _resizeMode = resizeMode;
      if (syncMetadataJson != null && syncMetadataJson.isNotEmpty) {
        try {
          final metadata = Map<String, Object?>.from(
            jsonDecode(syncMetadataJson) as Map,
          );
          _videoSyncUpdatedAt
            ..clear()
            ..addAll(_decodeDateMap(metadata['videoUpdatedAt']));
          _videoDeletedAt
            ..clear()
            ..addAll(_decodeDateMap(metadata['videoDeletedAt']));
          _playlistDeletedAt
            ..clear()
            ..addAll(_decodeDateMap(metadata['playlistDeletedAt']));
        } catch (_) {
          _videoSyncUpdatedAt.clear();
          _videoDeletedAt.clear();
          _playlistDeletedAt.clear();
        }
      }
      if (recentQueuesJson != null && recentQueuesJson.isNotEmpty) {
        try {
          _recentQueues
            ..clear()
            ..addAll(
              (jsonDecode(recentQueuesJson) as List).whereType<Map>().map(
                (item) => RecentQueueSnapshot.fromJson(
                  Map<String, Object?>.from(item),
                ),
              ),
            );
        } catch (_) {
          _recentQueues.clear();
        }
      }
      if (driveImportsJson != null && driveImportsJson.isNotEmpty) {
        try {
          _driveImports
            ..clear()
            ..addAll(
              (jsonDecode(driveImportsJson) as List).whereType<Map>().map(
                (item) => DriveImportRecord.fromJson(
                  Map<String, Object?>.from(item),
                  fallbackDeviceId: generatedDeviceId,
                ),
              ),
            );
        } catch (_) {
          _driveImports.clear();
        }
      }
      if (diagnosticsJson != null && diagnosticsJson.isNotEmpty) {
        try {
          _diagnosticEvents
            ..clear()
            ..addAll(
              (jsonDecode(diagnosticsJson) as List).whereType<Map>().map(
                (item) =>
                    DiagnosticEvent.fromJson(Map<String, Object?>.from(item)),
              ),
            );
        } catch (_) {
          _diagnosticEvents.clear();
        }
      }
      if (playbackQueueJson != null && playbackQueueJson.isNotEmpty) {
        try {
          final decoded = Map<String, Object?>.from(
            jsonDecode(playbackQueueJson) as Map,
          );
          _playbackSummary = PlaybackStateSummary.fromQueueStateJson(
            decoded,
            _videos,
          );
          _lastLocalPlaybackQueueUpdatedAt = DateTime.tryParse(
            decoded['updatedAt'] as String? ?? '',
          );
        } catch (_) {
          _playbackSummary = null;
          _lastLocalPlaybackQueueUpdatedAt = null;
        }
      }
    });
  }

  Future<void> _saveLibraryState() async {
    _invalidateVisibleVideos();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsVideosKey,
      jsonEncode(_videos.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(
      _prefsPlaylistsKey,
      jsonEncode(_playlists.map((item) => item.toJson()).toList()),
    );
    await prefs.setStringList(_prefsRecentIdsKey, _recentIds);
    await prefs.setString(_prefsTabKey, _selectedTab.name);
    await prefs.setString(_prefsSortKey, _sortMode.name);
    await prefs.setString(_prefsViewModeKey, _portraitViewMode.name);
    await prefs.setString(_prefsPortraitViewModeKey, _portraitViewMode.name);
    await prefs.setString(_prefsLandscapeViewModeKey, _landscapeViewMode.name);
    await prefs.setString(_prefsTabBarPlacementKey, _tabBarPlacement.name);
    await prefs.setString(_prefsLanguageKey, _language.name);
    await prefs.setString(_prefsThemeKey, _themeChoice.name);
    await prefs.setString(_prefsDeviceIdKey, _deviceId);
    await prefs.setString(_prefsDeviceNameKey, _deviceName);
    await prefs.setString(
      _prefsCloudSyncMetadataKey,
      jsonEncode({
        'videoUpdatedAt': _encodeDateMap(_videoSyncUpdatedAt),
        'videoDeletedAt': _encodeDateMap(_videoDeletedAt),
        'playlistDeletedAt': _encodeDateMap(_playlistDeletedAt),
      }),
    );
    await prefs.setString(
      _prefsRecentQueuesKey,
      jsonEncode(_recentQueues.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(
      _prefsDriveImportsKey,
      jsonEncode(_driveImports.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(
      _prefsDiagnosticsKey,
      jsonEncode(_diagnosticEvents.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(
      _prefsPlaybackFailurePolicyKey,
      _playbackFailurePolicy.name,
    );
    await prefs.setString(_prefsRepeatModeKey, _repeatMode.name);
    await prefs.setBool(_prefsShuffleEnabledKey, _shuffleEnabled);
    await prefs.setString(_prefsResizeModeKey, _resizeMode);
    await prefs.setString(
      _prefsResumePlaybackUpdatedAtKey,
      (_resumePlaybackUpdatedAt ?? DateTime.now()).toIso8601String(),
    );
    if (_lastCloudBackupAt == null) {
      await prefs.remove(_prefsLastCloudBackupAtKey);
    } else {
      await prefs.setString(
        _prefsLastCloudBackupAtKey,
        _lastCloudBackupAt!.toUtc().toIso8601String(),
      );
    }
    final playbackSummary = _playbackSummary;
    if (playbackSummary == null || playbackSummary.queue.isEmpty) {
      await prefs.remove(_prefsPlaybackQueueStateKey);
    } else {
      await prefs.setString(
        _prefsPlaybackQueueStateKey,
        jsonEncode(
          playbackSummary.toQueueStateJson(
            updatedAt: _lastLocalPlaybackQueueUpdatedAt,
          ),
        ),
      );
    }
    if (_lastGoogleEmail == null || _lastGoogleEmail!.isEmpty) {
      await prefs.remove(_prefsLastGoogleEmailKey);
    } else {
      await prefs.setString(_prefsLastGoogleEmailKey, _lastGoogleEmail!);
    }
    await prefs.setString(
      _prefsDriveAuthStateKey,
      _driveAuthExpired ? 'expired' : 'ready',
    );
    await prefs.setBool(_prefsResumePlaybackKey, _resumePlayback);
  }

  Map<String, DateTime> _decodeDateMap(Object? value) {
    if (value is! Map) return <String, DateTime>{};
    final result = <String, DateTime>{};
    for (final entry in value.entries) {
      final parsed = DateTime.tryParse(entry.value?.toString() ?? '');
      if (parsed != null) result[entry.key.toString()] = parsed;
    }
    return result;
  }

  Map<String, String> _encodeDateMap(Map<String, DateTime> value) => {
    for (final entry in value.entries)
      entry.key: entry.value.toUtc().toIso8601String(),
  };

  Future<void> _syncPlaybackState({bool forcePersist = false}) async {
    try {
      if (!mounted || _videos.isEmpty) return;
      final state = await _playback.invokeMapMethod<String, Object?>(
        'getPlaybackState',
      );
      if (state == null) return;
      final mediaId = state['mediaId'] as String?;
      final queueIds = (state['queueIds'] as List?)?.whereType<String>().toList(
        growable: false,
      );
      final mediaItemCount = (state['mediaItemCount'] as num?)?.toInt() ?? 0;
      _handleNativePlaybackError(state);
      if (mediaId == null || mediaItemCount <= 0) return;

      final positionMs = (state['positionMs'] as num?)?.toInt() ?? 0;
      final durationMs = (state['durationMs'] as num?)?.toInt() ?? 0;
      final isPlaying = state['isPlaying'] as bool? ?? false;
      final nativeIndex = (state['currentIndex'] as num?)?.toInt() ?? 0;
      final nativeRepeatMode = _repeatModeFromNative(
        (state['repeatMode'] as num?)?.toInt(),
      );
      final nativeShuffleEnabled =
          state['shuffleEnabled'] as bool? ??
          _playbackSummary?.shuffleEnabled ??
          _shuffleEnabled;
      final savedPositionMs = durationMs > 0 && durationMs - positionMs <= 10000
          ? 0
          : positionMs;

      final nativeSubtitle = state['subtitle'] is Map
          ? SubtitleReference.fromJson(
              Map<String, Object?>.from(state['subtitle'] as Map),
            )
          : null;
      final libraryIndex = _videos.indexWhere((item) => item.id == mediaId);
      final summary = _playbackSummary;
      final libraryById = {for (final item in _videos) item.id: item};
      final existingItem = libraryById[mediaId];
      final subtitleChanged =
          nativeSubtitle != null &&
          existingItem != null &&
          (existingItem.subtitle?.uri != nativeSubtitle.uri ||
              existingItem.subtitle?.mimeType != nativeSubtitle.mimeType);
      if (subtitleChanged) {
        libraryById[mediaId] = existingItem.copyWith(subtitle: nativeSubtitle);
      }
      final shouldKeepSavedMultiQueue =
          queueIds != null &&
          queueIds.length <= 1 &&
          summary != null &&
          summary.queue.length > 1;
      final effectiveQueueIds = shouldKeepSavedMultiQueue
          ? summary.queue.map((item) => item.id).toList(growable: false)
          : queueIds;
      final shouldPersist = _shouldPersistPlaybackSnapshot(
        mediaId,
        savedPositionMs,
        queueIds: effectiveQueueIds,
        forcePersist: forcePersist,
      );
      if (!mounted) return;
      setState(() {
        if (libraryIndex >= 0) {
          _videos[libraryIndex] =
              (libraryById[mediaId] ?? _videos[libraryIndex]).copyWith(
                lastPositionMs: savedPositionMs,
                duration: durationMs > 0
                    ? durationMs
                    : _videos[libraryIndex].duration,
                lastPlayedAt: DateTime.now(),
              );
          _invalidateVisibleVideos();
        }
        final syncedQueue =
            queueIds == null || queueIds.isEmpty || shouldKeepSavedMultiQueue
            ? summary?.queue
            : queueIds
                  .map((id) => libraryById[id])
                  .whereType<VideoItem>()
                  .toList(growable: false);
        if (syncedQueue != null && syncedQueue.isNotEmpty) {
          final queueIndex = syncedQueue.indexWhere(
            (item) => item.id == mediaId,
          );
          final resolvedIndex = queueIndex >= 0
              ? queueIndex
              : shouldKeepSavedMultiQueue
              ? summary.currentIndex.clamp(0, syncedQueue.length - 1)
              : nativeIndex.clamp(0, syncedQueue.length - 1);
          final resolvedPositionMs =
              queueIndex >= 0 || !shouldKeepSavedMultiQueue
              ? savedPositionMs
              : summary.positionMs;
          final resolvedDurationMs =
              queueIndex >= 0 || !shouldKeepSavedMultiQueue
              ? durationMs
              : summary.durationMs;
          _playbackSummary = PlaybackStateSummary(
            queue: syncedQueue,
            currentIndex: resolvedIndex,
            isPlaying: isPlaying,
            positionMs: resolvedPositionMs,
            durationMs: resolvedDurationMs,
            repeatMode: nativeRepeatMode,
            shuffleEnabled: nativeShuffleEnabled,
            originalQueue: summary?.originalQueue ?? const [],
          );
          _repeatMode = nativeRepeatMode;
          _shuffleEnabled = nativeShuffleEnabled;
        }
      });
      if (shouldPersist || subtitleChanged) {
        if (libraryIndex >= 0 &&
            _videos[libraryIndex].source == VideoSource.drive) {
          _markCloudVideoChanged(mediaId);
        }
        _rememberPersistedPlaybackSnapshot(
          mediaId,
          savedPositionMs,
          queueIds: effectiveQueueIds,
        );
        await _saveLibraryState();
        unawaited(_syncPlaybackQueueToDrive());
        _scheduleCloudLibrarySync();
      }
    } catch (_) {
      // Sync is opportunistic; playback controls still work if the session is gone.
    }
  }

  void _handleNativePlaybackError(Map<String, Object?> state) {
    final kindName = state['lastErrorKind'] as String?;
    final authError = state['authError'] as bool? ?? false;
    if (kindName == null && !authError) {
      _lastNativePlaybackErrorSignature = null;
      return;
    }
    final resolvedName = kindName ?? 'authRequired';
    final message = state['lastErrorMessage'] as String? ?? resolvedName;
    final mediaId = state['lastErrorMediaId'] as String? ?? '';
    final signature = '$resolvedName\u001f$mediaId\u001f$message';
    if (_lastNativePlaybackErrorSignature == signature) return;
    _lastNativePlaybackErrorSignature = signature;
    final kind = _driveFailureKindFromNative(resolvedName);
    _recordDiagnostic(
      'playback',
      message,
      failureKind: kind,
      httpStatus: (state['httpStatusCode'] as num?)?.toInt(),
    );
    if (kind == DriveFailureKind.authRequired || authError) {
      unawaited(_recoverDrivePlaybackAuth());
    }
  }

  DriveFailureKind _driveFailureKindFromNative(String value) => switch (value) {
    'authRequired' => DriveFailureKind.authRequired,
    'accessDenied' => DriveFailureKind.accessDenied,
    'fileMissing' => DriveFailureKind.fileMissing,
    'network' => DriveFailureKind.network,
    'rateLimited' => DriveFailureKind.rateLimited,
    'server' => DriveFailureKind.server,
    _ => DriveFailureKind.unknown,
  };

  PlayerRepeatMode _repeatModeFromNative(int? mode) => switch (mode) {
    0 => PlayerRepeatMode.off,
    1 => PlayerRepeatMode.one,
    2 => PlayerRepeatMode.all,
    _ => _playbackSummary?.repeatMode ?? _repeatMode,
  };

  bool _shouldPersistPlaybackSnapshot(
    String mediaId,
    int positionMs, {
    List<String>? queueIds,
    required bool forcePersist,
  }) {
    if (forcePersist) return true;
    if (_lastPersistedPlaybackMediaId != mediaId) return true;
    final queueSignature = queueIds?.join('\u001f');
    if (queueSignature != null &&
        queueSignature != _lastPersistedPlaybackQueueSignature) {
      return true;
    }
    final lastPosition = _lastPersistedPlaybackPositionMs;
    final lastPersistedAt = _lastPlaybackStatePersistAt;
    if (lastPosition == null || lastPersistedAt == null) return true;
    final movedEnough =
        (positionMs - lastPosition).abs() >=
        _playbackPersistInterval.inMilliseconds;
    final waitedEnough =
        DateTime.now().difference(lastPersistedAt) >= _playbackPersistInterval;
    return movedEnough && waitedEnough;
  }

  void _rememberPersistedPlaybackSnapshot(
    String mediaId,
    int positionMs, {
    List<String>? queueIds,
  }) {
    _lastLocalPlaybackQueueUpdatedAt = DateTime.now();
    _lastPersistedPlaybackMediaId = mediaId;
    _lastPersistedPlaybackPositionMs = positionMs;
    _lastPersistedPlaybackQueueSignature = queueIds?.join('\u001f');
    _lastPlaybackStatePersistAt = DateTime.now();
  }

  void _rememberPlaybackQueueChanged() {
    _lastLocalPlaybackQueueUpdatedAt = DateTime.now();
    final summary = _playbackSummary;
    if (summary != null && summary.queue.isNotEmpty) {
      _recordRecentQueue(summary);
    }
  }

  Future<String?> _provideDriveToken({required bool forceRefresh}) async {
    if (forceRefresh) {
      await _refreshDriveAccessTokenSilently(clearCurrentToken: true);
    } else if (_accessToken == null || _accessToken!.isEmpty) {
      await _refreshDriveAccessTokenSilently();
    }
    return _accessToken;
  }

  void _recordDiagnostic(
    String category,
    String message, {
    DriveFailureKind? failureKind,
    int? httpStatus,
  }) {
    final sanitized = message
        .replaceAll(RegExp(r'https?://\S+'), '<url>')
        .replaceAll(RegExp(r'[\w.+-]+@[\w.-]+'), '<account>');
    _diagnosticEvents.insert(
      0,
      DiagnosticEvent(
        timestamp: DateTime.now(),
        category: category,
        message: sanitized,
        failureKind: failureKind,
        httpStatus: httpStatus,
      ),
    );
    if (_diagnosticEvents.length > 50) {
      _diagnosticEvents.removeRange(50, _diagnosticEvents.length);
    }
  }

  String _driveFailureMessage(DriveFailureKind kind) => switch (kind) {
    DriveFailureKind.authRequired => t.reconnectDrivePrompt,
    DriveFailureKind.accessDenied =>
      _language == AppLanguage.ko
          ? '\uC774 \uACC4\uC815\uC73C\uB85C \uC811\uADFC \uAD8C\uD55C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.'
          : 'This account does not have access.',
    DriveFailureKind.fileMissing =>
      _language == AppLanguage.ko
          ? 'Drive\uC5D0\uC11C \uD30C\uC77C\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.'
          : 'The file could not be found in Drive.',
    DriveFailureKind.network =>
      _language == AppLanguage.ko
          ? '\uC778\uD130\uB137 \uC5F0\uACB0 \uD6C4 \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694.'
          : 'Connect to the internet and try again.',
    DriveFailureKind.rateLimited =>
      _language == AppLanguage.ko
          ? 'Drive \uC694\uCCAD\uC774 \uB9CE\uC544 \uC7A0\uC2DC \uD6C4 \uB2E4\uC2DC \uC2DC\uB3C4\uD569\uB2C8\uB2E4.'
          : 'Drive is busy. Try again shortly.',
    DriveFailureKind.server =>
      _language == AppLanguage.ko
          ? 'Drive \uC11C\uBC84 \uC624\uB958\uC785\uB2C8\uB2E4. \uC7A0\uC2DC \uD6C4 \uB2E4\uC2DC \uC2DC\uB3C4\uD558\uC138\uC694.'
          : 'Drive server error. Try again shortly.',
    DriveFailureKind.unknown => t.unknownError,
  };

  void _setSyncFailure(DriveApiException error) {
    final phase = error.kind == DriveFailureKind.authRequired
        ? SyncPhase.reconnectRequired
        : error.kind == DriveFailureKind.network
        ? SyncPhase.offline
        : SyncPhase.failed;
    if (mounted) {
      setState(() {
        _syncHealth = _syncHealth.copyWith(
          phase: phase,
          lastAttemptAt: DateTime.now(),
          failureKind: error.kind,
          httpStatus: error.statusCode,
          message: _driveFailureMessage(error.kind),
          retryable: error.retryable,
        );
      });
    }
    _recordDiagnostic(
      'sync',
      error.message,
      failureKind: error.kind,
      httpStatus: error.statusCode,
    );
    if (error.kind == DriveFailureKind.authRequired) {
      unawaited(_promptDriveReconnect(forceCloudQueueSync: true));
    }
  }

  void _markCloudVideoChanged(String videoId, {DateTime? at}) {
    final timestamp = at ?? DateTime.now();
    _videoSyncUpdatedAt[videoId] = timestamp;
    _videoDeletedAt.remove(videoId);
  }

  void _markCloudVideoDeleted(String videoId, {DateTime? at}) {
    final timestamp = at ?? DateTime.now();
    _videoSyncUpdatedAt[videoId] = timestamp;
    _videoDeletedAt[videoId] = timestamp;
  }

  void _scheduleCloudLibrarySync() {
    _cloudUploadDebounce?.cancel();
    _cloudUploadDebounce = Timer(const Duration(seconds: 3), () {
      if (_accessToken != null && _accessToken!.isNotEmpty) {
        unawaited(_syncAllCloudState());
      }
    });
  }

  Future<void> _syncAllCloudState({bool pullOnly = false}) async {
    final inFlight = _cloudSyncCompleter;
    if (inFlight != null) return inFlight.future;
    if (_accessToken == null || _accessToken!.isEmpty) return;
    final completer = Completer<void>();
    _cloudSyncCompleter = completer;
    if (mounted) {
      setState(() {
        _syncHealth = _syncHealth.copyWith(
          phase: SyncPhase.syncing,
          lastAttemptAt: DateTime.now(),
          clearFailure: true,
        );
      });
    }
    try {
      await _syncCloudLibrary(pullOnly: pullOnly);
      await _syncPlaybackQueueFromDrive(force: pullOnly);
      if (mounted) {
        setState(() {
          _syncHealth = _syncHealth.copyWith(
            phase: SyncPhase.synced,
            lastSuccessAt: DateTime.now(),
            clearFailure: true,
          );
        });
      }
      _recordDiagnostic('sync', 'Cloud state synchronized.');
      await _saveLibraryState();
      unawaited(_maybeCreateDailyBackup());
      completer.complete();
    } on DriveApiException catch (error) {
      _setSyncFailure(error);
      completer.complete();
    } catch (error) {
      final wrapped = DriveApiException(
        kind: DriveFailureKind.unknown,
        message: 'Cloud synchronization failed: $error',
      );
      _setSyncFailure(wrapped);
      completer.complete();
    } finally {
      _cloudSyncCompleter = null;
    }
  }

  CloudVideoState _cloudVideoState(VideoItem item) {
    final updatedAt =
        _videoSyncUpdatedAt[item.id] ??
        item.lastPlayedAt ??
        item.addedAt ??
        item.modifiedTime ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return CloudVideoState(
      id: item.id,
      title: item.title,
      uri: item.uri,
      size: item.size,
      modifiedTime: item.modifiedTime,
      durationMs: item.duration,
      addedAt: item.addedAt,
      lastPlayedAt: item.lastPlayedAt,
      lastPositionMs: item.lastPositionMs,
      isFavorite: item.isFavorite,
      thumbnailUrl: item.thumbnailUrl,
      width: item.width,
      height: item.height,
      updatedAt: updatedAt,
      updatedByDeviceId: _deviceId,
      driveSubtitle: item.subtitle?.isDrive == true ? item.subtitle : null,
    );
  }

  CloudLibraryState _buildLocalCloudLibraryState() {
    final now = DateTime.now();
    final videos = _videos
        .where((item) => item.source == VideoSource.drive)
        .map(_cloudVideoState)
        .toList();
    final knownVideoIds = videos.map((item) => item.id).toSet();
    for (final entry in _videoDeletedAt.entries) {
      if (knownVideoIds.contains(entry.key)) continue;
      videos.add(
        CloudVideoState(
          id: entry.key,
          title: '',
          uri: '',
          updatedAt: entry.value,
          updatedByDeviceId: _deviceId,
          deletedAt: entry.value,
        ),
      );
    }

    final playlists = _playlists.map((playlist) {
      final driveIds = playlist.videoIds
          .where((id) {
            final item = _videos.where((video) => video.id == id).firstOrNull;
            return item?.source == VideoSource.drive;
          })
          .toList(growable: false);
      return CloudPlaylistState(
        id: playlist.id,
        name: playlist.name,
        driveVideoIds: driveIds,
        createdAt: playlist.createdAt,
        updatedAt: playlist.updatedAt,
        updatedByDeviceId: _deviceId,
        sourceLabel: playlist.sourceLabel,
      );
    }).toList();
    final knownPlaylistIds = playlists.map((item) => item.id).toSet();
    for (final entry in _playlistDeletedAt.entries) {
      if (knownPlaylistIds.contains(entry.key)) continue;
      playlists.add(
        CloudPlaylistState(
          id: entry.key,
          name: '',
          driveVideoIds: const [],
          createdAt: entry.value,
          updatedAt: entry.value,
          updatedByDeviceId: _deviceId,
          sourceLabel: '',
          deletedAt: entry.value,
        ),
      );
    }

    final cloudRecentQueues = _recentQueues
        .map((queue) {
          final driveIds = queue.queueIds
              .where((id) {
                final item = _videos
                    .where((video) => video.id == id)
                    .firstOrNull;
                return item?.source == VideoSource.drive;
              })
              .toList(growable: false);
          if (driveIds.isEmpty) return null;
          final currentId = driveIds.contains(queue.currentVideoId)
              ? queue.currentVideoId
              : driveIds.first;
          final originalDriveIds = queue.originalQueueIds
              .where(driveIds.contains)
              .toList(growable: false);
          return RecentQueueSnapshot(
            id: '${queue.deviceId}:${queueSignature(driveIds)}',
            deviceId: queue.deviceId,
            deviceName: queue.deviceName,
            title: queue.title,
            queueIds: driveIds,
            originalQueueIds: originalDriveIds.isEmpty
                ? driveIds
                : originalDriveIds,
            currentIndex: driveIds.indexOf(currentId!),
            currentVideoId: currentId,
            positionMs: queue.positionMs,
            durationMs: queue.durationMs,
            repeatMode: queue.repeatMode,
            shuffleEnabled: queue.shuffleEnabled,
            updatedAt: queue.updatedAt,
          );
        })
        .whereType<RecentQueueSnapshot>()
        .toList(growable: false);

    return CloudLibraryState(
      deviceId: _deviceId,
      deviceName: _deviceName,
      platform: 'android',
      updatedAt: now,
      videos: videos,
      playlists: playlists,
      imports: _driveImports,
      recentQueues: cloudRecentQueues,
      resumePlayback: CloudSettingValue<bool>(
        value: _resumePlayback,
        updatedAt: _resumePlaybackUpdatedAt ?? now,
        updatedByDeviceId: _deviceId,
      ),
    );
  }

  String _cloudLibrarySignature(CloudLibraryState state) {
    final videos = [...state.videos]..sort((a, b) => a.id.compareTo(b.id));
    final playlists = [...state.playlists]
      ..sort((a, b) => a.id.compareTo(b.id));
    final imports = [...state.imports]..sort((a, b) => a.id.compareTo(b.id));
    final queues = [...state.recentQueues]
      ..sort((a, b) => a.id.compareTo(b.id));
    return jsonEncode({
      'videos': videos.map((item) => item.toJson()).toList(),
      'playlists': playlists.map((item) => item.toJson()).toList(),
      'imports': imports.map((item) => item.toJson()).toList(),
      'recentQueues': queues.map((item) => item.toJson()).toList(),
      'resumePlayback': state.resumePlayback.toJson(),
    });
  }

  Future<void> _syncCloudLibrary({bool pullOnly = false}) async {
    if (_syncingCloudLibrary) return;
    _syncingCloudLibrary = true;
    try {
      final ownName = '$_cloudLibraryPrefix$_deviceId.json';
      final files = await _driveAppData.listFiles(
        namePrefix: _cloudLibraryPrefix,
      );
      final states = <CloudLibraryState>[];
      for (final file in files) {
        try {
          final json = await _driveAppData.readJsonFile(file.id);
          if (json == null) continue;
          states.add(CloudLibraryState.fromJson(json));
          if (file.name == ownName) _cloudLibraryFileId = file.id;
        } catch (error) {
          _recordDiagnostic('sync', 'Ignored invalid cloud library state.');
        }
      }
      final local = _buildLocalCloudLibraryState();
      final merged = CloudLibraryState.merge(
        [...states, local],
        outputDeviceId: _deviceId,
        outputDeviceName: _deviceName,
        outputPlatform: 'android',
      );
      _applyMergedCloudLibrary(merged);
      final signature = _cloudLibrarySignature(merged);
      if (!pullOnly && signature != _lastUploadedCloudLibrarySignature) {
        _cloudLibraryFileId = await _driveAppData.upsertJsonFile(
          name: ownName,
          knownFileId: _cloudLibraryFileId,
          json: merged.toJson(),
        );
        _lastUploadedCloudLibrarySignature = signature;
      }
    } finally {
      _syncingCloudLibrary = false;
    }
  }

  void _applyMergedCloudLibrary(CloudLibraryState merged) {
    if (!mounted) return;
    setState(() {
      final existingById = {for (final item in _videos) item.id: item};
      for (final cloud in merged.videos) {
        _videoSyncUpdatedAt[cloud.id] = cloud.updatedAt;
        if (cloud.isDeleted) {
          _videoDeletedAt[cloud.id] = cloud.deletedAt!;
          _videos.removeWhere(
            (item) => item.id == cloud.id && item.source == VideoSource.drive,
          );
          continue;
        }
        _videoDeletedAt.remove(cloud.id);
        final existing = existingById[cloud.id];
        if (existing == null) {
          _videos.add(_videoItemFromCloud(cloud));
        } else if (existing.source == VideoSource.drive) {
          final index = _videos.indexWhere((item) => item.id == cloud.id);
          if (index >= 0) {
            _videos[index] = existing.copyWith(
              title: cloud.title,
              uri: cloud.uri,
              size: cloud.size,
              modifiedTime: cloud.modifiedTime,
              duration: cloud.durationMs,
              addedAt: cloud.addedAt,
              lastPlayedAt: cloud.lastPlayedAt,
              lastPositionMs: cloud.lastPositionMs,
              isFavorite: cloud.isFavorite,
              thumbnailUrl: cloud.thumbnailUrl,
              width: cloud.width,
              height: cloud.height,
              subtitle: cloud.driveSubtitle ?? existing.subtitle,
            );
          }
        }
      }

      final videoById = {for (final item in _videos) item.id: item};
      for (final cloud in merged.playlists) {
        if (cloud.isDeleted) {
          _playlistDeletedAt[cloud.id] = cloud.deletedAt!;
          _playlists.removeWhere((item) => item.id == cloud.id);
          continue;
        }
        _playlistDeletedAt.remove(cloud.id);
        final index = _playlists.indexWhere((item) => item.id == cloud.id);
        final localIds = index < 0
            ? const <String>[]
            : _playlists[index].videoIds
                  .where((id) => videoById[id]?.source == VideoSource.local)
                  .toList(growable: false);
        final driveIds = cloud.driveVideoIds
            .where((id) => videoById[id]?.source == VideoSource.drive)
            .toList(growable: false);
        final playlist = VideoPlaylist(
          id: cloud.id,
          name: cloud.name,
          videoIds: [...driveIds, ...localIds],
          createdAt: cloud.createdAt,
          updatedAt: cloud.updatedAt,
          sourceLabel: cloud.sourceLabel,
        );
        if (index < 0) {
          _playlists.add(playlist);
        } else {
          _playlists[index] = playlist;
        }
      }
      _driveImports
        ..clear()
        ..addAll(merged.imports);
      _recentQueues
        ..clear()
        ..addAll(merged.recentQueues);
      if (merged.resumePlayback.updatedAt.isAfter(
        _resumePlaybackUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      )) {
        _resumePlayback = merged.resumePlayback.value;
        _resumePlaybackUpdatedAt = merged.resumePlayback.updatedAt;
      }
      final recentVideos =
          _videos.where((item) => item.lastPlayedAt != null).toList()
            ..sort((a, b) => b.lastPlayedAt!.compareTo(a.lastPlayedAt!));
      _recentIds
        ..clear()
        ..addAll(recentVideos.map((item) => item.id));
      if (_recentIds.length > 50) {
        _recentIds.removeRange(50, _recentIds.length);
      }
      _invalidateVisibleVideos();
    });
  }

  VideoItem _videoItemFromCloud(CloudVideoState cloud) {
    return VideoItem(
      id: cloud.id,
      title: cloud.title,
      uri: cloud.uri,
      source: VideoSource.drive,
      size: cloud.size,
      modifiedTime: cloud.modifiedTime,
      duration: cloud.durationMs,
      addedAt: cloud.addedAt,
      lastPlayedAt: cloud.lastPlayedAt,
      lastPositionMs: cloud.lastPositionMs,
      isFavorite: cloud.isFavorite,
      thumbnailUrl: cloud.thumbnailUrl,
      width: cloud.width,
      height: cloud.height,
      subtitle: cloud.driveSubtitle,
    );
  }

  RecentQueueSnapshot _queueSnapshot(
    PlaybackStateSummary summary, {
    bool driveOnly = false,
  }) {
    final queue = driveOnly
        ? summary.queue
              .where((item) => item.source == VideoSource.drive)
              .toList(growable: false)
        : summary.queue;
    final current = summary.current;
    final currentId =
        current != null && queue.any((item) => item.id == current.id)
        ? current.id
        : queue.firstOrNull?.id;
    final queueIds = queue.map((item) => item.id).toList(growable: false);
    final originalSource = summary.originalQueue.isEmpty
        ? summary.queue
        : summary.originalQueue;
    final originalIds = originalSource
        .where((item) => !driveOnly || item.source == VideoSource.drive)
        .map((item) => item.id)
        .where(queueIds.contains)
        .toList(growable: false);
    final updatedAt = _lastLocalPlaybackQueueUpdatedAt ?? DateTime.now();
    return RecentQueueSnapshot(
      id: '$_deviceId:${queueSignature(queueIds)}',
      deviceId: _deviceId,
      deviceName: _deviceName,
      title: current?.title,
      queueIds: queueIds,
      originalQueueIds: originalIds.isEmpty ? queueIds : originalIds,
      currentIndex: currentId == null ? 0 : queueIds.indexOf(currentId),
      currentVideoId: currentId,
      positionMs: summary.positionMs,
      durationMs: summary.durationMs,
      repeatMode: summary.repeatMode,
      shuffleEnabled: summary.shuffleEnabled,
      updatedAt: updatedAt,
    );
  }

  void _recordRecentQueue(PlaybackStateSummary summary) {
    if (summary.queue.isEmpty || _deviceId.isEmpty) return;
    final snapshot = _queueSnapshot(summary);
    _recentQueues.removeWhere(
      (item) =>
          item.deviceId == _deviceId && item.signature == snapshot.signature,
    );
    _recentQueues.insert(0, snapshot);
    var localCount = 0;
    _recentQueues.removeWhere((item) {
      if (item.deviceId != _deviceId) return false;
      localCount += 1;
      return localCount > 10;
    });
  }

  Future<void> _syncPlaybackQueueFromDrive({bool force = false}) async {
    if (_syncingCloudQueue || _accessToken == null || _accessToken!.isEmpty) {
      return;
    }
    _syncingCloudQueue = true;
    try {
      final ownName = '$_cloudQueuePrefix$_deviceId.json';
      final files = await _driveAppData.listFiles(
        namePrefix: _cloudQueuePrefix,
      );
      final legacyFiles = await _driveAppData.listFiles(
        exactName: _cloudPlaybackQueueFileName,
      );
      final states = <CloudPlaybackState>[];
      for (final file in [...files, ...legacyFiles]) {
        try {
          final json = await _driveAppData.readJsonFile(file.id);
          if (json == null) continue;
          final state = CloudPlaybackState.fromJson(json);
          states.add(state);
          if (file.name == ownName) _cloudQueueFileId = file.id;
        } catch (_) {
          _recordDiagnostic('queue', 'Ignored invalid cloud queue state.');
        }
      }
      states.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (!mounted) return;
      setState(() => _knownDeviceQueues = states);
      final latestRemote = CloudPlaybackState.latest(
        states.where((item) => item.deviceId != _deviceId),
      );
      if (latestRemote == null) return;
      _mergeQueueItemsIntoLibrary(latestRemote.queueItems);
      final localUpdatedAt = _lastLocalPlaybackQueueUpdatedAt;
      if (!force &&
          localUpdatedAt != null &&
          !latestRemote.updatedAt.isAfter(localUpdatedAt)) {
        return;
      }
      final localSignature = _playbackSummary == null
          ? null
          : queueSignature(_playbackSummary!.queue.map((item) => item.id));
      if (localSignature == latestRemote.queue.signature) {
        if (!await _hasActiveNativePlayback()) {
          _applyRemoteQueue(latestRemote, updateOnly: true);
        }
      } else {
        setState(() => _remoteQueueCandidate = latestRemote);
      }
      await _saveLibraryState();
    } on DriveApiException catch (error) {
      _setSyncFailure(error);
    } finally {
      _syncingCloudQueue = false;
    }
  }

  Future<void> _syncPlaybackQueueToDrive({bool allowEmpty = false}) async {
    if (_syncingCloudQueue || _accessToken == null || _accessToken!.isEmpty) {
      return;
    }
    final summary = _playbackSummary;
    if (summary == null || summary.queue.isEmpty) {
      if (allowEmpty && _cloudQueueFileId != null) {
        try {
          await _driveAppData.deleteFile(_cloudQueueFileId!);
          _cloudQueueFileId = null;
          _lastUploadedCloudQueueSignature = null;
        } on DriveApiException catch (error) {
          _setSyncFailure(error);
        }
      }
      return;
    }
    if (summary.current?.source != VideoSource.drive) return;
    final driveSnapshot = _queueSnapshot(summary, driveOnly: true);
    if (driveSnapshot.queueIds.isEmpty) return;
    final signature = _cloudQueueSignature();
    if (signature == _lastUploadedCloudQueueSignature) return;
    _syncingCloudQueue = true;
    try {
      final payload = CloudPlaybackState(
        deviceId: _deviceId,
        deviceName: _deviceName,
        platform: 'android',
        updatedAt: driveSnapshot.updatedAt,
        queue: driveSnapshot,
        queueItems: summary.queue
            .where((item) => item.source == VideoSource.drive)
            .map(_cloudVideoState)
            .toList(growable: false),
      );
      _cloudQueueFileId = await _driveAppData.upsertJsonFile(
        name: '$_cloudQueuePrefix$_deviceId.json',
        knownFileId: _cloudQueueFileId,
        json: payload.toJson(),
      );
      _lastUploadedCloudQueueSignature = signature;
      _recordRecentQueue(summary);
      _scheduleCloudLibrarySync();
    } on DriveApiException catch (error) {
      _setSyncFailure(error);
    } finally {
      _syncingCloudQueue = false;
    }
  }

  String _cloudQueueSignature() {
    final summary = _playbackSummary;
    if (summary == null || summary.queue.isEmpty) {
      return 'empty:${_lastLocalPlaybackQueueUpdatedAt?.toIso8601String()}';
    }
    return [
      _lastLocalPlaybackQueueUpdatedAt?.toIso8601String() ?? '',
      summary.currentIndex,
      summary.positionMs,
      summary.isPlaying,
      summary.repeatMode.name,
      summary.shuffleEnabled,
      ...summary.queue.map((item) => item.id),
      '|original|',
      ...(summary.originalQueue.isEmpty ? summary.queue : summary.originalQueue)
          .map((item) => item.id),
    ].join('\u001f');
  }

  Future<bool> _hasActiveNativePlayback() async {
    try {
      final state = await _playback.invokeMapMethod<String, Object?>(
        'getPlaybackState',
      );
      final count = (state?['mediaItemCount'] as num?)?.toInt() ?? 0;
      final playing = state?['isPlaying'] as bool? ?? false;
      return count > 0 && playing;
    } catch (_) {
      return false;
    }
  }

  void _mergeQueueItemsIntoLibrary(List<CloudVideoState> items) {
    if (!mounted || items.isEmpty) return;
    setState(() {
      final knownIds = _videos.map((item) => item.id).toSet();
      for (final item in items) {
        if (item.isDeleted || !knownIds.add(item.id)) continue;
        _videos.add(_videoItemFromCloud(item));
        _videoSyncUpdatedAt[item.id] = item.updatedAt;
      }
      _invalidateVisibleVideos();
    });
  }

  void _applyRemoteQueue(CloudPlaybackState remote, {bool updateOnly = false}) {
    _mergeQueueItemsIntoLibrary(remote.queueItems);
    final byId = {for (final item in _videos) item.id: item};
    final queue = remote.queue.queueIds
        .map((id) => byId[id])
        .whereType<VideoItem>()
        .toList(growable: false);
    if (queue.isEmpty) return;
    final originalQueue = remote.queue.originalQueueIds
        .map((id) => byId[id])
        .whereType<VideoItem>()
        .toList(growable: false);
    final currentIndex = remote.queue.currentVideoId == null
        ? remote.queue.currentIndex.clamp(0, queue.length - 1)
        : queue.indexWhere((item) => item.id == remote.queue.currentVideoId);
    final safeIndex = currentIndex < 0
        ? remote.queue.currentIndex.clamp(0, queue.length - 1)
        : currentIndex;
    setState(() {
      _playbackSummary = PlaybackStateSummary(
        queue: queue,
        currentIndex: safeIndex,
        isPlaying: false,
        positionMs: remote.queue.positionMs,
        durationMs: remote.queue.durationMs,
        repeatMode: remote.queue.repeatMode,
        shuffleEnabled: remote.queue.shuffleEnabled,
        originalQueue: originalQueue,
      );
      _repeatMode = remote.queue.repeatMode;
      _shuffleEnabled = remote.queue.shuffleEnabled;
      _lastLocalPlaybackQueueUpdatedAt = remote.updatedAt;
      _remoteQueueCandidate = null;
      if (!updateOnly) {
        _status = t.playing(queue[safeIndex].title);
      }
    });
    _recordRecentQueue(_playbackSummary!);
  }

  CloudPlaybackState? _currentCloudPlaybackState() {
    final summary = _playbackSummary;
    if (summary == null ||
        summary.queue.isEmpty ||
        summary.current?.source != VideoSource.drive) {
      return null;
    }
    final snapshot = _queueSnapshot(summary, driveOnly: true);
    if (snapshot.queueIds.isEmpty) return null;
    return CloudPlaybackState(
      deviceId: _deviceId,
      deviceName: _deviceName,
      platform: 'android',
      updatedAt: snapshot.updatedAt,
      queue: snapshot,
      queueItems: summary.queue
          .where((item) => item.source == VideoSource.drive)
          .map(_cloudVideoState)
          .toList(growable: false),
    );
  }

  Future<void> _maybeCreateDailyBackup() async {
    final last = _lastCloudBackupAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(days: 1)) {
      return;
    }
    await _createCloudBackup(automatic: true);
  }

  Future<void> _createCloudBackup({bool automatic = false}) async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      if (!automatic) {
        final ready = await _ensureDriveReady();
        if (!ready) return;
      } else {
        return;
      }
    }
    final now = DateTime.now().toUtc();
    final payload = CloudBackupPayload(
      createdAt: now,
      deviceId: _deviceId,
      deviceName: _deviceName,
      platform: 'android',
      library: _buildLocalCloudLibraryState(),
      queue: _currentCloudPlaybackState(),
    );
    try {
      await _driveAppData.upsertJsonFile(
        name:
            '$_cloudBackupPrefix${now.millisecondsSinceEpoch}.$_deviceId.json',
        json: payload.toJson(),
      );
      _lastCloudBackupAt = now;
      final files = await _driveAppData.listFiles(
        namePrefix: _cloudBackupPrefix,
      );
      for (final stale in files.skip(5)) {
        await _driveAppData.deleteFile(stale.id);
      }
      _recordDiagnostic(
        'backup',
        automatic ? 'Automatic cloud backup created.' : 'Cloud backup created.',
      );
      await _saveLibraryState();
    } on DriveApiException catch (error) {
      _setSyncFailure(error);
      if (!automatic) _showMessage(_driveFailureMessage(error.kind));
    }
  }

  Future<List<_CloudBackupEntry>> _loadCloudBackups() async {
    final files = await _driveAppData.listFiles(namePrefix: _cloudBackupPrefix);
    final result = <_CloudBackupEntry>[];
    for (final file in files.take(5)) {
      try {
        final json = await _driveAppData.readJsonFile(file.id);
        if (json == null) continue;
        result.add(
          _CloudBackupEntry(
            file: file,
            payload: CloudBackupPayload.fromJson(json),
          ),
        );
      } catch (_) {
        _recordDiagnostic('backup', 'Ignored invalid cloud backup.');
      }
    }
    result.sort((a, b) => b.payload.createdAt.compareTo(a.payload.createdAt));
    return result;
  }

  Future<void> _restoreCloudBackup(_CloudBackupEntry entry) async {
    final now = DateTime.now().toUtc();
    final source = entry.payload.library;
    final restored = CloudLibraryState(
      deviceId: _deviceId,
      deviceName: _deviceName,
      platform: 'android',
      updatedAt: now,
      videos: source.videos
          .map(
            (item) => item.copyWith(
              updatedAt: now,
              updatedByDeviceId: _deviceId,
              deletedAt: item.isDeleted ? now : null,
              clearDeletedAt: !item.isDeleted,
            ),
          )
          .toList(growable: false),
      playlists: source.playlists
          .map(
            (item) => CloudPlaylistState(
              id: item.id,
              name: item.name,
              driveVideoIds: item.driveVideoIds,
              createdAt: item.createdAt,
              updatedAt: now,
              updatedByDeviceId: _deviceId,
              sourceLabel: item.sourceLabel,
              deletedAt: item.isDeleted ? now : null,
            ),
          )
          .toList(growable: false),
      imports: source.imports
          .map(
            (item) => DriveImportRecord(
              id: item.id,
              folderId: item.folderId,
              name: item.name,
              videoIds: item.videoIds,
              playlistId: item.playlistId,
              importedAt: item.importedAt,
              updatedAt: now,
              updatedByDeviceId: _deviceId,
              deletedAt: item.isDeleted ? now : null,
            ),
          )
          .toList(growable: false),
      recentQueues: source.recentQueues,
      resumePlayback: CloudSettingValue<bool>(
        value: source.resumePlayback.value,
        updatedAt: now,
        updatedByDeviceId: _deviceId,
      ),
    );
    _applyMergedCloudLibrary(restored);
    final queue = entry.payload.queue;
    if (queue != null) {
      _applyRemoteQueue(
        CloudPlaybackState(
          deviceId: _deviceId,
          deviceName: _deviceName,
          platform: 'android',
          updatedAt: now,
          queue: RecentQueueSnapshot(
            id: '$_deviceId:${queue.queue.signature}',
            deviceId: _deviceId,
            deviceName: _deviceName,
            title: queue.queue.title,
            queueIds: queue.queue.queueIds,
            originalQueueIds: queue.queue.originalQueueIds,
            currentIndex: queue.queue.currentIndex,
            currentVideoId: queue.queue.currentVideoId,
            positionMs: queue.queue.positionMs,
            durationMs: queue.queue.durationMs,
            repeatMode: queue.queue.repeatMode,
            shuffleEnabled: queue.queue.shuffleEnabled,
            updatedAt: now,
          ),
          queueItems: queue.queueItems,
        ),
      );
    }
    _lastUploadedCloudLibrarySignature = null;
    _lastUploadedCloudQueueSignature = null;
    await _saveLibraryState();
    await _syncAllCloudState();
    await _syncPlaybackQueueToDrive();
    _recordDiagnostic('backup', 'Cloud backup restored.');
  }

  void _invalidateVisibleVideos() {
    _visibleVideosCacheKey = null;
    _visibleVideosCache = null;
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
              _status = t.reconnectDrivePrompt;
            });
            unawaited(_saveLibraryState());
        }
      });
      unawaited(_signIn.attemptLightweightAuthentication());
      setState(() {
        _initializing = false;
        _status = _videos.isEmpty ? "Add videos to start." : "Library ready";
      });
    } catch (error) {
      setState(() {
        _initializing = false;
        _status = "Google sign-in setup failed: $error";
      });
    }
  }

  Future<void> _signInWithGoogle() async {
    await _guarded(() async {
      await _connectDriveWithPrompt(forceCloudQueueSync: true);
    });
  }

  Future<bool> _connectDriveWithPrompt({
    bool forceCloudQueueSync = false,
  }) async {
    try {
      final existingUser = _user;
      if (existingUser != null) {
        await _authorizeDriveForUser(existingUser, promptIfNecessary: true);
      } else {
        final user = await _signIn.authenticate(scopeHint: _driveScopes);
        await _setUser(user, promptIfNecessary: true);
      }
      final connected = _accessToken != null && _accessToken!.isNotEmpty;
      if (connected && forceCloudQueueSync) {
        await _syncAllCloudState(pullOnly: true);
      }
      return connected;
    } catch (error) {
      if (mounted) {
        final message = error.toString();
        _showMessage(message);
        setState(() => _status = message);
      }
      return false;
    }
  }

  Future<bool> _promptDriveReconnect({bool forceCloudQueueSync = false}) async {
    if (!mounted) return false;
    if (_driveReconnectDialogOpen) return false;
    _driveReconnectDialogOpen = true;
    try {
      final shouldReconnect = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          title: Text(t.drivePermissionExpired),
          content: Text(t.reconnectDrivePrompt),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.link),
              label: Text(t.reconnect),
            ),
          ],
        ),
      );
      if (shouldReconnect != true) return false;
      return _connectDriveWithPrompt(forceCloudQueueSync: forceCloudQueueSync);
    } finally {
      _driveReconnectDialogOpen = false;
    }
  }

  Future<void> _switchGoogleAccount() async {
    await _guarded(() async {
      await _signIn.signOut();
      setState(() {
        _user = null;
        _accessToken = null;
        _driveAuthExpired = false;
        _status = t.switchAccount;
      });
      final user = await _signIn.authenticate(scopeHint: _driveScopes);
      await _setUser(user, promptIfNecessary: true);
    });
  }

  Future<void> _setUser(
    GoogleSignInAccount user, {
    bool promptIfNecessary = false,
  }) async {
    if (!promptIfNecessary) {
      final authz = await user.authorizationClient.authorizationForScopes(
        _driveScopes,
      );
      final token = authz?.accessToken;
      setState(() {
        _user = user;
        _lastGoogleEmail = user.email;
        _accessToken = token;
        _cloudQueueFileId = null;
        _cloudLibraryFileId = null;
        _lastUploadedCloudQueueSignature = null;
        _lastUploadedCloudLibrarySignature = null;
        _driveAuthExpired = token == null;
        _status = token == null
            ? t.drivePermissionRequired
            : t.connectedAccount(user.email);
      });
      await _saveLibraryState();
      if (token != null && token.isNotEmpty) {
        unawaited(_syncAllCloudState(pullOnly: true));
      }
      return;
    }
    await _authorizeDriveForUser(user, promptIfNecessary: true);
  }

  Future<void> _authorizeDriveForUser(
    GoogleSignInAccount user, {
    required bool promptIfNecessary,
  }) async {
    final headers = await user.authorizationClient.authorizationHeaders(
      _driveScopes,
      promptIfNecessary: promptIfNecessary,
    );
    final authorization = headers?['Authorization'];
    setState(() {
      _user = user;
      _lastGoogleEmail = user.email;
      _accessToken = authorization?.replaceFirst('Bearer ', '');
      _cloudQueueFileId = null;
      _cloudLibraryFileId = null;
      _lastUploadedCloudQueueSignature = null;
      _lastUploadedCloudLibrarySignature = null;
      _driveAuthExpired = authorization == null;
      _status = authorization == null
          ? t.drivePermissionRequired
          : t.connectedAccount(user.email);
    });
    await _saveLibraryState();
    if (authorization != null && authorization.isNotEmpty) {
      unawaited(_syncAllCloudState(pullOnly: true));
    }
  }

  Future<void> _openDriveBrowser() async {
    await _guarded(() async {
      if (!await _ensureDriveReady()) return;
      if (!mounted) return;

      final result = await showDialog<DriveImportResult>(
        context: context,
        builder: (context) => _DrivePickerDialog(
          loadEntries: _listDriveEntries,
          loadFolderTreeVideos: _collectDriveVideosRecursively,
        ),
      );
      if (result == null) return;

      final addedItems = _addUniqueVideos(result.items);
      final added = addedItems.length;
      final duplicates = result.videosFound - added;
      VideoPlaylist? createdPlaylist;
      final playlistItems = _uniqueItemsForPlaylist(result.items);
      if (result.createPlaylist && playlistItems.isNotEmpty) {
        createdPlaylist = _createPlaylistFromItems(
          name: result.sourceName.isNotEmpty
              ? result.sourceName
              : _importPlaylistName(t.driveImport),
          sourceLabel: 'Google Drive',
          items: playlistItems,
        );
      }
      final importedAt = DateTime.now();
      for (final folder in result.sourceFolders.entries) {
        final record = DriveImportRecord(
          id: 'drive-import:${folder.key}',
          folderId: folder.key,
          name: folder.value,
          videoIds: result.items.map((item) => item.id).toList(growable: false),
          playlistId: createdPlaylist?.id,
          importedAt: importedAt,
          updatedAt: importedAt,
          updatedByDeviceId: _deviceId,
        );
        _driveImports.removeWhere((item) => item.id == record.id);
        _driveImports.insert(0, record);
      }
      await _saveLibraryState();
      _scheduleCloudLibrarySync();
      setState(() {
        if (createdPlaylist != null) {
          _selectedTab = LibraryTab.playlist;
          _selectedPlaylistId = createdPlaylist.id;
        } else {
          _selectedTab = LibraryTab.drive;
        }
        if (result.videosFound == 0) {
          _status = "${result.sourceName}: no videos found in this folder.";
        } else if (added == 0) {
          _status =
              "${result.sourceName}: no new videos; skipped ${duplicates.clamp(0, result.videosFound)} duplicates"
              "${createdPlaylist != null ? "; playlist created" : ""}";
        } else {
          _status =
              "${result.sourceName}: added $added videos; found ${result.videosFound}"
              "${duplicates > 0 ? "; skipped duplicates" : ""}"
              "${result.foldersScanned > 0 ? "; playlist created" : ""}";
        }
      });
      unawaited(_hydrateDriveThumbnails(addedItems));
    });
  }

  Future<void> _reimportDriveFolder(DriveImportRecord record) async {
    await _guarded(() async {
      if (!await _ensureDriveReady()) return;
      final result = await _collectDriveVideosRecursively(
        record.folderId,
        record.name,
        (progress) {
          if (!mounted) return;
          setState(() {
            _status =
                '${progress.currentFolderName}: ${progress.videosFound} videos';
          });
        },
      );
      final addedItems = _addUniqueVideos(result.items);
      final allIds = result.items
          .map((item) => item.id)
          .toList(growable: false);
      var playlistId = record.playlistId;
      final playlistIndex = playlistId == null
          ? -1
          : _playlists.indexWhere((item) => item.id == playlistId);
      if (playlistIndex >= 0) {
        final playlist = _playlists[playlistIndex];
        _playlists[playlistIndex] = playlist.copyWith(
          videoIds: {...playlist.videoIds, ...allIds}.toList(),
          updatedAt: DateTime.now(),
        );
      } else if (result.items.isNotEmpty) {
        playlistId = _createPlaylistFromItems(
          name: record.name,
          sourceLabel: 'Google Drive',
          items: _uniqueItemsForPlaylist(result.items),
        ).id;
      }
      final now = DateTime.now();
      final updatedRecord = DriveImportRecord(
        id: record.id,
        folderId: record.folderId,
        name: record.name,
        videoIds: allIds,
        playlistId: playlistId,
        importedAt: record.importedAt,
        updatedAt: now,
        updatedByDeviceId: _deviceId,
      );
      final recordIndex = _driveImports.indexWhere(
        (item) => item.id == record.id,
      );
      if (recordIndex >= 0) {
        _driveImports[recordIndex] = updatedRecord;
      } else {
        _driveImports.insert(0, updatedRecord);
      }
      setState(() {
        _status = t.isKo
            ? '${record.name}: ${addedItems.length}\uAC1C \uC0C8 \uC601\uC0C1 \uCD94\uAC00'
            : '${record.name}: ${addedItems.length} new videos';
      });
      await _saveLibraryState();
      _scheduleCloudLibrarySync();
      unawaited(_hydrateDriveThumbnails(addedItems));
    });
  }

  List<VideoItem> _addUniqueVideos(List<VideoItem> items) {
    final knownIds = _videos.map((item) => item.id).toSet();
    final uniqueItems = items.where((item) => knownIds.add(item.id)).toList();
    final now = DateTime.now();
    for (final item in uniqueItems) {
      if (item.source == VideoSource.drive) {
        _markCloudVideoChanged(item.id, at: now);
      }
    }
    setState(() => _videos.addAll(uniqueItems));
    return uniqueItems;
  }

  List<VideoItem> _uniqueItemsForPlaylist(List<VideoItem> items) {
    final knownLibraryIds = _videos.map((item) => item.id).toSet();
    final seenPlaylistIds = <String>{};
    return items
        .where(
          (item) =>
              knownLibraryIds.contains(item.id) && seenPlaylistIds.add(item.id),
        )
        .toList();
  }

  String _importPlaylistName(String label) {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    return '$label $date';
  }

  VideoPlaylist _createPlaylistFromItems({
    required String name,
    required String sourceLabel,
    required List<VideoItem> items,
  }) {
    final now = DateTime.now();
    final playlist = VideoPlaylist(
      id: 'playlist:${now.microsecondsSinceEpoch}:${_random.nextInt(999999)}',
      name: name.trim().isEmpty ? t.newPlaylist : name.trim(),
      videoIds: items.map((item) => item.id).toList(),
      createdAt: now,
      updatedAt: now,
      sourceLabel: sourceLabel,
    );
    setState(() => _playlists.insert(0, playlist));
    _playlistDeletedAt.remove(playlist.id);
    _scheduleCloudLibrarySync();
    return playlist;
  }

  VideoPlaylist? get _selectedPlaylist {
    final id = _selectedPlaylistId;
    if (id == null) return null;
    return _playlists.where((playlist) => playlist.id == id).firstOrNull;
  }

  List<VideoItem> _videosForPlaylist(VideoPlaylist playlist) {
    final byId = {for (final item in _videos) item.id: item};
    return playlist.videoIds
        .map((id) => byId[id])
        .whereType<VideoItem>()
        .toList();
  }

  VideoItem? _coverForPlaylist(VideoPlaylist playlist) {
    final items = _videosForPlaylist(playlist);
    return items.isEmpty ? null : items.first;
  }

  Future<bool> _ensureDriveReady({
    bool promptIfNeeded = true,
    bool syncCloudQueueOnReconnect = false,
  }) async {
    var user = _user;
    if (user == null) {
      final message = _lastGoogleEmail == null
          ? t.driveSignInRequired
          : t.reconnectDrivePrompt;
      setState(() => _status = message);
      if (!promptIfNeeded) {
        _showMessage(message);
        return false;
      }
      return _promptDriveReconnect(
        forceCloudQueueSync: syncCloudQueueOnReconnect,
      );
    }

    final headers = await user.authorizationClient.authorizationHeaders(
      _driveScopes,
      promptIfNecessary: false,
    );
    final authorization = headers?['Authorization'];
    if (authorization == null) {
      setState(() {
        _driveAuthExpired = true;
        _status = t.drivePermissionExpired;
      });
      await _saveLibraryState();
      if (!promptIfNeeded) {
        _showMessage(t.reconnectDrivePrompt);
        return false;
      }
      return _promptDriveReconnect(
        forceCloudQueueSync: syncCloudQueueOnReconnect,
      );
    }
    setState(() {
      _user = user;
      _lastGoogleEmail = user.email;
      _accessToken = authorization.replaceFirst('Bearer ', '');
      _driveAuthExpired = false;
      _status = t.connectedAccount(user.email);
    });
    await _saveLibraryState();
    if (syncCloudQueueOnReconnect) {
      await _syncAllCloudState(pullOnly: true);
    }
    return true;
  }

  Future<bool> _refreshDriveAccessTokenSilently({
    bool clearCurrentToken = false,
  }) async {
    final user = _user;
    if (user == null) return false;
    final currentToken = _accessToken;
    if (clearCurrentToken && currentToken != null && currentToken.isNotEmpty) {
      try {
        await user.authorizationClient.clearAuthorizationToken(
          accessToken: currentToken,
        );
      } catch (_) {
        // Best-effort cache clear; continue with a normal silent token request.
      }
    }
    final headers = await user.authorizationClient.authorizationHeaders(
      _driveScopes,
      promptIfNecessary: false,
    );
    final authorization = headers?['Authorization'];
    if (authorization == null) {
      if (mounted) {
        setState(() {
          _accessToken = null;
          _driveAuthExpired = true;
          _status = t.drivePermissionExpired;
        });
      }
      await _saveLibraryState();
      return false;
    }
    if (mounted) {
      setState(() {
        _user = user;
        _lastGoogleEmail = user.email;
        _accessToken = authorization.replaceFirst('Bearer ', '');
        _driveAuthExpired = false;
        _status = t.connectedAccount(user.email);
      });
    }
    await _saveLibraryState();
    return true;
  }

  Future<void> _recoverDrivePlaybackAuth() async {
    if (_refreshingDriveToken) return;
    _refreshingDriveToken = true;
    try {
      final refreshed = await _refreshDriveAccessTokenSilently();
      final token = _accessToken;
      if (!refreshed || token == null || token.isEmpty) {
        _showDriveReconnectMessageIfNeeded();
        return;
      }
      await _playback.invokeMethod('updateAccessToken', {
        'accessToken': token,
        'retry': true,
      });
      if (mounted) {
        setState(() => _status = t.connectedAccount(_user?.email ?? 'Google'));
      }
    } catch (_) {
      _showDriveReconnectMessageIfNeeded();
    } finally {
      _refreshingDriveToken = false;
    }
  }

  void _showDriveReconnectMessageIfNeeded() {
    final now = DateTime.now();
    final lastPrompt = _lastDriveReconnectPromptAt;
    if (lastPrompt != null &&
        now.difference(lastPrompt) < _driveReconnectPromptCooldown) {
      return;
    }
    _lastDriveReconnectPromptAt = now;
    unawaited(_promptDriveReconnect(forceCloudQueueSync: true));
  }

  Future<void> _updateNativeAccessToken({bool retry = false}) async {
    final token = _accessToken;
    if (token == null || token.isEmpty) return;
    await _playback.invokeMethod('updateAccessToken', {
      'accessToken': token,
      'retry': retry,
    });
  }

  Future<bool> _ensurePlaybackReadyFor(List<VideoItem> queue) async {
    final needsDrive = queue.any((item) => item.source == VideoSource.drive);
    if (needsDrive && !await _ensureDriveReady()) {
      return false;
    }
    if (needsDrive) {
      await _updateNativeAccessToken();
    }
    return true;
  }

  Future<List<DriveEntry>> _listDriveEntries(String parentId) async {
    final query =
        "'$parentId' in parents and trashed=false and "
        "(mimeType='$_driveFolderMimeType' or mimeType contains 'video/' or "
        "mimeType='application/x-subrip' or mimeType='text/vtt' or "
        "name contains '.srt' or name contains '.vtt')";
    return _listDriveEntriesByQuery(query);
  }

  Future<DriveImportResult> _collectDriveVideosRecursively(
    String folderId,
    String sourceName,
    ValueChanged<DriveImportProgress> onProgress,
  ) async {
    var currentLevel = <DriveEntry>[
      DriveEntry(
        id: folderId,
        name: sourceName,
        type: DriveEntryType.folder,
        mimeType: _driveFolderMimeType,
      ),
    ];
    final videos = <VideoItem>[];
    var foldersScanned = 0;

    while (currentLevel.isNotEmpty) {
      final nextLevel = <DriveEntry>[];
      for (
        var start = 0;
        start < currentLevel.length;
        start += _driveImportConcurrency
      ) {
        final end = min(start + _driveImportConcurrency, currentLevel.length);
        final batch = currentLevel.sublist(start, end);
        foldersScanned += batch.length;
        final scanName = batch.length == 1
            ? batch.first.name
            : "${batch.first.name} plus ${batch.length - 1}";
        onProgress(
          DriveImportProgress(
            foldersScanned: foldersScanned,
            videosFound: videos.length,
            currentFolderName: scanName,
          ),
        );

        final batchResults = await Future.wait(
          batch.map((folder) async {
            return (
              folder: folder,
              entries: await _listDriveEntries(folder.id),
            );
          }),
        );

        for (final result in batchResults) {
          final subtitles = result.entries
              .where((entry) => entry.isSubtitle)
              .toList(growable: false);
          for (final entry in result.entries) {
            if (entry.isFolder) {
              nextLevel.add(entry);
            } else if (entry.isVideo) {
              final subtitle = _matchingDriveSubtitle(entry, subtitles);
              videos.add(entry.toVideoItem(subtitle: subtitle));
            }
          }
        }
        onProgress(
          DriveImportProgress(
            foldersScanned: foldersScanned,
            videosFound: videos.length,
            currentFolderName: scanName,
          ),
        );
      }
      currentLevel = nextLevel;
    }

    return DriveImportResult(
      items: videos,
      sourceName: sourceName,
      sourceFolders: {folderId: sourceName},
      foldersScanned: foldersScanned,
      videosFound: videos.length,
      createPlaylist: true,
    );
  }

  Future<List<DriveEntry>> _listDriveEntriesByQuery(String query) async {
    final entries = <DriveEntry>[];
    String? pageToken;

    do {
      final queryParameters = <String, String>{
        'q': query,
        'fields':
            'nextPageToken,files(id,name,mimeType,size,modifiedTime,thumbnailLink,videoMediaMetadata)',
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
      entries.addAll(
        files.cast<Map<String, Object?>>().map((file) {
          final mimeType = file['mimeType'] as String? ?? '';
          final videoMetadata =
              file['videoMediaMetadata'] as Map<String, Object?>?;
          final durationMillis = videoMetadata?['durationMillis'];
          final name = file['name'] as String? ?? "Untitled";
          final lowerName = name.toLowerCase();
          final isSubtitle =
              mimeType == 'application/x-subrip' ||
              mimeType == 'text/vtt' ||
              lowerName.endsWith('.srt') ||
              lowerName.endsWith('.vtt');
          return DriveEntry(
            id: file['id']! as String,
            name: name,
            mimeType: mimeType,
            type: mimeType == _driveFolderMimeType
                ? DriveEntryType.folder
                : isSubtitle
                ? DriveEntryType.subtitle
                : DriveEntryType.video,
            modifiedTime: DateTime.tryParse(
              file['modifiedTime'] as String? ?? '',
            ),
            size: int.tryParse(file['size'] as String? ?? ''),
            duration: durationMillis is num
                ? durationMillis.toInt()
                : int.tryParse(durationMillis as String? ?? ''),
            thumbnailUrl: file['thumbnailLink'] as String?,
            width: (videoMetadata?['width'] as num?)?.toInt(),
            height: (videoMetadata?['height'] as num?)?.toInt(),
          );
        }),
      );
      pageToken = body['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);

    entries.sort((a, b) {
      if (a.type != b.type) return a.type.index.compareTo(b.type.index);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  SubtitleReference? _matchingDriveSubtitle(
    DriveEntry video,
    List<DriveEntry> subtitles,
  ) {
    final videoStem = _fileStem(video.name);
    final candidates = subtitles
        .where((subtitle) {
          final subtitleStem = _fileStem(subtitle.name);
          return subtitleStem == videoStem ||
              subtitleStem.startsWith('$videoStem.');
        })
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final aExact = _fileStem(a.name) == videoStem ? 0 : 1;
      final bExact = _fileStem(b.name) == videoStem ? 0 : 1;
      return aExact != bExact
          ? aExact.compareTo(bExact)
          : a.name.compareTo(b.name);
    });
    final subtitle = candidates.first;
    return SubtitleReference(
      kind: 'drive',
      uri: 'https://www.googleapis.com/drive/v3/files/${subtitle.id}?alt=media',
      mimeType: subtitle.name.toLowerCase().endsWith('.vtt')
          ? 'text/vtt'
          : 'application/x-subrip',
      fileId: subtitle.id,
      label: subtitle.name,
      language: _subtitleLanguageFromName(videoStem, subtitle.name),
    );
  }

  String _fileStem(String name) {
    final dot = name.lastIndexOf('.');
    return (dot <= 0 ? name : name.substring(0, dot)).toLowerCase();
  }

  String? _subtitleLanguageFromName(String videoStem, String subtitleName) {
    final subtitleStem = _fileStem(subtitleName);
    if (!subtitleStem.startsWith('$videoStem.')) return null;
    final language = subtitleStem.substring(videoStem.length + 1);
    return language.isEmpty ? null : language;
  }

  Future<Map<String, Object?>> _driveGet(Uri url) async {
    late final http.Response response;
    try {
      response = await http
          .get(url, headers: {'Authorization': 'Bearer $_accessToken'})
          .timeout(const Duration(seconds: 25));
    } on TimeoutException catch (error) {
      throw DriveApiException(
        kind: DriveFailureKind.network,
        message: _driveFailureMessage(DriveFailureKind.network),
        reason: error.toString(),
      );
    } on io.SocketException catch (error) {
      throw DriveApiException(
        kind: DriveFailureKind.network,
        message: _driveFailureMessage(DriveFailureKind.network),
        reason: error.message,
      );
    } on http.ClientException catch (error) {
      throw DriveApiException(
        kind: DriveFailureKind.network,
        message: _driveFailureMessage(DriveFailureKind.network),
        reason: error.message,
      );
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      final refreshed = await _refreshDriveAccessTokenSilently(
        clearCurrentToken: true,
      );
      final retryToken = _accessToken;
      if (refreshed && retryToken != null && retryToken.isNotEmpty) {
        final retryResponse = await http
            .get(url, headers: {'Authorization': 'Bearer $retryToken'})
            .timeout(const Duration(seconds: 25));
        if (retryResponse.statusCode >= 200 && retryResponse.statusCode < 300) {
          return jsonDecode(retryResponse.body) as Map<String, Object?>;
        }
        if (retryResponse.statusCode == 403) {
          throw DriveApiException(
            kind: DriveFailureKind.accessDenied,
            message: _driveFailureMessage(DriveFailureKind.accessDenied),
            statusCode: 403,
          );
        }
        if (retryResponse.statusCode == 404) {
          throw DriveApiException(
            kind: DriveFailureKind.fileMissing,
            message: _driveFailureMessage(DriveFailureKind.fileMissing),
            statusCode: 404,
          );
        }
        if (retryResponse.statusCode != 401) {
          throw _driveHttpException(retryResponse.statusCode);
        }
      } else if (response.statusCode == 403) {
        throw DriveApiException(
          kind: DriveFailureKind.accessDenied,
          message: _driveFailureMessage(DriveFailureKind.accessDenied),
          statusCode: 403,
        );
      }
      final token = _accessToken;
      if (_user != null && token != null) {
        await _user!.authorizationClient.clearAuthorizationToken(
          accessToken: token,
        );
      }
      if (mounted) {
        setState(() {
          _accessToken = null;
          _driveAuthExpired = true;
          _status = t.drivePermissionExpired;
        });
      }
      await _saveLibraryState();
      _showDriveReconnectMessageIfNeeded();
      throw DriveApiException(
        kind: DriveFailureKind.authRequired,
        message: _driveFailureMessage(DriveFailureKind.authRequired),
        statusCode: 401,
      );
    }
    if (response.statusCode == 404) {
      throw DriveApiException(
        kind: DriveFailureKind.fileMissing,
        message: _driveFailureMessage(DriveFailureKind.fileMissing),
        statusCode: 404,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _driveHttpException(response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, Object?>;
  }

  DriveApiException _driveHttpException(int statusCode) {
    final kind = switch (statusCode) {
      403 => DriveFailureKind.accessDenied,
      404 => DriveFailureKind.fileMissing,
      429 => DriveFailureKind.rateLimited,
      >= 500 => DriveFailureKind.server,
      _ => DriveFailureKind.unknown,
    };
    return DriveApiException(
      kind: kind,
      message: _driveFailureMessage(kind),
      statusCode: statusCode,
    );
  }

  Future<void> _hydrateDriveThumbnails(List<VideoItem> items) async {
    var token = _accessToken;
    if (token == null || items.isEmpty) return;

    for (final item in items.take(24)) {
      if (item.source != VideoSource.drive ||
          item.thumbnailBase64 != null ||
          item.thumbnailUrl == null ||
          item.thumbnailUrl!.isEmpty) {
        continue;
      }
      try {
        var response = await http
            .get(
              Uri.parse(item.thumbnailUrl!),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 401 || response.statusCode == 403) {
          final refreshed = await _refreshDriveAccessTokenSilently(
            clearCurrentToken: true,
          );
          token = _accessToken;
          if (refreshed && token != null) {
            response = await http
                .get(
                  Uri.parse(item.thumbnailUrl!),
                  headers: {'Authorization': 'Bearer $token'},
                )
                .timeout(const Duration(seconds: 8));
          }
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final encoded = base64Encode(response.bodyBytes);
        if (!mounted) return;
        setState(() {
          final index = _videos.indexWhere((video) => video.id == item.id);
          if (index >= 0) {
            _videos[index] = _videos[index].copyWith(thumbnailBase64: encoded);
          }
        });
      } catch (_) {
        // Thumbnail loading is cosmetic; playback/import should never fail here.
      }
    }
    await _saveLibraryState();
  }

  Future<void> _playVisibleShuffled() async {
    final items = _visibleVideos();
    if (items.isEmpty) {
      _showMessage(t.noVideosIn(_tabLabel(_selectedTab)));
      return;
    }
    final queue = [...items]..shuffle(_random);
    await _startPlayback(
      queue,
      startIndex: 0,
      shuffleEnabled: true,
      originalQueue: items,
    );
  }

  Future<void> _playVisibleInOrder() async {
    final items = _visibleVideos();
    if (items.isEmpty) {
      _showMessage(t.noVideosIn(_tabLabel(_selectedTab)));
      return;
    }
    await _startPlayback(items, startIndex: 0, shuffleEnabled: false);
  }

  Future<void> _playFromItem(VideoItem item) async {
    final queue = _visibleVideos();
    final index = queue.indexWhere((candidate) => candidate.id == item.id);
    await _startPlayback(queue, startIndex: index < 0 ? 0 : index);
  }

  Future<void> _playPlaylist(VideoPlaylist playlist) async {
    final queue = _videosForPlaylist(playlist);
    if (queue.isEmpty) {
      _showMessage(t.noVideosToPlay);
      return;
    }
    await _startPlayback(queue, startIndex: 0);
  }

  Future<void> _playSingleItem(VideoItem item) async {
    await _startPlayback([item], startIndex: 0);
  }

  Future<void> _playLastVideo() async {
    if (!await _syncCloudQueueBeforeResumeIfNeeded()) return;
    final summary = _playbackSummary;
    if (summary != null && summary.queue.isNotEmpty) {
      await _startPlayback(
        summary.queue,
        startIndex: summary.currentIndex,
        startPositionMs: _resumePlayback ? summary.positionMs : 0,
      );
      return;
    }
    final item = _lastPlaybackCandidate;
    if (item == null) {
      _showMessage(t.noVideoPlaying);
      return;
    }
    await _playSingleItem(item);
  }

  Future<bool> _syncCloudQueueBeforeResumeIfNeeded() async {
    final summary = _playbackSummary;
    final reconnecting = _driveAuthExpired || _accessToken == null;
    final shouldCheckDriveQueue =
        _driveAuthExpired ||
        _lastGoogleEmail != null ||
        (summary?.queue.any((item) => item.source == VideoSource.drive) ??
            false);
    if (!shouldCheckDriveQueue) return true;
    final ready = await _ensureDriveReady(
      promptIfNeeded: true,
      syncCloudQueueOnReconnect: true,
    );
    if (!ready) return false;
    await _syncAllCloudState(pullOnly: true);
    final candidate = _remoteQueueCandidate;
    final shouldRestoreCloudQueue =
        candidate != null &&
        (reconnecting ||
            summary == null ||
            (summary.queue.length <= 1 && candidate.queue.queueIds.length > 1));
    if (shouldRestoreCloudQueue) {
      _applyRemoteQueue(candidate);
      await _saveLibraryState();
    }
    return true;
  }

  Future<void> _startPlayback(
    List<VideoItem> queue, {
    required int startIndex,
    int? startPositionMs,
    bool? shuffleEnabled,
    PlayerRepeatMode? repeatMode,
    List<VideoItem>? originalQueue,
  }) async {
    await _guarded(() async {
      if (queue.isEmpty) {
        _showMessage(t.noVideosToPlay);
        return;
      }
      if (!await _ensurePlaybackReadyFor(queue)) return;
      final resolvedShuffle = shuffleEnabled ?? _shuffleEnabled;
      final resolvedRepeat = repeatMode ?? _repeatMode;
      final preservedOriginal = List<VideoItem>.from(originalQueue ?? queue);
      var playbackQueue = List<VideoItem>.from(queue);
      var normalizedIndex = startIndex.clamp(0, queue.length - 1);
      if (resolvedShuffle && originalQueue == null && queue.length > 1) {
        final current = queue[normalizedIndex];
        final rest = queue.where((item) => item.id != current.id).toList()
          ..shuffle(_random);
        playbackQueue = [current, ...rest];
        normalizedIndex = 0;
      }
      final count = await _playback.invokeMethod<int>('playQueue', {
        'accessToken': _accessToken,
        'items': playbackQueue.map((item) => item.toPlaybackMap()).toList(),
        'originalItems': preservedOriginal
            .map((item) => item.toPlaybackMap())
            .toList(),
        'startIndex': normalizedIndex,
        'startPositionMs':
            startPositionMs ??
            _resumeStartPositionFor(playbackQueue[normalizedIndex]),
        'repeatMode': resolvedRepeat.name,
        'shuffleEnabled': resolvedShuffle,
        'failurePolicy': _playbackFailurePolicy.name,
        'resizeMode': _resizeMode,
      });
      final current = playbackQueue[normalizedIndex];
      _markPlayed(current);
      setState(() {
        _playbackSummary = PlaybackStateSummary(
          queue: playbackQueue,
          currentIndex: normalizedIndex,
          isPlaying: true,
          positionMs: current.lastPositionMs,
          durationMs: current.duration ?? 0,
          repeatMode: resolvedRepeat,
          shuffleEnabled: resolvedShuffle,
          originalQueue: preservedOriginal,
        );
        _repeatMode = resolvedRepeat;
        _shuffleEnabled = resolvedShuffle;
        _status = t.playing(current.title);
      });
      _rememberPersistedPlaybackSnapshot(
        current.id,
        current.lastPositionMs,
        queueIds: playbackQueue.map((item) => item.id).toList(growable: false),
      );
      await _saveLibraryState();
      unawaited(_syncPlaybackQueueToDrive());
      if ((count ?? playbackQueue.length) > 0) {
        await _playback.invokeMethod('openPlayer');
      }
    });
  }

  int _resumeStartPositionFor(VideoItem item) {
    if (!_resumePlayback) return 0;
    final duration = item.duration ?? 0;
    if (duration > 0 && duration - item.lastPositionMs <= 10000) {
      return 0;
    }
    return item.lastPositionMs;
  }

  void _markPlayed(VideoItem item) {
    final playedAt = DateTime.now();
    final index = _videos.indexWhere((candidate) => candidate.id == item.id);
    if (index >= 0) {
      _videos[index] = _videos[index].copyWith(lastPlayedAt: playedAt);
      if (_videos[index].source == VideoSource.drive) {
        _markCloudVideoChanged(item.id, at: playedAt);
      }
      _invalidateVisibleVideos();
    }
    _recentIds
      ..remove(item.id)
      ..insert(0, item.id);
    if (_recentIds.length > 50) {
      _recentIds.removeRange(50, _recentIds.length);
    }
  }

  Future<bool?> _restoreNativeQueueIfNeeded() async {
    final summary = _playbackSummary;
    if (summary == null || summary.queue.isEmpty) return null;
    try {
      final state = await _playback.invokeMapMethod<String, Object?>(
        'getPlaybackState',
      );
      final mediaItemCount = (state?['mediaItemCount'] as num?)?.toInt() ?? 0;
      if (mediaItemCount > 0) return false;
    } catch (_) {
      // If the native session is gone, try to recreate it from saved state.
    }
    if (!await _ensurePlaybackReadyFor(summary.queue)) return null;
    final currentIndex = summary.currentIndex
        .clamp(0, summary.queue.length - 1)
        .toInt();
    await _playback.invokeMethod<int>('playQueue', {
      'accessToken': _accessToken,
      'items': summary.queue.map((item) => item.toPlaybackMap()).toList(),
      'originalItems':
          (summary.originalQueue.isEmpty
                  ? summary.queue
                  : summary.originalQueue)
              .map((item) => item.toPlaybackMap())
              .toList(),
      'startIndex': currentIndex,
      'startPositionMs': _resumePlayback ? summary.positionMs : 0,
      'repeatMode': summary.repeatMode.name,
      'shuffleEnabled': summary.shuffleEnabled,
      'failurePolicy': _playbackFailurePolicy.name,
      'resizeMode': _resizeMode,
    });
    final current = summary.queue[currentIndex];
    _markPlayed(current);
    setState(() {
      _playbackSummary = PlaybackStateSummary(
        queue: summary.queue,
        currentIndex: currentIndex,
        isPlaying: true,
        positionMs: _resumePlayback ? summary.positionMs : 0,
        durationMs: summary.durationMs,
        repeatMode: summary.repeatMode,
        shuffleEnabled: summary.shuffleEnabled,
        originalQueue: summary.originalQueue,
      );
      _status = t.playing(current.title);
    });
    _rememberPlaybackQueueChanged();
    await _saveLibraryState();
    unawaited(_syncPlaybackQueueToDrive());
    return true;
  }

  Future<void> _openPlayerFromMini() async {
    await _guarded(() async {
      if (!await _syncCloudQueueBeforeResumeIfNeeded()) return;
      if (_playbackSummary?.current == null) {
        _showMessage(t.noVideosToPlay);
        return;
      }
      if (await _restoreNativeQueueIfNeeded() == null) return;
      await _playback.invokeMethod('openPlayer');
    });
  }

  Future<void> _playPause() async {
    await _guarded(() async {
      if (_playbackSummary?.current == null) {
        _showMessage(t.noVideosToPlay);
        return;
      }
      final restored = await _restoreNativeQueueIfNeeded();
      if (restored == null) return;
      if (restored) return;
      await _playback.invokeMethod('playPause');
      setState(() {
        final summary = _playbackSummary!;
        _playbackSummary = PlaybackStateSummary(
          queue: summary.queue,
          currentIndex: summary.currentIndex,
          isPlaying: !summary.isPlaying,
          positionMs: summary.positionMs,
          durationMs: summary.durationMs,
          repeatMode: summary.repeatMode,
          shuffleEnabled: summary.shuffleEnabled,
          originalQueue: summary.originalQueue,
        );
      });
    });
  }

  Future<void> _next() async {
    await _guarded(() async {
      if (_playbackSummary == null || _playbackSummary!.queue.isEmpty) {
        _showMessage(t.noVideosToPlay);
        return;
      }
      if (await _restoreNativeQueueIfNeeded() == null) return;
      await _syncPlaybackState(forcePersist: true);
      final summary = _playbackSummary;
      if (summary == null || summary.queue.isEmpty) {
        _showMessage(t.noVideosToPlay);
        return;
      }
      if (summary.queue.any((item) => item.source == VideoSource.drive)) {
        await _refreshDriveAccessTokenSilently();
        await _updateNativeAccessToken();
      }
      await _playback.invokeMethod('next');
      final nextIndex = (summary.currentIndex + 1) % summary.queue.length;
      _markPlayed(summary.queue[nextIndex]);
      setState(() {
        _playbackSummary = PlaybackStateSummary(
          queue: summary.queue,
          currentIndex: nextIndex,
          isPlaying: summary.isPlaying,
          positionMs: 0,
          durationMs: summary.queue[nextIndex].duration ?? 0,
          repeatMode: summary.repeatMode,
          shuffleEnabled: summary.shuffleEnabled,
          originalQueue: summary.originalQueue,
        );
      });
      _rememberPlaybackQueueChanged();
      await _saveLibraryState();
      unawaited(_syncPlaybackQueueToDrive());
    });
  }

  Future<void> _stop() async {
    await _guarded(() async {
      await _syncPlaybackState(forcePersist: true);
      await _playback.invokeMethod('stop');
      setState(() {
        _playbackSummary = null;
        _status = t.playbackStopped;
      });
      _rememberPlaybackQueueChanged();
      await _saveLibraryState();
      unawaited(_syncPlaybackQueueToDrive(allowEmpty: true));
    });
  }

  Future<void> _showCurrentQueue() async {
    await _syncPlaybackState();
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      await _syncPlaybackQueueFromDrive();
    }
    if (!mounted) return;
    final videoById = {for (final item in _videos) item.id: item};
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _QueueHubPage(
          strings: t,
          current: _playbackSummary,
          recentQueues: List<RecentQueueSnapshot>.unmodifiable(
            [..._recentQueues]
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
          ),
          deviceQueues: List<CloudPlaybackState>.unmodifiable(
            [..._knownDeviceQueues]
              ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
          ),
          videoById: videoById,
          ownDeviceId: _deviceId,
          onPlayCurrent: (index) async {
            final summary = _playbackSummary;
            if (summary == null || summary.queue.isEmpty) return;
            await _startPlayback(
              summary.queue,
              startIndex: index,
              repeatMode: summary.repeatMode,
              shuffleEnabled: summary.shuffleEnabled,
              originalQueue: summary.originalQueue,
            );
          },
          onRestoreRecent: (snapshot) =>
              _restoreRecentQueue(snapshot, startPlayback: false),
          onImportDeviceQueue: (state) =>
              _importDeviceQueue(state, startPlayback: false),
        ),
      ),
    );
  }

  Future<void> _restoreRecentQueue(
    RecentQueueSnapshot snapshot, {
    required bool startPlayback,
  }) async {
    final byId = {for (final item in _videos) item.id: item};
    final queue = snapshot.queueIds
        .map((id) => byId[id])
        .whereType<VideoItem>()
        .toList(growable: false);
    if (queue.isEmpty) {
      _showMessage(t.noVideosToPlay);
      return;
    }
    final originalQueue = snapshot.originalQueueIds
        .map((id) => byId[id])
        .whereType<VideoItem>()
        .toList(growable: false);
    final currentIndexById = snapshot.currentVideoId == null
        ? -1
        : queue.indexWhere((item) => item.id == snapshot.currentVideoId);
    final currentIndex = currentIndexById >= 0
        ? currentIndexById
        : snapshot.currentIndex.clamp(0, queue.length - 1);
    setState(() {
      _playbackSummary = PlaybackStateSummary(
        queue: queue,
        currentIndex: currentIndex,
        isPlaying: false,
        positionMs: snapshot.positionMs,
        durationMs: snapshot.durationMs,
        repeatMode: snapshot.repeatMode,
        shuffleEnabled: snapshot.shuffleEnabled,
        originalQueue: originalQueue,
      );
      _repeatMode = snapshot.repeatMode;
      _shuffleEnabled = snapshot.shuffleEnabled;
      _lastLocalPlaybackQueueUpdatedAt = DateTime.now();
      _status = t.playing(queue[currentIndex].title);
    });
    _rememberPlaybackQueueChanged();
    await _saveLibraryState();
    if (startPlayback) {
      await _startPlayback(
        queue,
        startIndex: currentIndex,
        startPositionMs: snapshot.positionMs,
        repeatMode: snapshot.repeatMode,
        shuffleEnabled: snapshot.shuffleEnabled,
        originalQueue: originalQueue,
      );
    }
  }

  Future<void> _importDeviceQueue(
    CloudPlaybackState state, {
    required bool startPlayback,
  }) async {
    _applyRemoteQueue(state);
    await _saveLibraryState();
    final summary = _playbackSummary;
    if (startPlayback && summary != null && summary.queue.isNotEmpty) {
      await _startPlayback(
        summary.queue,
        startIndex: summary.currentIndex,
        startPositionMs: summary.positionMs,
        repeatMode: summary.repeatMode,
        shuffleEnabled: summary.shuffleEnabled,
        originalQueue: summary.originalQueue,
      );
    }
  }

  void _toggleFavorite(VideoItem item) {
    final index = _videos.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0) return;
    setState(() {
      _videos[index] = _videos[index].copyWith(isFavorite: !item.isFavorite);
    });
    if (item.source == VideoSource.drive) _markCloudVideoChanged(item.id);
    unawaited(_saveLibraryState());
    _scheduleCloudLibrarySync();
  }

  void _toggleSelection(VideoItem item) {
    setState(() {
      if (!_selectedIds.add(item.id)) {
        _selectedIds.remove(item.id);
      }
    });
  }

  void _clearSelection() {
    setState(_selectedIds.clear);
  }

  void _selectAllVisible() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(_visibleVideos().map((item) => item.id));
    });
  }

  void _favoriteSelected() {
    if (_selectedIds.isEmpty) return;
    setState(() {
      for (var index = 0; index < _videos.length; index++) {
        if (_selectedIds.contains(_videos[index].id)) {
          _videos[index] = _videos[index].copyWith(isFavorite: true);
          if (_videos[index].source == VideoSource.drive) {
            _markCloudVideoChanged(_videos[index].id);
          }
        }
      }
      _status = t.favoriteMarked(_selectedIds.length);
      _selectedIds.clear();
    });
    unawaited(_saveLibraryState());
    _scheduleCloudLibrarySync();
  }

  void _removeSelected() {
    if (_selectedIds.isEmpty) return;
    final selectedPlaylist = _selectedPlaylist;
    if (_selectedTab == LibraryTab.playlist && selectedPlaylist != null) {
      final removingIds = _selectedIds.toSet();
      final nextIds = selectedPlaylist.videoIds
          .where((id) => !removingIds.contains(id))
          .toList();
      setState(() {
        final index = _playlists.indexWhere(
          (entry) => entry.id == selectedPlaylist.id,
        );
        if (index >= 0) {
          _playlists[index] = selectedPlaylist.copyWith(
            videoIds: nextIds,
            updatedAt: DateTime.now(),
          );
        }
        _selectedIds.clear();
        _status = t.removeFromPlaylist;
      });
      unawaited(_saveLibraryState());
      _scheduleCloudLibrarySync();
      return;
    }
    final count = _selectedIds.length;
    final removingIds = _selectedIds.toSet();
    for (final item in _videos.where(
      (item) =>
          removingIds.contains(item.id) && item.source == VideoSource.drive,
    )) {
      _markCloudVideoDeleted(item.id);
    }
    setState(() {
      _videos.removeWhere((item) => removingIds.contains(item.id));
      _recentIds.removeWhere(removingIds.contains);
      _removeVideoIdsFromPlaylists(removingIds);
      final summary = _playbackSummary;
      if (summary != null) {
        final nextQueue = summary.queue
            .where((item) => !removingIds.contains(item.id))
            .toList();
        _playbackSummary = nextQueue.isEmpty
            ? null
            : PlaybackStateSummary(
                queue: nextQueue,
                currentIndex: summary.currentIndex.clamp(
                  0,
                  nextQueue.length - 1,
                ),
                isPlaying: summary.isPlaying,
                positionMs: summary.positionMs,
                durationMs: summary.durationMs,
                repeatMode: summary.repeatMode,
                shuffleEnabled: summary.shuffleEnabled,
                originalQueue: summary.originalQueue
                    .where((item) => !removingIds.contains(item.id))
                    .toList(growable: false),
              );
      }
      _selectedIds.clear();
      _status = t.videosRemoved(count);
    });
    unawaited(_saveLibraryState());
    _scheduleCloudLibrarySync();
  }

  void _removeVideo(VideoItem item) {
    if (item.source == VideoSource.drive) _markCloudVideoDeleted(item.id);
    setState(() {
      _videos.removeWhere((candidate) => candidate.id == item.id);
      _recentIds.remove(item.id);
      _removeVideoIdsFromPlaylists({item.id});
      final summary = _playbackSummary;
      if (summary != null) {
        final nextQueue = summary.queue
            .where((candidate) => candidate.id != item.id)
            .toList();
        _playbackSummary = nextQueue.isEmpty
            ? null
            : PlaybackStateSummary(
                queue: nextQueue,
                currentIndex: summary.currentIndex.clamp(
                  0,
                  nextQueue.length - 1,
                ),
                isPlaying: summary.isPlaying,
                positionMs: summary.positionMs,
                durationMs: summary.durationMs,
                repeatMode: summary.repeatMode,
                shuffleEnabled: summary.shuffleEnabled,
                originalQueue: summary.originalQueue
                    .where((candidate) => candidate.id != item.id)
                    .toList(growable: false),
              );
      }
      _status = "${item.title} removed";
    });
    unawaited(_saveLibraryState());
    _scheduleCloudLibrarySync();
  }

  void _removeFromSelectedPlaylist(VideoItem item) {
    final playlist = _selectedPlaylist;
    if (playlist == null) return;
    final nextIds = playlist.videoIds.where((id) => id != item.id).toList();
    setState(() {
      final index = _playlists.indexWhere((entry) => entry.id == playlist.id);
      if (index >= 0) {
        _playlists[index] = playlist.copyWith(
          videoIds: nextIds,
          updatedAt: DateTime.now(),
        );
      }
      _status = t.removeFromPlaylist;
    });
    unawaited(_saveLibraryState());
    _scheduleCloudLibrarySync();
  }

  Future<void> _createEmptyPlaylist() async {
    final name = await _askPlaylistName(initialName: t.newPlaylist);
    if (name == null) return;
    final playlist = _createPlaylistFromItems(
      name: name,
      sourceLabel: t.emptyPlaylist,
      items: const [],
    );
    setState(() {
      _selectedTab = LibraryTab.playlist;
      _selectedPlaylistId = playlist.id;
      _status = t.playlistCreated(playlist.name);
    });
    await _saveLibraryState();
    _scheduleCloudLibrarySync();
  }

  Future<void> _renamePlaylist(VideoPlaylist playlist) async {
    final name = await _askPlaylistName(initialName: playlist.name);
    if (name == null) return;
    setState(() {
      final index = _playlists.indexWhere((entry) => entry.id == playlist.id);
      if (index >= 0) {
        _playlists[index] = playlist.copyWith(
          name: name,
          updatedAt: DateTime.now(),
        );
      }
    });
    await _saveLibraryState();
    _scheduleCloudLibrarySync();
  }

  void _deletePlaylist(VideoPlaylist playlist) {
    _playlistDeletedAt[playlist.id] = DateTime.now();
    setState(() {
      _playlists.removeWhere((entry) => entry.id == playlist.id);
      if (_selectedPlaylistId == playlist.id) {
        _selectedPlaylistId = null;
      }
    });
    unawaited(_saveLibraryState());
    _scheduleCloudLibrarySync();
  }

  Future<String?> _askPlaylistName({required String initialName}) async {
    final controller = TextEditingController(text: initialName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.playlistName),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: t.playlistName),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> _addSelectedToPlaylist() async {
    if (_selectedIds.isEmpty) return;
    final selectedItems = _videos
        .where((item) => _selectedIds.contains(item.id))
        .toList();
    if (selectedItems.isEmpty) return;
    final target = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(t.newPlaylist),
              onTap: () => Navigator.pop(context, 'new'),
            ),
            for (final playlist in _playlists)
              ListTile(
                leading: const Icon(Icons.queue_music_outlined),
                title: Text(playlist.name),
                subtitle: Text(
                  t.videoCount(_videosForPlaylist(playlist).length),
                ),
                onTap: () => Navigator.pop(context, playlist),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;

    VideoPlaylist playlist;
    if (target == 'new') {
      final name = await _askPlaylistName(initialName: t.newPlaylist);
      if (name == null) return;
      playlist = _createPlaylistFromItems(
        name: name,
        sourceLabel: t.newPlaylist,
        items: const [],
      );
    } else {
      playlist = target as VideoPlaylist;
    }

    final nextIds = [...playlist.videoIds];
    for (final item in selectedItems) {
      if (!nextIds.contains(item.id)) nextIds.add(item.id);
    }
    setState(() {
      final index = _playlists.indexWhere((entry) => entry.id == playlist.id);
      if (index >= 0) {
        _playlists[index] = playlist.copyWith(
          videoIds: nextIds,
          updatedAt: DateTime.now(),
        );
      }
      _selectedIds.clear();
      _selectedTab = LibraryTab.playlist;
      _selectedPlaylistId = playlist.id;
      _status = t.addedToPlaylist(selectedItems.length, playlist.name);
    });
    await _saveLibraryState();
    _scheduleCloudLibrarySync();
  }

  void _removeVideoIdsFromPlaylists(Set<String> ids) {
    for (var index = 0; index < _playlists.length; index++) {
      final playlist = _playlists[index];
      final nextIds = playlist.videoIds
          .where((id) => !ids.contains(id))
          .toList();
      if (nextIds.length != playlist.videoIds.length) {
        _playlists[index] = playlist.copyWith(
          videoIds: nextIds,
          updatedAt: DateTime.now(),
        );
      }
    }
  }

  Future<void> _clearPlaylist() async {
    await _createCloudBackup(automatic: true);
    final now = DateTime.now();
    for (final item in _videos.where(
      (item) => item.source == VideoSource.drive,
    )) {
      _markCloudVideoDeleted(item.id, at: now);
    }
    for (final playlist in _playlists) {
      _playlistDeletedAt[playlist.id] = now;
    }
    for (var index = 0; index < _driveImports.length; index++) {
      final item = _driveImports[index];
      _driveImports[index] = DriveImportRecord(
        id: item.id,
        folderId: item.folderId,
        name: item.name,
        videoIds: item.videoIds,
        playlistId: item.playlistId,
        importedAt: item.importedAt,
        updatedAt: now,
        updatedByDeviceId: _deviceId,
        deletedAt: now,
      );
    }
    setState(() {
      _videos.clear();
      _playlists.clear();
      _recentIds.clear();
      _playbackSummary = null;
      _selectedIds.clear();
      _selectedPlaylistId = null;
      _status = t.playlistCleared;
    });
    await _saveLibraryState();
    _scheduleCloudLibrarySync();
  }

  Future<void> _clearResumePositions() async {
    await _createCloudBackup(automatic: true);
    final changedAt = DateTime.now();
    setState(() {
      for (var index = 0; index < _videos.length; index++) {
        _videos[index] = _videos[index].copyWith(lastPositionMs: 0);
        if (_videos[index].source == VideoSource.drive) {
          _markCloudVideoChanged(_videos[index].id, at: changedAt);
        }
      }
      final summary = _playbackSummary;
      if (summary != null) {
        _playbackSummary = PlaybackStateSummary(
          queue: summary.queue,
          currentIndex: summary.currentIndex,
          isPlaying: summary.isPlaying,
          positionMs: 0,
          durationMs: summary.durationMs,
          repeatMode: summary.repeatMode,
          shuffleEnabled: summary.shuffleEnabled,
          originalQueue: summary.originalQueue,
        );
      }
      _status = t.resumePositionsCleared;
    });
    await _saveLibraryState();
    _scheduleCloudLibrarySync();
  }

  String _syncStatusText() {
    final last = _syncHealth.lastSuccessAt;
    return switch (_syncHealth.phase) {
      SyncPhase.syncing => t.isKo ? '\uB3D9\uAE30\uD654 \uC911' : 'Syncing',
      SyncPhase.offline => t.isKo ? '\uC624\uD504\uB77C\uC778' : 'Offline',
      SyncPhase.reconnectRequired => t.reconnectDrivePrompt,
      SyncPhase.failed =>
        _syncHealth.message ??
            (t.isKo ? '\uB3D9\uAE30\uD654 \uC2E4\uD328' : 'Sync failed'),
      _ when last != null =>
        t.isKo
            ? '\uB9C8\uC9C0\uB9C9 \uB3D9\uAE30\uD654: ${_relativeTime(last, true)}'
            : 'Last sync: ${_relativeTime(last, false)}',
      _ =>
        t.isKo
            ? '\uC544\uC9C1 \uB3D9\uAE30\uD654\uD558\uC9C0 \uC54A\uC74C'
            : 'Not synced yet',
    };
  }

  String _relativeTime(DateTime value, bool isKo) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return isKo ? '\uBC29\uAE08' : 'just now';
    if (difference.inHours < 1) {
      return isKo
          ? '${difference.inMinutes}\uBD84 \uC804'
          : '${difference.inMinutes} min ago';
    }
    if (difference.inDays < 1) {
      return isKo
          ? '${difference.inHours}\uC2DC\uAC04 \uC804'
          : '${difference.inHours} hr ago';
    }
    return isKo
        ? '${difference.inDays}\uC77C \uC804'
        : '${difference.inDays} days ago';
  }

  _SyncPageSnapshot _syncPageSnapshot() => _SyncPageSnapshot(
    health: _syncHealth,
    account: _user?.email ?? _lastGoogleEmail,
    deviceId: _deviceId,
    deviceName: _deviceName,
    currentQueue: _playbackSummary,
    remoteCandidate: _remoteQueueCandidate,
    deviceQueues: List<CloudPlaybackState>.unmodifiable(_knownDeviceQueues),
    lastBackupAt: _lastCloudBackupAt,
  );

  Future<void> _openSyncAndBackup() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _SyncAndBackupPage(
          strings: t,
          snapshot: _syncPageSnapshot,
          onSync: () async {
            if (!await _ensureDriveReady()) return;
            await _syncAllCloudState(pullOnly: true);
          },
          onBackup: () => _createCloudBackup(),
          loadBackups: _loadCloudBackups,
          onRestore: _restoreCloudBackup,
          onImportRemote: (state) =>
              _importDeviceQueue(state, startPlayback: false),
        ),
      ),
    );
  }

  Future<void> _openGestureHelp() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              t.isKo
                  ? '\uD50C\uB808\uC774\uC5B4 \uC81C\uC2A4\uCC98'
                  : 'Player gestures',
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _gestureHelpTile(
                  Icons.touch_app_outlined,
                  t.isKo ? '\uD55C \uBC88 \uD130\uCE58' : 'Single tap',
                  t.isKo
                      ? '\uD50C\uB808\uC774\uC5B4 \uCEE8\uD2B8\uB864\uC744 \uD45C\uC2DC\uD558\uAC70\uB098 \uC228\uAE41\uB2C8\uB2E4.'
                      : 'Show or hide player controls.',
                ),
                _gestureHelpTile(
                  Icons.fast_forward,
                  t.isKo ? '\uB354\uBE14 \uD0ED' : 'Double tap',
                  t.isKo
                      ? '\uC67C\uCABD/\uC624\uB978\uCABD\uC744 \uC5F0\uC18D \uB354\uBE14 \uD0ED\uD574 10\uCD08\uC529 \uB204\uC801 \uD0D0\uC0C9\uD569\uB2C8\uB2E4.'
                      : 'Repeatedly double tap left or right to seek in 10-second steps.',
                ),
                _gestureHelpTile(
                  Icons.swipe,
                  t.isKo
                      ? '\uAC00\uB85C \uB4DC\uB798\uADF8'
                      : 'Horizontal drag',
                  t.isKo
                      ? '\uD654\uBA74 \uAC00\uC6B4\uB370 4/6 \uC601\uC5ED\uC5D0\uC11C \uC7AC\uC0DD \uC704\uCE58\uB97C \uC62E\uAE41\uB2C8\uB2E4.'
                      : 'Seek from the middle four-sixths of the video surface.',
                ),
                _gestureHelpTile(
                  Icons.lock_outline,
                  t.isKo ? '\uC7A0\uAE08' : 'Lock',
                  t.isKo
                      ? '\uC7A0\uAE08 \uBC84\uD2BC\uC744 \uAE38\uAC8C \uB20C\uB7EC \uD574\uC81C\uD569\uB2C8\uB2E4.'
                      : 'Press and hold the lock button to unlock.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gestureHelpTile(IconData icon, String title, String subtitle) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: _Ui.accent),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }

  Future<void> _openDiagnostics() async {
    Map<String, Object?> nativeState = const {};
    try {
      nativeState =
          await _playback.invokeMapMethod<String, Object?>(
            'getPlaybackState',
          ) ??
          const {};
    } catch (_) {
      // A stopped native service is a valid diagnostic state.
    }
    if (!mounted) return;
    final rows = <String, String>{
      t.isKo ? '\uC571 \uBC84\uC804' : 'App version': _appVersion,
      'Android': _androidVersion,
      t.isKo ? '\uD604\uC7AC \uACC4\uC815' : 'Account':
          _user?.email ??
          _lastGoogleEmail ??
          (t.isKo ? '\uC5F0\uACB0 \uC548 \uB428' : 'Not connected'),
      t.isKo ? 'Drive \uD1A0\uD070' : 'Drive token': _refreshingDriveToken
          ? (t.isKo ? '\uAC31\uC2E0 \uC911' : 'Refreshing')
          : _driveAuthExpired || _accessToken == null
          ? (t.isKo ? '\uC7AC\uC5F0\uACB0 \uD544\uC694' : 'Reconnect required')
          : (t.isKo ? '\uC0AC\uC6A9 \uAC00\uB2A5' : 'Available'),
      t.isKo ? '\uD604\uC7AC \uD050' : 'Current queue':
          '${_playbackSummary?.queue.length ?? 0}',
      t.isKo ? '\uCD5C\uADFC \uD050' : 'Recent queues':
          '${_recentQueues.length}',
      t.isKo ? '\uC378\uB124\uC77C \uCE90\uC2DC' : 'Thumbnail cache':
          '${_ThumbnailMemoryCache.entryCount} / ${(_ThumbnailMemoryCache.byteCount / (1024 * 1024)).toStringAsFixed(1)} MiB',
      t.isKo ? '\uB9C8\uC9C0\uB9C9 HTTP' : 'Last HTTP':
          '${nativeState['httpStatusCode'] ?? '-'}',
      t.isKo ? '\uC7AC\uC0DD \uC624\uB958' : 'Playback error':
          '${nativeState['playerErrorCode'] ?? '-'}',
      t.isKo ? '\uB3D9\uAE30\uD654 \uC624\uB958' : 'Sync error':
          _syncHealth.message ?? '-',
    };
    final logText = _diagnosticLogText(rows);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => _DiagnosticsPage(
          strings: t,
          rows: rows,
          events: List<DiagnosticEvent>.unmodifiable(_diagnosticEvents),
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: logText));
          },
        ),
      ),
    );
  }

  String _diagnosticLogText(Map<String, String> rows) {
    final buffer = StringBuffer('Cloud Player diagnostics\n');
    for (final entry in rows.entries) {
      final value =
          entry.key.toLowerCase().contains('account') ||
              entry.key.contains('\uACC4\uC815')
          ? _maskedAccount(entry.value)
          : entry.value;
      buffer.writeln('${entry.key}: $value');
    }
    buffer.writeln('Events:');
    for (final event in _diagnosticEvents) {
      buffer.writeln(
        '${event.timestamp.toUtc().toIso8601String()} '
        '[${event.category}] ${event.failureKind?.name ?? '-'} '
        '${event.httpStatus ?? '-'} ${event.message}',
      );
    }
    return buffer.toString();
  }

  String _maskedAccount(String value) {
    final at = value.indexOf('@');
    if (at <= 0) return value;
    final prefix = value.substring(0, at);
    return '${prefix.substring(0, min(2, prefix.length))}***${value.substring(at)}';
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setPageState) {
              return Scaffold(
                appBar: AppBar(title: Text(t.settings)),
                body: SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      DropdownButtonFormField<AppLanguage>(
                        initialValue: _language,
                        decoration: InputDecoration(
                          labelText: t.languageSetting,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: AppLanguage.ko,
                            child: Text(
                              AppStrings(AppLanguage.ko).languageName,
                            ),
                          ),
                          DropdownMenuItem(
                            value: AppLanguage.en,
                            child: Text(
                              AppStrings(AppLanguage.en).languageName,
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _language = value);
                          setPageState(() {});
                          unawaited(_saveLibraryState());
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AppThemeChoice>(
                        initialValue: _themeChoice,
                        decoration: InputDecoration(labelText: t.themeSetting),
                        items: [
                          DropdownMenuItem(
                            value: AppThemeChoice.light,
                            child: Text(t.lightTheme),
                          ),
                          DropdownMenuItem(
                            value: AppThemeChoice.dark,
                            child: Text(t.darkTheme),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _themeChoice = value);
                          _themeChoiceNotifier.value = value;
                          setPageState(() {});
                          unawaited(_saveLibraryState());
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<TabBarPlacement>(
                        initialValue: _tabBarPlacement,
                        decoration: InputDecoration(
                          labelText: t.tabBarPlacement,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: TabBarPlacement.automatic,
                            child: Text(t.tabBarAutomatic),
                          ),
                          DropdownMenuItem(
                            value: TabBarPlacement.bottom,
                            child: Text(t.tabBarBottom),
                          ),
                          DropdownMenuItem(
                            value: TabBarPlacement.landscapeLeft,
                            child: Text(t.tabBarLandscapeLeft),
                          ),
                          DropdownMenuItem(
                            value: TabBarPlacement.landscapeRight,
                            child: Text(t.tabBarLandscapeRight),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _tabBarPlacement = value);
                          setPageState(() {});
                          unawaited(_saveLibraryState());
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<LibraryViewMode>(
                        initialValue: _portraitViewMode,
                        decoration: InputDecoration(
                          labelText: t.portraitViewMode,
                        ),
                        items: _viewModeMenuItems(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _portraitViewMode = value);
                          setPageState(() {});
                          unawaited(_saveLibraryState());
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<LibraryViewMode>(
                        initialValue: _landscapeViewMode,
                        decoration: InputDecoration(
                          labelText: t.landscapeViewMode,
                        ),
                        items: _viewModeMenuItems(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _landscapeViewMode = value);
                          setPageState(() {});
                          unawaited(_saveLibraryState());
                        },
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.resumePlayback),
                        subtitle: Text(t.resumePlaybackDescription),
                        value: _resumePlayback,
                        onChanged: (value) {
                          setState(() {
                            _resumePlayback = value;
                            _resumePlaybackUpdatedAt = DateTime.now();
                          });
                          setPageState(() {});
                          unawaited(_saveLibraryState());
                          _scheduleCloudLibrarySync();
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<PlaybackFailurePolicy>(
                        initialValue: _playbackFailurePolicy,
                        decoration: InputDecoration(
                          labelText: t.isKo
                              ? '\uC7AC\uC0DD \uC624\uB958 \uCC98\uB9AC'
                              : 'Playback error handling',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: PlaybackFailurePolicy.ask,
                            child: Text(t.isKo ? '\uBB3B\uAE30' : 'Ask'),
                          ),
                          DropdownMenuItem(
                            value: PlaybackFailurePolicy.skip,
                            child: Text(
                              t.isKo
                                  ? '\uB2E4\uC74C \uC601\uC0C1'
                                  : 'Play next',
                            ),
                          ),
                          DropdownMenuItem(
                            value: PlaybackFailurePolicy.stop,
                            child: Text(t.isKo ? '\uBA48\uCDA4' : 'Stop'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _playbackFailurePolicy = value);
                          setPageState(() {});
                          unawaited(_saveLibraryState());
                          unawaited(
                            _playback.invokeMethod('updatePlayerPreferences', {
                              'failurePolicy': value.name,
                            }),
                          );
                        },
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cloud_sync_outlined),
                        title: Text(
                          t.isKo
                              ? '\uB3D9\uAE30\uD654 \uBC0F \uBC31\uC5C5'
                              : 'Sync and backup',
                        ),
                        subtitle: Text(_syncStatusText()),
                        onTap: _openSyncAndBackup,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.gesture),
                        title: Text(
                          t.isKo
                              ? '\uD50C\uB808\uC774\uC5B4 \uC81C\uC2A4\uCC98'
                              : 'Player gestures',
                        ),
                        onTap: _openGestureHelp,
                      ),
                      if (_diagnosticsUnlocked)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.monitor_heart_outlined),
                          title: Text(
                            t.isKo
                                ? '\uC9C4\uB2E8 \uB3C4\uAD6C'
                                : 'Diagnostics',
                          ),
                          onTap: _openDiagnostics,
                        ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.info_outline),
                        title: Text(
                          t.isKo ? '\uC571 \uBC84\uC804' : 'App version',
                        ),
                        subtitle: Text(_appVersion),
                        onTap: () {
                          _versionTapCount += 1;
                          if (_versionTapCount >= 7 && !_diagnosticsUnlocked) {
                            setState(() => _diagnosticsUnlocked = true);
                            setPageState(() {});
                            _showMessage(
                              t.isKo
                                  ? '\uC9C4\uB2E8 \uB3C4\uAD6C\uB97C \uD65C\uC131\uD654\uD588\uC2B5\uB2C8\uB2E4.'
                                  : 'Diagnostics enabled.',
                            );
                          }
                        },
                      ),
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.restart_alt),
                        title: Text(t.clearResumePositions),
                        subtitle: Text(t.clearResumePositionsDescription),
                        onTap: () {
                          Navigator.pop(context);
                          _clearResumePositions();
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.delete_sweep_outlined),
                        title: Text(t.clearLibrary),
                        subtitle: Text(t.clearLibraryDescription),
                        onTap: () {
                          Navigator.pop(context);
                          _clearPlaylist();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openAccountSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final email = _user?.email;
        final status = _driveAuthExpired
            ? t.drivePermissionExpired
            : email != null
            ? t.connectedAccount(email)
            : _lastGoogleEmail != null
            ? t.previousAccount(_lastGoogleEmail!)
            : t.googleAccountNotConnected;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Google Drive',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: _driveAuthExpired ? _Ui.red : _Ui.accent,
                    foregroundColor: Colors.white,
                    child: Text(
                      (email ?? _lastGoogleEmail ?? 'K')[0].toUpperCase(),
                    ),
                  ),
                  title: Text(status),
                  subtitle: Text(
                    _driveAuthExpired
                        ? t.reconnectDrivePrompt
                        : email ?? _lastGoogleEmail ?? t.driveSignInRequired,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 56, bottom: 8),
                  child: Text(
                    _syncStatusText(),
                    style: TextStyle(color: _Ui.text2, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () {
                            Navigator.pop(context);
                            _signInWithGoogle();
                          },
                    icon: const Icon(Icons.link),
                    label: Text(t.reconnect),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onPressed: _busy
                        ? null
                        : () {
                            Navigator.pop(context);
                            _switchGoogleAccount();
                          },
                    icon: const Icon(Icons.switch_account_outlined),
                    label: Text(t.switchAccount),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _openSettings();
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(t.settings),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _selectTab(int index) {
    final nextTab = LibraryTab.values[index];
    setState(() {
      _selectedTab = nextTab;
      _selectedIds.clear();
      if (nextTab != LibraryTab.playlist) {
        _selectedPlaylistId = null;
      }
    });
    if (nextTab == LibraryTab.drive || nextTab == LibraryTab.all) {
      unawaited(
        _hydrateDriveThumbnails(
          _videos.where((item) => item.source == VideoSource.drive).toList(),
        ),
      );
    }
    unawaited(_saveLibraryState());
  }

  void _closeSearch() {
    setState(() {
      _searchActive = false;
      _searchController.clear();
    });
  }

  List<VideoItem> _visibleVideos() {
    final cacheKey = [
      _visibleVideosSignature(),
      _selectedTab.name,
      _selectedPlaylistId ?? '',
      _sortMode.name,
      _query,
      _recentIds.length,
    ].join('|');
    final cached = _visibleVideosCache;
    if (_visibleVideosCacheKey == cacheKey && cached != null) {
      return cached;
    }
    Iterable<VideoItem> items = switch (_selectedTab) {
      LibraryTab.all => _videos,
      LibraryTab.local => _videos.where(
        (item) => item.source == VideoSource.local,
      ),
      LibraryTab.drive => _videos.where(
        (item) => item.source == VideoSource.drive,
      ),
      LibraryTab.playlist =>
        _selectedPlaylist == null
            ? const <VideoItem>[]
            : _videosForPlaylist(_selectedPlaylist!),
      LibraryTab.recent =>
        _recentIds
            .map((id) => _videos.where((item) => item.id == id).firstOrNull)
            .whereType<VideoItem>(),
    };
    if (_query.isNotEmpty) {
      final lowerQuery = _query.toLowerCase();
      items = items.where(
        (item) => item.title.toLowerCase().contains(lowerQuery),
      );
    }
    final list = items.toList();
    if (_selectedTab == LibraryTab.recent) {
      _visibleVideosCacheKey = cacheKey;
      _visibleVideosCache = List.unmodifiable(list);
      return _visibleVideosCache!;
    }
    switch (_sortMode) {
      case VideoSortMode.recentlyAdded:
        list.sort((a, b) => _compareDateDesc(a.addedAt, b.addedAt));
      case VideoSortMode.name:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case VideoSortMode.recentlyPlayed:
        list.sort((a, b) => _compareDateDesc(a.lastPlayedAt, b.lastPlayedAt));
      case VideoSortMode.source:
        list.sort((a, b) {
          final sourceCompare = a.source.name.compareTo(b.source.name);
          if (sourceCompare != 0) return sourceCompare;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      case VideoSortMode.size:
        list.sort((a, b) => (b.size ?? -1).compareTo(a.size ?? -1));
      case VideoSortMode.duration:
        list.sort((a, b) => (b.duration ?? -1).compareTo(a.duration ?? -1));
    }
    _visibleVideosCacheKey = cacheKey;
    _visibleVideosCache = List.unmodifiable(list);
    return _visibleVideosCache!;
  }

  String _visibleVideosSignature() {
    final videoHash = Object.hashAll(
      _videos.map(
        (item) => Object.hash(
          item.id,
          item.title,
          item.source.name,
          item.addedAt?.millisecondsSinceEpoch,
          item.lastPlayedAt?.millisecondsSinceEpoch,
          item.lastPositionMs,
          item.duration,
          item.isFavorite,
          item.size,
        ),
      ),
    );
    final playlistHash = Object.hashAll(
      _playlists.map(
        (playlist) => Object.hash(
          playlist.id,
          playlist.name,
          playlist.updatedAt.millisecondsSinceEpoch,
          Object.hashAll(playlist.videoIds),
        ),
      ),
    );
    return '$videoHash/$playlistHash';
  }

  int _compareDateDesc(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on PlatformException catch (error) {
      final message = _friendlyPlatformError(error);
      _showMessage(message);
      setState(() => _status = message);
    } on StateError catch (error) {
      final message = error.message;
      _showMessage(message);
      setState(() => _status = message);
    } catch (error) {
      _showMessage(error.toString());
      setState(() => _status = '${t.unknownError}: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyPlatformError(PlatformException error) {
    return switch (error.code) {
      'EMPTY_QUEUE' => t.noVideosToPlay,
      'PLAYER_OPEN_FAILED' => t.playerOpenFailed,
      'DRIVE_EMPTY' => t.driveEmpty,
      'DRIVE_IMPORT_FAILED' => t.driveImportFailed,
      _ => error.message ?? t.unknownError,
    };
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _handleMainBack({
    required bool selecting,
    required bool showingPlaylistDetail,
  }) {
    if (selecting) {
      _clearSelection();
      return true;
    }
    if (_searchActive) {
      _closeSearch();
      return true;
    }
    if (showingPlaylistDetail) {
      setState(() => _selectedPlaylistId = null);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final visibleVideos = _visibleVideos();
    final selecting = _selectedIds.isNotEmpty;
    final lastVideo = _lastPlaybackCandidate;
    final selectedPlaylist = _selectedPlaylist;
    final showingPlaylistDetail =
        _selectedTab == LibraryTab.playlist && selectedPlaylist != null;

    final hasInternalBackTarget =
        selecting || _searchActive || showingPlaylistDetail;
    final tabSide = _resolvedSideTabSide(mediaQuery);
    final useSideTabs = tabSide != null;
    final resolvedViewMode = _resolvedViewMode(mediaQuery);

    return PopScope(
      canPop: !hasInternalBackTarget,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleMainBack(
            selecting: selecting,
            showingPlaylistDetail: showingPlaylistDetail,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: selecting
              ? IconButton(
                  tooltip: t.cancelSelection,
                  onPressed: _clearSelection,
                  icon: const Icon(Icons.close),
                )
              : showingPlaylistDetail
              ? IconButton(
                  tooltip: t.playlists,
                  onPressed: () => setState(() => _selectedPlaylistId = null),
                  icon: const Icon(Icons.arrow_back),
                )
              : null,
          title: _searchActive && !selecting
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: t.searchVideos,
                    prefixIcon: const Icon(Icons.search),
                  ),
                )
              : Text(
                  selecting
                      ? t.selectedCount(_selectedIds.length)
                      : showingPlaylistDetail
                      ? selectedPlaylist.name
                      : '클라우드플레이어',
                ),
          actions: selecting
              ? [
                  IconButton(
                    tooltip: t.selectAllVisible,
                    onPressed: _selectAllVisible,
                    icon: const Icon(Icons.select_all),
                  ),
                  IconButton(
                    tooltip: t.favorite,
                    onPressed: _favoriteSelected,
                    icon: const Icon(Icons.star_border),
                  ),
                  IconButton(
                    tooltip: t.addToPlaylist,
                    onPressed: _addSelectedToPlaylist,
                    icon: const Icon(Icons.playlist_add),
                  ),
                  IconButton(
                    tooltip: "Remove selected",
                    onPressed: _removeSelected,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ]
              : _searchActive
              ? [
                  IconButton(
                    tooltip: t.cancelSelection,
                    onPressed: _closeSearch,
                    icon: const Icon(Icons.close),
                  ),
                ]
              : [
                  _RoundActionButton(
                    tooltip: t.searchVideos,
                    onPressed: () => setState(() => _searchActive = true),
                    icon: Icons.search,
                  ),
                  _AvatarActionButton(
                    tooltip: t.googleSignIn,
                    onPressed: _busy || _initializing
                        ? null
                        : _openAccountSheet,
                    email: _user?.email ?? _lastGoogleEmail,
                  ),
                  _RoundActionButton(
                    tooltip: t.settings,
                    onPressed: _busy ? null : _openSettings,
                    icon: Icons.settings_outlined,
                  ),
                ],
        ),
        body: SafeArea(
          child: Row(
            children: [
              if (tabSide == _SideTabSide.left)
                _SideTabs(
                  side: _SideTabSide.left,
                  selectedIndex: _selectedTab.index,
                  tabs: LibraryTab.values,
                  labelFor: _tabLabel,
                  onSelected: _busy ? null : _selectTab,
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 520;
                    final collapseHeaderOnScroll = compact && useSideTabs;
                    final useFloatingMini = compact && useSideTabs;
                    final hasMini =
                        _playbackSummary?.current != null || lastVideo != null;
                    final content = Column(
                      children: [
                        Expanded(
                          child: CustomScrollView(
                            slivers: [
                              SliverPersistentHeader(
                                pinned: !collapseHeaderOnScroll,
                                floating: collapseHeaderOnScroll,
                                delegate: _LibraryHeaderDelegate(
                                  compact: compact,
                                  childBuilder: (context, shrinkProgress) =>
                                      _LibraryHeader(
                                        status: _status,
                                        driveAuthExpired: _driveAuthExpired,
                                        selectedTab: _selectedTab,
                                        compact: compact,
                                        strings: t,
                                        tabLabel: showingPlaylistDetail
                                            ? selectedPlaylist.name
                                            : _tabLabel(_selectedTab),
                                        onAddDrive: _openDriveBrowser,
                                        onPlayInOrder:
                                            visibleVideos.isEmpty || _busy
                                            ? null
                                            : _playVisibleInOrder,
                                        onShuffle:
                                            visibleVideos.isEmpty || _busy
                                            ? null
                                            : _playVisibleShuffled,
                                        onCreatePlaylist: _busy
                                            ? null
                                            : _createEmptyPlaylist,
                                      ),
                                ),
                              ),
                              if (_remoteQueueCandidate != null)
                                SliverToBoxAdapter(
                                  child: _RemoteQueueBanner(
                                    state: _remoteQueueCandidate!,
                                    strings: t,
                                    onImport: () => _importDeviceQueue(
                                      _remoteQueueCandidate!,
                                      startPlayback: false,
                                    ),
                                    onDismiss: () => setState(
                                      () => _remoteQueueCandidate = null,
                                    ),
                                  ),
                                ),
                              if (_selectedTab == LibraryTab.drive &&
                                  _driveImports.any((item) => !item.isDeleted))
                                SliverToBoxAdapter(
                                  child: _DriveImportHistoryBand(
                                    records: _driveImports
                                        .where((item) => !item.isDeleted)
                                        .toList(growable: false),
                                    strings: t,
                                    onReimport: _reimportDriveFolder,
                                  ),
                                ),
                              if (_selectedTab == LibraryTab.playlist &&
                                  selectedPlaylist == null)
                                _PlaylistSliverList(
                                  playlists: _playlists,
                                  strings: t,
                                  coverFor: _coverForPlaylist,
                                  countFor: (playlist) =>
                                      _videosForPlaylist(playlist).length,
                                  onOpen: (playlist) => setState(
                                    () => _selectedPlaylistId = playlist.id,
                                  ),
                                  onPlay: _playPlaylist,
                                  onRename: _renamePlaylist,
                                  onDelete: _deletePlaylist,
                                  onCreate: _createEmptyPlaylist,
                                )
                              else
                                _VideoSliverList(
                                  tab: _selectedTab,
                                  videos: visibleVideos,
                                  busy: _busy,
                                  selectedIds: _selectedIds,
                                  viewMode: resolvedViewMode,
                                  strings: t,
                                  onPlay: _playFromItem,
                                  onToggleSelection: _toggleSelection,
                                  onToggleFavorite: _toggleFavorite,
                                  onRemove: showingPlaylistDetail
                                      ? _removeFromSelectedPlaylist
                                      : _removeVideo,
                                  removeLabel: showingPlaylistDetail
                                      ? t.removeFromPlaylist
                                      : t.removeFromList,
                                ),
                            ],
                          ),
                        ),
                        if (_playbackSummary?.current != null ||
                            lastVideo != null)
                          !compact
                              ? _MiniPlayer(
                                  item: _playbackSummary?.current ?? lastVideo!,
                                  showLivePreview:
                                      _playbackSummary?.current != null,
                                  isPlaying:
                                      _playbackSummary?.isPlaying ?? false,
                                  positionMs:
                                      _playbackSummary?.positionMs ??
                                      (lastVideo?.lastPositionMs ?? 0),
                                  durationMs:
                                      _playbackSummary?.durationMs ??
                                      (lastVideo?.duration ?? 0),
                                  strings: t,
                                  onOpen: _playbackSummary?.current == null
                                      ? _playLastVideo
                                      : _openPlayerFromMini,
                                  onPlayPause: _playbackSummary?.current == null
                                      ? _playLastVideo
                                      : _playPause,
                                  onNext: _playbackSummary?.current == null
                                      ? null
                                      : _next,
                                  onQueue: _playbackSummary?.current == null
                                      ? null
                                      : _showCurrentQueue,
                                  onStop: _playbackSummary?.current == null
                                      ? null
                                      : _stop,
                                )
                              : const SizedBox.shrink(),
                      ],
                    );
                    if (!hasMini || !useFloatingMini) {
                      return content;
                    }
                    return Stack(
                      children: [
                        Positioned.fill(child: content),
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: _FloatingMiniControl(
                            item: _playbackSummary?.current ?? lastVideo!,
                            isPlaying: _playbackSummary?.isPlaying ?? false,
                            strings: t,
                            onOpen: _playbackSummary?.current == null
                                ? _playLastVideo
                                : _openPlayerFromMini,
                            onPlayPause: _playbackSummary?.current == null
                                ? _playLastVideo
                                : _playPause,
                            onNext: _playbackSummary?.current == null
                                ? null
                                : _next,
                            onQueue: _playbackSummary?.current == null
                                ? null
                                : _showCurrentQueue,
                            onStop: _playbackSummary?.current == null
                                ? null
                                : _stop,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (tabSide == _SideTabSide.right)
                _SideTabs(
                  side: _SideTabSide.right,
                  selectedIndex: _selectedTab.index,
                  tabs: LibraryTab.values,
                  labelFor: _tabLabel,
                  onSelected: _busy ? null : _selectTab,
                ),
            ],
          ),
        ),
        bottomNavigationBar: useSideTabs
            ? null
            : _BottomTabs(
                selectedIndex: _selectedTab.index,
                tabs: LibraryTab.values,
                labelFor: _tabLabel,
                onSelected: _busy ? null : _selectTab,
              ),
      ),
    );
  }

  _SideTabSide? _resolvedSideTabSide(MediaQueryData mediaQuery) {
    final phoneLandscape =
        mediaQuery.orientation == Orientation.landscape &&
        mediaQuery.size.shortestSide < 600;
    return switch (_tabBarPlacement) {
      TabBarPlacement.bottom => null,
      TabBarPlacement.automatic => phoneLandscape ? _SideTabSide.right : null,
      TabBarPlacement.landscapeLeft =>
        phoneLandscape ? _SideTabSide.left : null,
      TabBarPlacement.landscapeRight =>
        phoneLandscape ? _SideTabSide.right : null,
    };
  }

  LibraryViewMode _resolvedViewMode(MediaQueryData mediaQuery) {
    return mediaQuery.orientation == Orientation.landscape
        ? _landscapeViewMode
        : _portraitViewMode;
  }

  List<DropdownMenuItem<LibraryViewMode>> _viewModeMenuItems() {
    return [
      DropdownMenuItem(
        value: LibraryViewMode.list,
        child: Text(t.listViewMode),
      ),
      DropdownMenuItem(
        value: LibraryViewMode.grid,
        child: Text(t.gridViewMode),
      ),
    ];
  }
}

enum _SideTabSide { left, right }

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        splashRadius: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        style: const ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
        icon: Icon(icon, color: enabled ? _Ui.text2 : _Ui.text3, size: 21),
      ),
    );
  }
}

class _AvatarActionButton extends StatelessWidget {
  const _AvatarActionButton({
    required this.tooltip,
    required this.email,
    required this.onPressed,
  });

  final String tooltip;
  final String? email;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final letter = (email?.trim().isNotEmpty ?? false)
        ? email!.trim()[0].toUpperCase()
        : 'K';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _Ui.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              letter,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({
    required this.selectedIndex,
    required this.tabs,
    required this.labelFor,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<LibraryTab> tabs;
  final String Function(LibraryTab tab) labelFor;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    final visibleTabs = <LibraryTab>[
      LibraryTab.all,
      LibraryTab.recent,
      LibraryTab.drive,
      LibraryTab.playlist,
    ];
    final selectedTab = tabs[selectedIndex];
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: _Ui.card,
          border: Border(top: BorderSide(color: _Ui.border)),
        ),
        height: 64,
        child: Row(
          children: [
            for (final tab in visibleTabs)
              Expanded(
                child: _BottomTabButton(
                  selected: selectedTab == tab,
                  icon: tab.icon,
                  label: labelFor(tab),
                  onTap: onSelected == null
                      ? null
                      : () => onSelected!(tabs.indexOf(tab)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SideTabs extends StatelessWidget {
  const _SideTabs({
    required this.side,
    required this.selectedIndex,
    required this.tabs,
    required this.labelFor,
    required this.onSelected,
  });

  final _SideTabSide side;
  final int selectedIndex;
  final List<LibraryTab> tabs;
  final String Function(LibraryTab tab) labelFor;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    final visibleTabs = <LibraryTab>[
      LibraryTab.all,
      LibraryTab.recent,
      LibraryTab.drive,
      LibraryTab.playlist,
    ];
    final selectedTab = tabs[selectedIndex];
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: _Ui.card,
        border: side == _SideTabSide.left
            ? Border(right: BorderSide(color: _Ui.border))
            : Border(left: BorderSide(color: _Ui.border)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final tab in visibleTabs)
            Expanded(
              child: _BottomTabButton(
                selected: selectedTab == tab,
                icon: tab.icon,
                label: labelFor(tab),
                onTap: onSelected == null
                    ? null
                    : () => onSelected!(tabs.indexOf(tab)),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomTabButton extends StatelessWidget {
  const _BottomTabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _Ui.accent : _Ui.text3;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _LibraryHeaderDelegate({
    required this.compact,
    required this.childBuilder,
  });

  final bool compact;
  final Widget Function(BuildContext context, double shrinkProgress)
  childBuilder;

  @override
  double get minExtent => compact ? 46 : 58;

  @override
  double get maxExtent => compact ? 46 : 96;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    return Material(
      color: _Ui.bg,
      elevation: overlapsContent ? 1 : 0,
      child: SizedBox.expand(child: childBuilder(context, progress)),
    );
  }

  @override
  bool shouldRebuild(covariant _LibraryHeaderDelegate oldDelegate) {
    return compact != oldDelegate.compact ||
        childBuilder != oldDelegate.childBuilder;
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.status,
    required this.driveAuthExpired,
    required this.selectedTab,
    required this.compact,
    required this.strings,
    required this.tabLabel,
    required this.onAddDrive,
    required this.onPlayInOrder,
    required this.onShuffle,
    required this.onCreatePlaylist,
  });

  final String status;
  final bool driveAuthExpired;
  final LibraryTab selectedTab;
  final bool compact;
  final AppStrings strings;
  final String tabLabel;
  final VoidCallback onAddDrive;
  final VoidCallback? onPlayInOrder;
  final VoidCallback? onShuffle;
  final VoidCallback? onCreatePlaylist;

  @override
  Widget build(BuildContext context) {
    final showDriveAction = selectedTab == LibraryTab.drive;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 4 : 6, 16, compact ? 4 : 6),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Tooltip(
                    message: status,
                    child: Text(
                      tabLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (selectedTab == LibraryTab.drive && driveAuthExpired)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 17,
                      color: _Ui.red,
                    ),
                  ),
              ],
            ),
          ),
          _CompactHeaderTextButton(
            tooltip: strings.playInOrder,
            icon: Icons.play_arrow,
            label: strings.playInOrder,
            onTap: onPlayInOrder,
          ),
          const SizedBox(width: 6),
          _CompactHeaderTextButton(
            tooltip: strings.shufflePlay,
            icon: Icons.shuffle,
            label: strings.shufflePlay,
            onTap: onShuffle,
            active: true,
          ),
          if (showDriveAction) ...[
            const SizedBox(width: 6),
            _CompactHeaderTextButton(
              tooltip: strings.importFromDrive,
              icon: Icons.cloud_download_outlined,
              label: strings.importFromDrive,
              onTap: onAddDrive,
            ),
          ],
          if (selectedTab == LibraryTab.playlist) ...[
            const SizedBox(width: 6),
            _CompactHeaderTextButton(
              tooltip: strings.createPlaylist,
              icon: Icons.add,
              label: strings.newPlaylist,
              onTap: onCreatePlaylist,
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaylistSliverList extends StatelessWidget {
  const _PlaylistSliverList({
    required this.playlists,
    required this.strings,
    required this.coverFor,
    required this.countFor,
    required this.onOpen,
    required this.onPlay,
    required this.onRename,
    required this.onDelete,
    required this.onCreate,
  });

  final List<VideoPlaylist> playlists;
  final AppStrings strings;
  final VideoItem? Function(VideoPlaylist playlist) coverFor;
  final int Function(VideoPlaylist playlist) countFor;
  final ValueChanged<VideoPlaylist> onOpen;
  final ValueChanged<VideoPlaylist> onPlay;
  final ValueChanged<VideoPlaylist> onRename;
  final ValueChanged<VideoPlaylist> onDelete;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.queue_music_outlined, size: 44, color: _Ui.text3),
                const SizedBox(height: 12),
                Text(strings.playlistEmpty, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: Text(strings.createPlaylist),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      sliver: SliverList.separated(
        itemCount: playlists.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final playlist = playlists[index];
          return _PlaylistTile(
            playlist: playlist,
            cover: coverFor(playlist),
            count: countFor(playlist),
            strings: strings,
            onOpen: () => onOpen(playlist),
            onPlay: () => onPlay(playlist),
            onRename: () => onRename(playlist),
            onDelete: () => onDelete(playlist),
          );
        },
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.playlist,
    required this.cover,
    required this.count,
    required this.strings,
    required this.onOpen,
    required this.onPlay,
    required this.onRename,
    required this.onDelete,
  });

  final VideoPlaylist playlist;
  final VideoItem? cover;
  final int count;
  final AppStrings strings;
  final VoidCallback onOpen;
  final VoidCallback onPlay;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final coverItem = cover;
    return Material(
      color: _Ui.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              coverItem == null
                  ? Container(
                      width: 92,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _Ui.surface2,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Icon(Icons.queue_music_outlined, color: _Ui.text3),
                    )
                  : _VideoThumb(
                      source: coverItem.source,
                      thumbnailBase64: coverItem.thumbnailBase64,
                      thumbnailUrl: coverItem.thumbnailUrl,
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _Ui.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _SourcePill(label: strings.videoCount(count)),
                        if (playlist.sourceLabel.isNotEmpty)
                          _SourcePill(label: playlist.sourceLabel),
                        Text(
                          _formatDate(playlist.updatedAt),
                          style: TextStyle(color: _Ui.text2, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: strings.shufflePlay,
                onPressed: count == 0 ? null : onPlay,
                icon: const Icon(Icons.play_arrow),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: _Ui.text3),
                onSelected: (value) {
                  if (value == 'rename') onRename();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'rename', child: Text(strings.rename)),
                  PopupMenuItem(value: 'delete', child: Text(strings.delete)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactHeaderTextButton extends StatelessWidget {
  const _CompactHeaderTextButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final highlighted = active && enabled;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: highlighted ? _Ui.accentDim : _Ui.surface2,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: highlighted
                    ? _Ui.accentDark
                    : enabled
                    ? _Ui.text2
                    : _Ui.text3,
                size: 18,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: highlighted
                      ? _Ui.accentDark
                      : enabled
                      ? _Ui.text2
                      : _Ui.text3,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumeBadge extends StatelessWidget {
  const _ResumeBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _Ui.accentDim,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0x3332BF5E)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          text,
          style: TextStyle(
            color: _Ui.accentDark,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _Ui.surface2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            color: _Ui.text2,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _VideoSliverList extends StatelessWidget {
  const _VideoSliverList({
    required this.tab,
    required this.videos,
    required this.busy,
    required this.selectedIds,
    required this.viewMode,
    required this.strings,
    required this.onPlay,
    required this.onToggleSelection,
    required this.onToggleFavorite,
    required this.onRemove,
    required this.removeLabel,
  });

  final LibraryTab tab;
  final List<VideoItem> videos;
  final bool busy;
  final Set<String> selectedIds;
  final LibraryViewMode viewMode;
  final AppStrings strings;
  final ValueChanged<VideoItem> onPlay;
  final ValueChanged<VideoItem> onToggleSelection;
  final ValueChanged<VideoItem> onToggleFavorite;
  final ValueChanged<VideoItem> onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _EmptyTab(tab: tab, strings: strings),
      );
    }
    if (viewMode == LibraryViewMode.grouped) {
      final children = <Widget>[];
      final groups = <String, List<VideoItem>>{};
      for (final item in videos) {
        final key = item.source == VideoSource.drive
            ? 'Google Drive'
            : strings.local;
        groups.putIfAbsent(key, () => []).add(item);
      }
      final entries = groups.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final entry in entries) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Text(
              '${entry.key} · ${entry.value.length}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        );
        for (final item in entry.value) {
          children.add(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _VideoTile(
                item: item,
                busy: busy,
                selected: selectedIds.contains(item.id),
                selectionMode: selectedIds.isNotEmpty,
                onPlay: () => onPlay(item),
                onToggleSelection: () => onToggleSelection(item),
                onToggleFavorite: () => onToggleFavorite(item),
                onRemove: () => onRemove(item),
                strings: strings,
                removeLabel: removeLabel,
              ),
            ),
          );
          children.add(
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Divider(height: 1),
            ),
          );
        }
      }
      return SliverList(delegate: SliverChildListDelegate(children));
    }

    if (viewMode == LibraryViewMode.grid) {
      final isLandscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        sliver: SliverGrid.builder(
          itemCount: videos.length,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: isLandscape ? 210 : 220,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: isLandscape ? 1.68 : 1.32,
          ),
          itemBuilder: (context, index) {
            final item = videos[index];
            return _VideoGridTile(
              item: item,
              busy: busy,
              selected: selectedIds.contains(item.id),
              selectionMode: selectedIds.isNotEmpty,
              onPlay: () => onPlay(item),
              onToggleSelection: () => onToggleSelection(item),
              onToggleFavorite: () => onToggleFavorite(item),
              onRemove: () => onRemove(item),
              strings: strings,
              removeLabel: removeLabel,
            );
          },
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      sliver: SliverList.separated(
        itemCount: videos.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = videos[index];
          return _VideoTile(
            item: item,
            busy: busy,
            selected: selectedIds.contains(item.id),
            selectionMode: selectedIds.isNotEmpty,
            onPlay: () => onPlay(item),
            onToggleSelection: () => onToggleSelection(item),
            onToggleFavorite: () => onToggleFavorite(item),
            onRemove: () => onRemove(item),
            strings: strings,
            removeLabel: removeLabel,
          );
        },
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.item,
    required this.busy,
    required this.selected,
    required this.selectionMode,
    required this.strings,
    required this.onPlay,
    required this.onToggleSelection,
    required this.onToggleFavorite,
    required this.onRemove,
    required this.removeLabel,
  });

  final VideoItem item;
  final bool busy;
  final bool selected;
  final bool selectionMode;
  final AppStrings strings;
  final VoidCallback onPlay;
  final VoidCallback onToggleSelection;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: selected ? _Ui.accentDim : _Ui.card,
      child: InkWell(
        onLongPress: busy ? null : onToggleSelection,
        onTap: busy ? null : (selectionMode ? onToggleSelection : onPlay),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      _VideoThumb(
                        source: item.source,
                        thumbnailBase64: item.thumbnailBase64,
                        thumbnailUrl: item.thumbnailUrl,
                      ),
                      if (item.duration != null && item.duration! > 0)
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.68),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              child: Text(
                                _formatDuration(item.duration!),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (selected)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.42),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _Ui.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _SourcePill(
                              label: item.source == VideoSource.drive
                                  ? 'Drive'
                                  : strings.local,
                            ),
                            if (_metadataText(item, strings).isNotEmpty)
                              Text(
                                _metadataText(item, strings),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _Ui.text2,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                        if (item.lastPositionMs > 0) ...[
                          const SizedBox(height: 5),
                          _ResumeBadge(
                            text:
                                '${strings.resumeAt} ${_formatDuration(item.lastPositionMs)}',
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 28,
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: busy ? null : onToggleFavorite,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              item.isFavorite ? Icons.star : Icons.star_border,
                              color: item.isFavorite ? _Ui.yellow : _Ui.text3,
                              size: 18,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          enabled: !busy,
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.more_vert,
                            size: 18,
                            color: _Ui.text3,
                          ),
                          onSelected: (value) {
                            if (value == 'delete') onRemove();
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(removeLabel),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (item.lastPositionMs > 0) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    value: item.duration != null && item.duration! > 0
                        ? (item.lastPositionMs / item.duration!).clamp(0.0, 1.0)
                        : null,
                    backgroundColor: _Ui.surface2,
                    color: _Ui.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _metadataText(VideoItem item, AppStrings strings) {
    final parts = <String>[];
    if (item.size != null) {
      parts.add(_formatBytes(item.size!));
    }
    if (item.modifiedTime != null) {
      parts.add(_formatDate(item.modifiedTime!));
    }
    if (item.lastPlayedAt != null) {
      parts.add('${strings.recentlyPlayed} ${_formatDate(item.lastPlayedAt!)}');
    }
    return parts.join(' - ');
  }
}

class _VideoGridTile extends StatelessWidget {
  const _VideoGridTile({
    required this.item,
    required this.busy,
    required this.selected,
    required this.selectionMode,
    required this.strings,
    required this.onPlay,
    required this.onToggleSelection,
    required this.onToggleFavorite,
    required this.onRemove,
    required this.removeLabel,
  });

  final VideoItem item;
  final bool busy;
  final bool selected;
  final bool selectionMode;
  final AppStrings strings;
  final VoidCallback onPlay;
  final VoidCallback onToggleSelection;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _Ui.accentDim : _Ui.card,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: busy ? null : onToggleSelection,
        onTap: busy ? null : (selectionMode ? onToggleSelection : onPlay),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return _VideoThumb(
                  source: item.source,
                  thumbnailBase64: item.thumbnailBase64,
                  thumbnailUrl: item.thumbnailUrl,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  borderRadius: 0,
                );
              },
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.22),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.72),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 7,
              top: 7,
              child: _SourcePill(
                label: item.source == VideoSource.drive
                    ? 'Drive'
                    : strings.local,
              ),
            ),
            Positioned(
              right: 3,
              top: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: busy ? null : onToggleFavorite,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        item.isFavorite ? Icons.star : Icons.star_border,
                        color: item.isFavorite ? _Ui.yellow : Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    enabled: !busy,
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.more_vert,
                      size: 17,
                      color: Colors.white,
                    ),
                    onSelected: (value) {
                      if (value == 'delete') onRemove();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'delete', child: Text(removeLabel)),
                    ],
                  ),
                ],
              ),
            ),
            if (item.duration != null && item.duration! > 0)
              Positioned(
                right: 7,
                bottom: 27,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.70),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    child: Text(
                      _formatDuration(item.duration!),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ),
            if (item.lastPositionMs > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  value: item.duration != null && item.duration! > 0
                      ? (item.lastPositionMs / item.duration!).clamp(0.0, 1.0)
                      : null,
                  backgroundColor: Colors.white.withValues(alpha: 0.24),
                  color: _Ui.accent,
                ),
              ),
            if (selected)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.42),
                child: const Icon(Icons.check_circle, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailMemoryCache {
  static const _maxEntries = 80;
  static const _maxBytes = 32 * 1024 * 1024;
  static final _images = <String, _ThumbnailCacheEntry>{};
  static int _byteCount = 0;

  static int get entryCount => _images.length;
  static int get byteCount => _byteCount;

  static MemoryImage? imageFor(String encoded) {
    final existing = _images.remove(encoded);
    if (existing != null) {
      _images[encoded] = existing;
      return existing.image;
    }
    try {
      final bytes = base64Decode(encoded);
      final entry = _ThumbnailCacheEntry(
        image: MemoryImage(bytes),
        byteCount: bytes.length,
      );
      _images[encoded] = entry;
      _byteCount += entry.byteCount;
      while (_images.length > _maxEntries || _byteCount > _maxBytes) {
        final removed = _images.remove(_images.keys.first);
        if (removed != null) _byteCount -= removed.byteCount;
      }
      return entry.image;
    } on FormatException {
      return null;
    }
  }
}

class _ThumbnailCacheEntry {
  const _ThumbnailCacheEntry({required this.image, required this.byteCount});

  final MemoryImage image;
  final int byteCount;
}

class _VideoThumb extends StatelessWidget {
  const _VideoThumb({
    required this.source,
    this.thumbnailBase64,
    this.thumbnailUrl,
    this.width = 92,
    this.height = 56,
    this.borderRadius = 5,
  });

  final VideoSource source;
  final String? thumbnailBase64;
  final String? thumbnailUrl;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDrive = source == VideoSource.drive;
    final thumbnail = thumbnailBase64;
    final thumbnailImage = thumbnail != null && thumbnail.isNotEmpty
        ? _ThumbnailMemoryCache.imageFor(thumbnail)
        : null;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDrive ? const Color(0xff12324a) : const Color(0xff2a2f37),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: thumbnailImage != null
          ? Image(
              image: thumbnailImage,
              fit: BoxFit.cover,
              width: width,
              height: height,
              gaplessPlayback: true,
            )
          : thumbnailUrl != null && thumbnailUrl!.isNotEmpty
          ? Image.network(
              thumbnailUrl!,
              fit: BoxFit.cover,
              width: width,
              height: height,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  _SourceIcon(isDrive: isDrive),
            )
          : _SourceIcon(isDrive: isDrive),
    );
  }
}

class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.isDrive});

  final bool isDrive;

  @override
  Widget build(BuildContext context) {
    return Icon(
      isDrive ? Icons.cloud_outlined : Icons.movie_outlined,
      color: Colors.white,
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.tab, required this.strings});

  final LibraryTab tab;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final message = switch (tab) {
      LibraryTab.local => strings.noVideos,
      LibraryTab.drive => strings.importVideosFromDrive,
      LibraryTab.recent => strings.noRecentVideos,
      LibraryTab.playlist => strings.playlistEmpty,
      LibraryTab.all => strings.noVideos,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.icon,
              size: 44,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _DriveImportHistoryBand extends StatelessWidget {
  const _DriveImportHistoryBand({
    required this.records,
    required this.strings,
    required this.onReimport,
  });

  final List<DriveImportRecord> records;
  final AppStrings strings;
  final Future<void> Function(DriveImportRecord record) onReimport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.isKo
                ? '\uAC00\uC838\uC628 Drive \uD3F4\uB354'
                : 'Imported Drive folders',
            style: TextStyle(
              color: _Ui.text,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          for (final record in records.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined, color: _Ui.accent),
              title: Text(
                record.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${strings.videoCount(record.videoIds.length)} · ${_shortDateTime(record.updatedAt)}',
              ),
              trailing: IconButton(
                tooltip: strings.isKo
                    ? '\uB2E4\uC2DC \uAC00\uC838\uC624\uAE30'
                    : 'Reimport',
                onPressed: () => onReimport(record),
                icon: const Icon(Icons.refresh),
              ),
            ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _SyncPageSnapshot {
  const _SyncPageSnapshot({
    required this.health,
    required this.account,
    required this.deviceId,
    required this.deviceName,
    required this.currentQueue,
    required this.remoteCandidate,
    required this.deviceQueues,
    required this.lastBackupAt,
  });

  final SyncHealth health;
  final String? account;
  final String deviceId;
  final String deviceName;
  final PlaybackStateSummary? currentQueue;
  final CloudPlaybackState? remoteCandidate;
  final List<CloudPlaybackState> deviceQueues;
  final DateTime? lastBackupAt;
}

class _SyncAndBackupPage extends StatefulWidget {
  const _SyncAndBackupPage({
    required this.strings,
    required this.snapshot,
    required this.onSync,
    required this.onBackup,
    required this.loadBackups,
    required this.onRestore,
    required this.onImportRemote,
  });

  final AppStrings strings;
  final _SyncPageSnapshot Function() snapshot;
  final Future<void> Function() onSync;
  final Future<void> Function() onBackup;
  final Future<List<_CloudBackupEntry>> Function() loadBackups;
  final Future<void> Function(_CloudBackupEntry entry) onRestore;
  final Future<void> Function(CloudPlaybackState state) onImportRemote;

  @override
  State<_SyncAndBackupPage> createState() => _SyncAndBackupPageState();
}

class _SyncAndBackupPageState extends State<_SyncAndBackupPage> {
  bool _busy = false;
  List<_CloudBackupEntry> _backups = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_refreshBackups());
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refreshBackups(updateBusy: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshBackups({bool updateBusy = true}) async {
    try {
      final backups = await widget.loadBackups();
      if (mounted) setState(() => _backups = backups);
    } catch (_) {
      // The status section reports the Drive error from the parent state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final isKo = strings.isKo;
    final state = widget.snapshot();
    final lastSync = state.health.lastSuccessAt;
    final otherDevices = <String, CloudPlaybackState>{};
    for (final queue in state.deviceQueues) {
      if (queue.deviceId == state.deviceId) continue;
      final existing = otherDevices[queue.deviceId];
      if (existing == null || queue.updatedAt.isAfter(existing.updatedAt)) {
        otherDevices[queue.deviceId] = queue;
      }
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isKo ? '\uB3D9\uAE30\uD654 \uBC0F \uBC31\uC5C5' : 'Sync and backup',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            _SettingsSectionTitle(
              title: isKo ? '\uB3D9\uAE30\uD654 \uC0C1\uD0DC' : 'Sync status',
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _syncIcon(state.health.phase),
                color: _syncColor(state.health.phase),
              ),
              title: Text(_syncLabel(state.health.phase, isKo)),
              subtitle: Text(
                lastSync == null
                    ? (isKo
                          ? '\uC544\uC9C1 \uB3D9\uAE30\uD654\uD558\uC9C0 \uC54A\uC74C'
                          : 'Not synced yet')
                    : '${isKo ? '\uB9C8\uC9C0\uB9C9 \uB3D9\uAE30\uD654' : 'Last sync'}: ${_shortDateTime(lastSync)}',
              ),
              trailing: IconButton(
                tooltip: isKo ? '\uC9C0\uAE08 \uB3D9\uAE30\uD654' : 'Sync now',
                onPressed: _busy ? null : () => _run(widget.onSync),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone_android_outlined),
              title: Text(state.deviceName),
              subtitle: Text(
                '${isKo ? '\uC774 \uAE30\uAE30 \uD050' : 'This device queue'}: ${state.currentQueue?.queue.length ?? 0}',
              ),
            ),
            if (state.remoteCandidate != null)
              Material(
                color: _Ui.accentDim,
                borderRadius: BorderRadius.circular(8),
                child: ListTile(
                  leading: const Icon(Icons.devices, color: _Ui.accent),
                  title: Text(
                    isKo
                        ? '${state.remoteCandidate!.deviceName}\uC758 \uCD5C\uC2E0 \uD050'
                        : 'Latest queue from ${state.remoteCandidate!.deviceName}',
                  ),
                  subtitle: Text(
                    strings.videoCount(
                      state.remoteCandidate!.queue.queueIds.length,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.onImportRemote(state.remoteCandidate!),
                          ),
                    child: Text(isKo ? '\uAC00\uC838\uC624\uAE30' : 'Import'),
                  ),
                ),
              ),
            if (otherDevices.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final queue in otherDevices.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.computer_outlined),
                  title: Text(queue.deviceName),
                  subtitle: Text(
                    '${strings.videoCount(queue.queue.queueIds.length)} · ${_shortDateTime(queue.updatedAt)}',
                  ),
                  trailing: TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => widget.onImportRemote(queue)),
                    child: Text(isKo ? '\uAC00\uC838\uC624\uAE30' : 'Import'),
                  ),
                ),
            ],
            const Divider(height: 28),
            _SettingsSectionTitle(
              title: isKo
                  ? '\uD074\uB77C\uC6B0\uB4DC \uBC31\uC5C5'
                  : 'Cloud backups',
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.backup_outlined),
              title: Text(isKo ? '\uC9C0\uAE08 \uBC31\uC5C5' : 'Back up now'),
              subtitle: Text(
                state.lastBackupAt == null
                    ? (isKo
                          ? '\uC544\uC9C1 \uBC31\uC5C5 \uC5C6\uC74C'
                          : 'No backup yet')
                    : _shortDateTime(state.lastBackupAt!),
              ),
              onTap: _busy ? null : () => _run(widget.onBackup),
            ),
            if (_backups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  isKo
                      ? '\uBCF5\uC6D0\uD560 \uBC31\uC5C5\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.'
                      : 'No backups available.',
                  style: TextStyle(color: _Ui.text2),
                ),
              )
            else
              for (final backup in _backups)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history),
                  title: Text(_shortDateTime(backup.payload.createdAt)),
                  subtitle: Text(
                    '${backup.payload.deviceName} · ${strings.videoCount(backup.payload.activeVideoCount)} · ${backup.payload.activePlaylistCount} ${isKo ? '\uAC1C \uC7AC\uC0DD\uBAA9\uB85D' : 'playlists'}',
                  ),
                  trailing: TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(
                                  isKo
                                      ? '\uBC31\uC5C5 \uBCF5\uC6D0'
                                      : 'Restore backup',
                                ),
                                content: Text(
                                  isKo
                                      ? 'Drive \uC601\uC0C1, \uC7AC\uC0DD\uBAA9\uB85D, \uD050\uB97C \uC774 \uC2DC\uC810\uC73C\uB85C \uBCF5\uC6D0\uD569\uB2C8\uB2E4. \uB85C\uCEEC \uC601\uC0C1\uC740 \uC720\uC9C0\uB429\uB2C8\uB2E4.'
                                      : 'Restore Drive videos, playlists, and queue. Local videos stay on this device.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: Text(
                                      MaterialLocalizations.of(
                                        context,
                                      ).cancelButtonLabel,
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text(
                                      isKo ? '\uBCF5\uC6D0' : 'Restore',
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await _run(() => widget.onRestore(backup));
                            }
                          },
                    child: Text(isKo ? '\uBCF5\uC6D0' : 'Restore'),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  IconData _syncIcon(SyncPhase phase) => switch (phase) {
    SyncPhase.syncing => Icons.sync,
    SyncPhase.synced => Icons.cloud_done_outlined,
    SyncPhase.offline => Icons.cloud_off_outlined,
    SyncPhase.reconnectRequired => Icons.link_off,
    SyncPhase.failed => Icons.error_outline,
    SyncPhase.idle => Icons.cloud_outlined,
  };

  Color _syncColor(SyncPhase phase) => switch (phase) {
    SyncPhase.synced => _Ui.accent,
    SyncPhase.offline ||
    SyncPhase.reconnectRequired ||
    SyncPhase.failed => _Ui.red,
    _ => _Ui.text2,
  };

  String _syncLabel(SyncPhase phase, bool isKo) => switch (phase) {
    SyncPhase.syncing => isKo ? '\uB3D9\uAE30\uD654 \uC911' : 'Syncing',
    SyncPhase.synced => isKo ? '\uB3D9\uAE30\uD654 \uC815\uC0C1' : 'Synced',
    SyncPhase.offline => isKo ? '\uC624\uD504\uB77C\uC778' : 'Offline',
    SyncPhase.reconnectRequired =>
      isKo ? '\uC7AC\uC5F0\uACB0 \uD544\uC694' : 'Reconnect required',
    SyncPhase.failed =>
      isKo ? '\uB3D9\uAE30\uD654 \uC2E4\uD328' : 'Sync failed',
    SyncPhase.idle => isKo ? '\uB300\uAE30 \uC911' : 'Idle',
  };
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          color: _Ui.text,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DiagnosticsPage extends StatelessWidget {
  const _DiagnosticsPage({
    required this.strings,
    required this.rows,
    required this.events,
    required this.onCopy,
  });

  final AppStrings strings;
  final Map<String, String> rows;
  final List<DiagnosticEvent> events;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.isKo ? '\uC9C4\uB2E8 \uB3C4\uAD6C' : 'Diagnostics'),
        actions: [
          IconButton(
            tooltip: strings.isKo ? '\uB85C\uADF8 \uBCF5\uC0AC' : 'Copy logs',
            onPressed: () async {
              await onCopy();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      strings.isKo
                          ? '\uC9C4\uB2E8 \uB85C\uADF8\uB97C \uBCF5\uC0AC\uD588\uC2B5\uB2C8\uB2E4.'
                          : 'Diagnostics copied.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            for (final entry in rows.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(entry.key),
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 210),
                  child: Text(
                    entry.value,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _Ui.text2, fontSize: 12),
                  ),
                ),
              ),
            const Divider(height: 28),
            _SettingsSectionTitle(
              title: strings.isKo
                  ? '\uCD5C\uADFC \uC774\uBCA4\uD2B8'
                  : 'Recent events',
            ),
            if (events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  strings.isKo
                      ? '\uAE30\uB85D\uB41C \uC774\uBCA4\uD2B8\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.'
                      : 'No events recorded.',
                  style: TextStyle(color: _Ui.text2),
                ),
              )
            else
              for (final event in events)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    event.failureKind == null
                        ? Icons.info_outline
                        : Icons.error_outline,
                    color: event.failureKind == null ? _Ui.text3 : _Ui.red,
                    size: 19,
                  ),
                  title: Text(
                    event.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${event.category} · ${_shortDateTime(event.timestamp)} · ${event.httpStatus ?? '-'}',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RemoteQueueBanner extends StatelessWidget {
  const _RemoteQueueBanner({
    required this.state,
    required this.strings,
    required this.onImport,
    required this.onDismiss,
  });

  final CloudPlaybackState state;
  final AppStrings strings;
  final Future<void> Function() onImport;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final isKo = strings.isKo;
    return ColoredBox(
      color: _Ui.accentDim,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.devices, color: _Ui.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isKo
                        ? '${state.deviceName}\uC5D0\uC11C \uBCF4\uB358 \uD050\uAC00 \uC788\uC2B5\uB2C8\uB2E4'
                        : 'A newer queue is available from ${state.deviceName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _Ui.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    isKo
                        ? '${state.queue.queueIds.length}\uAC1C \uC601\uC0C1 \u00B7 ${_shortDateTime(state.updatedAt)}'
                        : '${state.queue.queueIds.length} videos · ${_shortDateTime(state.updatedAt)}',
                    style: TextStyle(color: _Ui.text2, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () async => onImport(),
              child: Text(isKo ? '\uAC00\uC838\uC624\uAE30' : 'Import'),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueHubPage extends StatelessWidget {
  const _QueueHubPage({
    required this.strings,
    required this.current,
    required this.recentQueues,
    required this.deviceQueues,
    required this.videoById,
    required this.ownDeviceId,
    required this.onPlayCurrent,
    required this.onRestoreRecent,
    required this.onImportDeviceQueue,
  });

  final AppStrings strings;
  final PlaybackStateSummary? current;
  final List<RecentQueueSnapshot> recentQueues;
  final List<CloudPlaybackState> deviceQueues;
  final Map<String, VideoItem> videoById;
  final String ownDeviceId;
  final Future<void> Function(int index) onPlayCurrent;
  final Future<void> Function(RecentQueueSnapshot snapshot) onRestoreRecent;
  final Future<void> Function(CloudPlaybackState state) onImportDeviceQueue;

  @override
  Widget build(BuildContext context) {
    final isKo = strings.isKo;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isKo ? '\uD050' : 'Queues'),
          bottom: TabBar(
            labelColor: _Ui.accent,
            unselectedLabelColor: _Ui.text2,
            indicatorColor: _Ui.accent,
            tabs: [
              Tab(text: isKo ? '\uD604\uC7AC \uD050' : 'Current'),
              Tab(text: isKo ? '\uCD5C\uADFC \uD050' : 'Recent'),
              Tab(text: isKo ? '\uB2E4\uB978 \uAE30\uAE30' : 'Devices'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _currentQueue(context),
            _recentQueueList(context),
            _deviceQueueList(context),
          ],
        ),
      ),
    );
  }

  Widget _currentQueue(BuildContext context) {
    final summary = current;
    if (summary == null || summary.queue.isEmpty) {
      return _queueEmpty(strings.queueEmpty);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: summary.queue.length + 1,
      separatorBuilder: (_, _) => Divider(color: _Ui.border, height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _QueueModeChip(
                  icon: summary.shuffleEnabled
                      ? Icons.shuffle
                      : Icons.format_list_numbered,
                  label: summary.shuffleEnabled
                      ? (strings.isKo ? '\uC154\uD50C' : 'Shuffle')
                      : (strings.isKo ? '\uC21C\uC11C' : 'In order'),
                ),
                _QueueModeChip(
                  icon: summary.repeatMode == PlayerRepeatMode.one
                      ? Icons.repeat_one
                      : Icons.repeat,
                  label: switch (summary.repeatMode) {
                    PlayerRepeatMode.off =>
                      strings.isKo ? '\uBC18\uBCF5 \uAEBC\uC9D0' : 'Repeat off',
                    PlayerRepeatMode.all =>
                      strings.isKo ? '\uC804\uCCB4 \uBC18\uBCF5' : 'Repeat all',
                    PlayerRepeatMode.one =>
                      strings.isKo
                          ? '\uD55C \uC601\uC0C1 \uBC18\uBCF5'
                          : 'Repeat one',
                  },
                ),
                _QueueModeChip(
                  icon: Icons.video_collection_outlined,
                  label: strings.videoCount(summary.queue.length),
                ),
              ],
            ),
          );
        }
        final itemIndex = index - 1;
        final item = summary.queue[itemIndex];
        final selected = itemIndex == summary.currentIndex;
        return Material(
          color: selected ? _Ui.accentDim : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            leading: Icon(
              selected ? Icons.play_arrow : Icons.video_file_outlined,
              color: selected ? _Ui.accent : _Ui.text3,
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? _Ui.accent : _Ui.text,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            subtitle: Text(selected ? strings.nowPlaying : strings.tapToPlay),
            onTap: () async {
              await onPlayCurrent(itemIndex);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        );
      },
    );
  }

  Widget _recentQueueList(BuildContext context) {
    final queues = recentQueues
        .where((queue) => queue.queueIds.any(videoById.containsKey))
        .toList(growable: false);
    if (queues.isEmpty) {
      return _queueEmpty(
        strings.isKo
            ? '\uC544\uC9C1 \uC800\uC7A5\uB41C \uCD5C\uADFC \uD050\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.'
            : 'No recent queues yet.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: queues.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final queue = queues[index];
        return _QueueSnapshotTile(
          title: queue.title ?? strings.currentQueue,
          subtitle:
              '${queue.deviceName} · ${strings.videoCount(queue.queueIds.length)} · ${_shortDateTime(queue.updatedAt)}',
          shuffleEnabled: queue.shuffleEnabled,
          onImport: () async {
            await onRestoreRecent(queue);
            if (context.mounted) Navigator.pop(context);
          },
          isKo: strings.isKo,
        );
      },
    );
  }

  Widget _deviceQueueList(BuildContext context) {
    final byDevice = <String, CloudPlaybackState>{};
    for (final queue in deviceQueues) {
      if (queue.deviceId == ownDeviceId || queue.queue.queueIds.isEmpty) {
        continue;
      }
      final existing = byDevice[queue.deviceId];
      if (existing == null || queue.updatedAt.isAfter(existing.updatedAt)) {
        byDevice[queue.deviceId] = queue;
      }
    }
    final queues = byDevice.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (queues.isEmpty) {
      return _queueEmpty(
        strings.isKo
            ? '\uB2E4\uB978 \uAE30\uAE30\uC5D0\uC11C \uC800\uC7A5\uB41C \uD050\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.'
            : 'No queues from other devices.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: queues.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final queue = queues[index];
        return _QueueSnapshotTile(
          title: queue.queue.title ?? queue.deviceName,
          subtitle:
              '${queue.deviceName} · ${strings.videoCount(queue.queue.queueIds.length)} · ${_shortDateTime(queue.updatedAt)}',
          shuffleEnabled: queue.queue.shuffleEnabled,
          onImport: () async {
            await onImportDeviceQueue(queue);
            if (context.mounted) Navigator.pop(context);
          },
          isKo: strings.isKo,
        );
      },
    );
  }

  Widget _queueEmpty(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music_outlined, color: _Ui.text3, size: 42),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: _Ui.text2),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueModeChip extends StatelessWidget {
  const _QueueModeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: _Ui.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _Ui.text2),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: _Ui.text2, fontSize: 11)),
        ],
      ),
    );
  }
}

class _QueueSnapshotTile extends StatelessWidget {
  const _QueueSnapshotTile({
    required this.title,
    required this.subtitle,
    required this.shuffleEnabled,
    required this.onImport,
    required this.isKo,
  });

  final String title;
  final String subtitle;
  final bool shuffleEnabled;
  final Future<void> Function() onImport;
  final bool isKo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _Ui.card,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Icon(
              shuffleEnabled ? Icons.shuffle : Icons.format_list_numbered,
              color: _Ui.accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _Ui.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _Ui.text2, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () async => onImport(),
              child: Text(isKo ? '\uAC00\uC838\uC624\uAE30' : 'Import'),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class _MiniPlayer extends StatefulWidget {
  const _MiniPlayer({
    required this.item,
    required this.showLivePreview,
    required this.isPlaying,
    required this.positionMs,
    required this.durationMs,
    required this.strings,
    required this.onOpen,
    required this.onPlayPause,
    required this.onNext,
    required this.onQueue,
    required this.onStop,
  });

  final VideoItem item;
  final bool showLivePreview;
  final bool isPlaying;
  final int positionMs;
  final int durationMs;
  final AppStrings strings;
  final VoidCallback onOpen;
  final VoidCallback onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onQueue;
  final VoidCallback? onStop;

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final progress = widget.durationMs <= 0
        ? 0.0
        : (widget.positionMs / widget.durationMs).clamp(0.0, 1.0);
    return Material(
      color: _Ui.card,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: InkWell(
        onTap: widget.onOpen,
        onHighlightChanged: (value) {
          if (_pressed == value) return;
          setState(() => _pressed = value);
        },
        splashColor: _Ui.accent.withValues(alpha: 0.10),
        highlightColor: Colors.transparent,
        child: SafeArea(
          top: false,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            color: _pressed ? _Ui.accent.withValues(alpha: 0.08) : _Ui.card,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 2.5,
                  backgroundColor: _Ui.surface2,
                  color: _pressed ? _Ui.accentDark : _Ui.accent,
                ),
                SizedBox(
                  height: 60,
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      _MiniPreview(
                        item: widget.item,
                        showLivePreview: widget.showLivePreview,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _Ui.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.positionMs > 0
                                  ? '${_formatDuration(widget.positionMs)} ${widget.strings.resume}'
                                  : widget.item.source == VideoSource.drive
                                  ? 'Google Drive'
                                  : widget.strings.local,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _Ui.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _MiniCircleButton(
                        icon: widget.isPlaying ? Icons.pause : Icons.play_arrow,
                        onPressed: widget.onPlayPause,
                      ),
                      IconButton(
                        tooltip: widget.strings.currentQueue,
                        onPressed: widget.onQueue,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 34,
                          height: 34,
                        ),
                        icon: Icon(
                          Icons.queue_music,
                          size: 19,
                          color: widget.onQueue == null ? _Ui.text3 : _Ui.text2,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingMiniControl extends StatelessWidget {
  const _FloatingMiniControl({
    required this.item,
    required this.isPlaying,
    required this.strings,
    required this.onOpen,
    required this.onPlayPause,
    required this.onNext,
    required this.onQueue,
    required this.onStop,
  });

  final VideoItem item;
  final bool isPlaying;
  final AppStrings strings;
  final VoidCallback onOpen;
  final VoidCallback onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onQueue;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 10,
      borderRadius: BorderRadius.circular(999),
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onOpen,
        child: Container(
          width: 360,
          height: 42,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: _Ui.card.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _Ui.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.graphic_eq, size: 17, color: _Ui.accentDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _Ui.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _MiniFlatButton(
                tooltip: isPlaying ? 'Pause' : 'Play',
                icon: isPlaying ? Icons.pause : Icons.play_arrow,
                onPressed: onPlayPause,
              ),
              _MiniFlatButton(
                tooltip: 'Next',
                icon: Icons.skip_next,
                onPressed: onNext,
              ),
              _MiniFlatButton(
                tooltip: strings.currentQueue,
                icon: Icons.queue_music,
                onPressed: onQueue,
              ),
              _MiniFlatButton(
                tooltip: 'Stop',
                icon: Icons.stop,
                onPressed: onStop,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniFlatButton extends StatelessWidget {
  const _MiniFlatButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      icon: Icon(
        icon,
        size: 18,
        color: onPressed == null ? _Ui.text3 : _Ui.text2,
      ),
    );
  }
}

class _MiniPreview extends StatelessWidget {
  const _MiniPreview({required this.item, required this.showLivePreview});

  final VideoItem item;
  final bool showLivePreview;

  @override
  Widget build(BuildContext context) {
    if (showLivePreview && io.Platform.isAndroid) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: const SizedBox(
          width: 92,
          height: 52,
          child: IgnorePointer(
            child: AndroidView(viewType: 'drive_shuffle_player/mini_player'),
          ),
        ),
      );
    }
    return _VideoThumb(
      source: item.source,
      thumbnailBase64: item.thumbnailBase64,
      thumbnailUrl: item.thumbnailUrl,
      width: 92,
      height: 52,
      borderRadius: 7,
    );
  }
}

class _MiniCircleButton extends StatelessWidget {
  const _MiniCircleButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _Ui.surface2, shape: BoxShape.circle),
        child: Icon(icon, color: _Ui.text, size: 16),
      ),
    );
  }
}

class _DrivePickerDialog extends StatefulWidget {
  const _DrivePickerDialog({
    required this.loadEntries,
    required this.loadFolderTreeVideos,
  });

  final Future<List<DriveEntry>> Function(String parentId) loadEntries;
  final Future<DriveImportResult> Function(
    String folderId,
    String sourceName,
    ValueChanged<DriveImportProgress> onProgress,
  )
  loadFolderTreeVideos;

  @override
  State<_DrivePickerDialog> createState() => _DrivePickerDialogState();
}

class _DrivePickerDialogState extends State<_DrivePickerDialog> {
  final List<DriveEntry> _path = const [
    DriveEntry(
      id: 'root',
      name: "My Drive",
      type: DriveEntryType.folder,
      mimeType: _driveFolderMimeType,
    ),
  ].toList();
  final Map<String, DriveEntry> _selectedEntries = {};
  late Future<List<DriveEntry>> _entries = widget.loadEntries(_current.id);
  List<DriveEntry> _visibleEntries = const [];
  bool _collecting = false;
  String _collectingName = '';
  String _currentScanFolder = '';
  int _scannedFolderCount = 0;
  int _foundVideoCount = 0;

  DriveEntry get _current => _path.last;
  bool get _hasSelection => _selectedEntries.isNotEmpty;

  void _openFolder(DriveEntry folder) {
    if (_collecting) return;
    setState(() {
      _path.add(folder);
      _visibleEntries = const [];
      _entries = widget.loadEntries(folder.id);
    });
  }

  void _goUp() {
    if (_collecting || _path.length <= 1) return;
    setState(() {
      _path.removeLast();
      _visibleEntries = const [];
      _entries = widget.loadEntries(_current.id);
    });
  }

  void _refresh() {
    if (_collecting) return;
    setState(() {
      _visibleEntries = const [];
      _entries = widget.loadEntries(_current.id);
    });
  }

  void _toggleSelected(DriveEntry entry) {
    setState(() {
      if (_selectedEntries.containsKey(entry.id)) {
        _selectedEntries.remove(entry.id);
      } else {
        _selectedEntries[entry.id] = entry;
      }
    });
  }

  void _clearSelection() => setState(_selectedEntries.clear);

  bool _handleBack() {
    if (_collecting) return true;
    if (_hasSelection) {
      _clearSelection();
      return true;
    }
    if (_path.length > 1) {
      _goUp();
      return true;
    }
    return false;
  }

  Future<void> _importSelected() {
    final selected = _selectedEntries.values.toList();
    return _importEntries(
      videos: selected.where((entry) => entry.isVideo).toList(),
      folders: selected.where((entry) => entry.isFolder).toList(),
      sourceName: selected.length == 1
          ? selected.first.name
          : "${selected.length} items",
    );
  }

  Future<void> _addCurrentFolderTree() {
    return _importEntries(
      videos: const [],
      folders: [_current],
      sourceName: _current.name,
    );
  }

  Future<void> _importEntries({
    required List<DriveEntry> videos,
    required List<DriveEntry> folders,
    required String sourceName,
  }) async {
    if (videos.isEmpty && folders.isEmpty) return;
    setState(() {
      _collecting = true;
      _collectingName = sourceName;
      _currentScanFolder = sourceName;
      _scannedFolderCount = 0;
      _foundVideoCount = videos.length;
    });

    final items = videos.map((entry) => entry.toVideoItem()).toList();
    var foldersScanned = 0;
    var videosFound = videos.length;

    try {
      for (final folder in folders) {
        final baseFolders = foldersScanned;
        final baseVideos = videosFound;
        final result = await widget.loadFolderTreeVideos(
          folder.id,
          folder.name,
          (progress) {
            if (!mounted) return;
            setState(() {
              _currentScanFolder = progress.currentFolderName;
              _scannedFolderCount = baseFolders + progress.foldersScanned;
              _foundVideoCount = baseVideos + progress.videosFound;
            });
          },
        );
        items.addAll(result.items);
        foldersScanned += result.foldersScanned;
        videosFound += result.videosFound;
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        DriveImportResult(
          items: items,
          sourceName: sourceName,
          sourceFolders: {for (final folder in folders) folder.id: folder.name},
          foldersScanned: foldersScanned,
          videosFound: videosFound,
          createPlaylist: folders.isNotEmpty,
        ),
      );
    } finally {
      if (mounted) setState(() => _collecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedEntries.length;
    final currentFolderVideos = _visibleEntries
        .where((entry) => entry.isVideo)
        .length;

    final hasInternalBackTarget =
        _collecting || _hasSelection || _path.length > 1;

    return PopScope(
      canPop: !hasInternalBackTarget,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: _Ui.bg,
          appBar: AppBar(
            leading: IconButton(
              tooltip: "Close",
              onPressed: _collecting ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
            title: Text(_hasSelection ? "$selectedCount개 선택" : "Drive에서 가져오기"),
            actions: [
              if (_hasSelection)
                TextButton(
                  onPressed: _collecting ? null : _clearSelection,
                  child: Text("선택 해제", style: TextStyle(color: _Ui.text2)),
                ),
              IconButton(
                tooltip: "새로고침",
                onPressed: _collecting ? null : _refresh,
                icon: Icon(Icons.refresh, color: _Ui.text2),
              ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  _DrivePickerPathBar(
                    path: _path,
                    onGoUp: _path.length > 1 ? _goUp : null,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: FutureBuilder<List<DriveEntry>>(
                      future: _entries,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text(snapshot.error.toString()));
                        }

                        final entries = (snapshot.data ?? const <DriveEntry>[])
                            .where((entry) => !entry.isSubtitle)
                            .toList(growable: false);
                        _visibleEntries = entries;
                        if (entries.isEmpty) {
                          return const Center(
                            child: Text('No items in this folder.'),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: entries.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            return _DrivePickerEntryTile(
                              entry: entry,
                              selected: _selectedEntries.containsKey(entry.id),
                              selectionMode: _hasSelection,
                              onOpen: entry.isFolder
                                  ? () => _openFolder(entry)
                                  : null,
                              onToggleSelected: () => _toggleSelected(entry),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (_collecting)
                _DrivePickerImportOverlay(
                  collectingName: _collectingName,
                  currentScanFolder: _currentScanFolder,
                  scannedFolderCount: _scannedFolderCount,
                  foundVideoCount: _foundVideoCount,
                ),
            ],
          ),
          bottomNavigationBar: _DrivePickerSelectionBar(
            selectedCount: selectedCount,
            currentFolderVideos: currentFolderVideos,
            collecting: _collecting,
            onAddSelected: selectedCount == 0 ? null : _importSelected,
            onClearSelection: selectedCount == 0 ? null : _clearSelection,
            onAddCurrentFolder: _addCurrentFolderTree,
          ),
        ),
      ),
    );
  }
}

class _DrivePickerPathBar extends StatelessWidget {
  const _DrivePickerPathBar({required this.path, required this.onGoUp});

  final List<DriveEntry> path;
  final VoidCallback? onGoUp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: "Parent folder",
            onPressed: onGoUp,
            icon: const Icon(Icons.arrow_upward),
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
      ),
    );
  }
}

class _DrivePickerEntryTile extends StatelessWidget {
  const _DrivePickerEntryTile({
    required this.entry,
    required this.selected,
    required this.selectionMode,
    required this.onOpen,
    required this.onToggleSelected,
  });

  final DriveEntry entry;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onOpen;
  final VoidCallback onToggleSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: selected ? _Ui.accentDim : _Ui.card,
      child: InkWell(
        onTap: entry.isFolder && !selectionMode ? onOpen : onToggleSelected,
        onLongPress: onToggleSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                activeColor: _Ui.accent,
                onChanged: (_) => onToggleSelected(),
              ),
              const SizedBox(width: 4),
              Icon(
                entry.isFolder ? Icons.folder_outlined : Icons.movie_outlined,
                size: 30,
                color: entry.isFolder ? _Ui.text3 : _Ui.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.isFolder
                          ? "폴더"
                          : _drivePickerVideoDescription(entry),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: _Ui.text2),
                    ),
                  ],
                ),
              ),
              if (entry.isFolder && !selectionMode)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.chevron_right, color: _Ui.text3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrivePickerSelectionBar extends StatelessWidget {
  const _DrivePickerSelectionBar({
    required this.selectedCount,
    required this.currentFolderVideos,
    required this.collecting,
    required this.onAddSelected,
    required this.onClearSelection,
    required this.onAddCurrentFolder,
  });

  final int selectedCount;
  final int currentFolderVideos;
  final bool collecting;
  final VoidCallback? onAddSelected;
  final VoidCallback? onClearSelection;
  final VoidCallback onAddCurrentFolder;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: _Ui.card,
          border: Border(top: BorderSide(color: _Ui.border)),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: collecting ? null : onAddSelected,
              style: FilledButton.styleFrom(
                backgroundColor: _Ui.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(162, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.playlist_add_check),
              label: Text(selectedCount == 0 ? "선택 추가" : "$selectedCount개 추가"),
            ),
            IconButton.filledTonal(
              tooltip: "선택 해제",
              onPressed: collecting ? null : onClearSelection,
              icon: const Icon(Icons.clear),
            ),
            FilledButton.tonalIcon(
              onPressed: collecting ? null : onAddCurrentFolder,
              style: FilledButton.styleFrom(
                backgroundColor: _Ui.surface2,
                foregroundColor: _Ui.text2,
                elevation: 0,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text("폴더 전체 ($currentFolderVideos)"),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrivePickerImportOverlay extends StatelessWidget {
  const _DrivePickerImportOverlay({
    required this.collectingName,
    required this.currentScanFolder,
    required this.scannedFolderCount,
    required this.foundVideoCount,
  });

  final String collectingName;
  final String currentScanFolder;
  final int scannedFolderCount;
  final int foundVideoCount;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72)),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text("Importing $collectingName..."),
                    const SizedBox(height: 8),
                    Text(
                      currentScanFolder.isEmpty
                          ? "Searching videos in subfolders."
                          : "Current location: $currentScanFolder",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Scanned $scannedFolderCount folders - found $foundVideoCount videos",
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _drivePickerVideoDescription(DriveEntry entry) {
  final parts = <String>[];
  if (entry.size != null) {
    parts.add(_formatBytes(entry.size!));
  }
  if (entry.duration != null && entry.duration! > 0) {
    parts.add(_formatDuration(entry.duration!));
  }
  if (entry.width != null && entry.height != null) {
    parts.add('${entry.width}x${entry.height}');
  }
  if (entry.modifiedTime != null) {
    parts.add("Modified ${_formatDate(entry.modifiedTime!)}");
  }
  return parts.isEmpty ? "Video file" : parts.join(" - ");
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

String _formatDuration(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (duration.inHours > 0) {
    return '${duration.inHours}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

String _two(int value) => value.toString().padLeft(2, '0');
