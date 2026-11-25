import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:installm/core/utils/logger.dart';

/// Where a Play update stands, reduced to what the prompt needs to show.
enum PlayUpdateStage {
  /// Nothing to say: no update waiting, or this build did not come from Play.
  none,

  /// A newer build is on Play and the user should be told.
  available,

  /// A background download was started and is still running.
  downloading,

  /// Downloaded and waiting for a restart to install.
  ready,
}

class PlayUpdateCheck {
  const PlayUpdateCheck(
    this.stage, {
    this.availableVersionCode,
    this.canUpdateInApp = false,
  });

  final PlayUpdateStage stage;

  /// Play's version code for the newer build, or null when it is unknown.
  final int? availableVersionCode;

  /// True when Play lets the app download this update itself. An immediate-only
  /// update, or a build Play did not install, sends the user to the listing.
  final bool canUpdateInApp;

  bool get hasUpdate => stage != PlayUpdateStage.none;
}

/// Play's own in-app update API, and nothing else.
///
/// The check, the download and the install all run inside the Play Store app:
/// the app asks for no network access of its own and sends nothing anywhere,
/// which keeps the "no cloud" promise intact. Off Android, and on builds Play
/// did not install, every call here is a quiet no-op; Play answers
/// `ERROR_API_NOT_AVAILABLE` and that is reported as "nothing to do".
class PlayUpdateService {
  const PlayUpdateService();

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<PlayUpdateCheck> check() async {
    if (!isSupported) return const PlayUpdateCheck(PlayUpdateStage.none);
    try {
      final info = await InAppUpdate.checkForUpdate();
      final stage = switch (info.updateAvailability) {
        UpdateAvailability.updateAvailable => PlayUpdateStage.available,
        // Play reports download state under this availability value.
        UpdateAvailability.developerTriggeredUpdateInProgress =>
          info.installStatus == InstallStatus.downloaded
              ? PlayUpdateStage.ready
              : PlayUpdateStage.downloading,
        UpdateAvailability.unknown ||
        UpdateAvailability.updateNotAvailable => PlayUpdateStage.none,
      };
      return PlayUpdateCheck(
        stage,
        availableVersionCode: info.availableVersionCode,
        canUpdateInApp: info.flexibleUpdateAllowed,
      );
    } on PlatformException catch (error) {
      // A sideloaded debug APK, a device without Play, or an update Play only
      // allows immediately. None of them deserves an error on screen.
      AppLogger.debug('Play update check unavailable: ${error.code}');
      return const PlayUpdateCheck(PlayUpdateStage.none);
    } catch (error) {
      AppLogger.debug('Play update check failed: $error');
      return const PlayUpdateCheck(PlayUpdateStage.none);
    }
  }

  /// Starts Play's background download. False means the user should be sent to
  /// the listing instead, because this build cannot update itself.
  Future<bool> startBackgroundDownload() async {
    if (!isSupported) return false;
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      return result == AppUpdateResult.success;
    } on PlatformException catch (error) {
      AppLogger.debug('Play flexible update did not start: ${error.code}');
      return false;
    } catch (error) {
      AppLogger.debug('Play flexible update did not start: $error');
      return false;
    }
  }

  /// Hands the downloaded update to Play, which restarts the app.
  Future<bool> installDownloaded() async {
    if (!isSupported) return false;
    try {
      await InAppUpdate.completeFlexibleUpdate();
      return true;
    } on PlatformException catch (error) {
      AppLogger.debug('Play update could not install: ${error.code}');
      return false;
    } catch (error) {
      AppLogger.debug('Play update could not install: $error');
      return false;
    }
  }

  /// Play reports install state changes only, with no byte count, so this
  /// carries stages rather than a percentage. A failed or cancelled download
  /// resolves to [PlayUpdateStage.available] so the prompt can offer it again.
  Stream<PlayUpdateStage> get installStages async* {
    if (!isSupported) return;
    yield* InAppUpdate.installUpdateListener.map(
      (status) => switch (status) {
        InstallStatus.downloaded ||
        InstallStatus.installed => PlayUpdateStage.ready,
        InstallStatus.downloading ||
        InstallStatus.pending ||
        InstallStatus.installing => PlayUpdateStage.downloading,
        InstallStatus.failed ||
        InstallStatus.canceled ||
        InstallStatus.unknown => PlayUpdateStage.available,
      },
    );
  }
}
