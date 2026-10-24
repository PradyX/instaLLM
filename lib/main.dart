import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installm/app.dart';
import 'package:installm/core/services/local_notification_service.dart';
import 'package:installm/core/utils/logger.dart';
import 'package:installm/i18n/strings.g.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installm/core/data/legacy_store_cleanup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  // Enable Edge-to-Edge UI for Android 15+
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ),
  );

  // Initialize global Flutter/Dart error handlers.
  AppLogger.initErrorHandlers();

  // Initialize i18n
  LocaleSettings.useDeviceLocale();

  await LocalNotificationService.instance.initialize();
  await LocalNotificationService.instance.requestPermissions();

  // Removes store files of deleted features (workflows, activity feed).
  await LegacyStoreCleanup.run();

  AppLogger.info('App started successfully');
  runApp(
    TranslationProvider(
      child: ProviderScope(retry: _noProviderRetry, child: const MyApp()),
    ),
  );
}

/// Riverpod 3 retries a failed provider ten times with backoff by default,
/// which would keep a broken store behind a spinner for half a minute before
/// the error the UI reports appears. The failures here are file and network
/// errors the user needs to see, so retrying stays off.
Duration? _noProviderRetry(int retryCount, Object error) => null;
