import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:installm/core/utils/logger.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  /// Monochrome small icon for Android notifications, also set per notice so a
  /// channel created earlier cannot pin the old one.
  static const String _androidStatusIcon = '@drawable/ic_stat_installm';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  bool _notificationsAvailable = true;

  /// True when the plugin itself could not be set up. Kept apart from
  /// [_notificationsAvailable], which is about what the user allowed: a
  /// refused permission must not stop a later request from being made, and a
  /// failed setup must not present a prompt that cannot be answered.
  bool _initializationFailed = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // A status icon, not the launcher icon: Android paints the small icon from
    // its alpha channel alone, and the full-colour mipmap turns into a blank
    // circle in the shade. See res/drawable/ic_stat_installm.xml.
    const androidSettings = AndroidInitializationSettings(_androidStatusIcon);
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open InstaLLM',
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'InstaLLM',
      appUserModelId: 'com.prady.installm.desktop',
      guid: '2f655744-b4fd-4d2a-9b61-d0f5f53d0cf4',
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    try {
      // The returned value is deliberately not treated as availability. On iOS
      // and macOS the plugin reports the *permission* state here, and this app
      // defers that question (the request*Permission flags above are false), so
      // the value is false until the user is asked — reading it as "not
      // available" used to skip the request and every notice after it.
      await _plugin.initialize(settings: settings);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'LocalNotificationService initialization disabled notifications: '
        '$error\n$stackTrace',
      );
      _initializationFailed = true;
      _notificationsAvailable = false;
    }

    _isInitialized = true;
  }

  /// Asks the platform for permission to show notifications.
  ///
  /// Only a setup failure cancels the question, so a permission the user
  /// refused earlier can still be asked for again after they change the setting
  /// in the system. What the platform answers decides whether notices are built
  /// at all: a notification the system would drop is not worth the work.
  Future<void> requestPermissions() async {
    await initialize();
    if (_initializationFailed) return;

    if (Platform.isAndroid) {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      _recordPermissionAnswer(
        await androidImpl?.requestNotificationsPermission(),
      );
      return;
    }

    if (Platform.isIOS) {
      final iosImpl = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      _recordPermissionAnswer(
        await iosImpl?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ),
      );
    }

    if (Platform.isMacOS) {
      final macOsImpl = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      _recordPermissionAnswer(
        await macOsImpl?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ),
      );
    }
  }

  /// Stores what the platform answered about notification permission.
  ///
  /// A null answer means the platform did not report one (older Android
  /// releases ask at install time), so the last known state is kept.
  void _recordPermissionAnswer(bool? granted) {
    if (granted == null) return;
    _notificationsAvailable = granted;
    if (granted) return;
    AppLogger.warning(
      'LocalNotificationService: notifications are not allowed here, so '
      'download notices are skipped. Allow them in the system notification '
      'settings for InstaLLM to get them.',
    );
  }

  Future<void> showModelDownloadComplete(String modelName) async {
    await initialize();
    if (!_notificationsAvailable) return;

    const androidDetails = AndroidNotificationDetails(
      'model_downloads',
      'Model downloads',
      channelDescription: 'Notifies when model downloads complete',
      icon: _androidStatusIcon,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );
    const linuxDetails = LinuxNotificationDetails(
      category: LinuxNotificationCategory.transferComplete,
      urgency: LinuxNotificationUrgency.normal,
      defaultActionName: 'Open InstaLLM',
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
      linux: linuxDetails,
    );

    try {
      await _plugin.show(
        id: modelName.hashCode & 0x7fffffff,
        title: 'Model downloaded',
        body: '$modelName is ready to use.',
        notificationDetails: details,
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'LocalNotificationService failed to show notification: '
        '$error\n$stackTrace',
      );
    }
  }

  /// Tells the user a supervised agent run ended or needs them.
  ///
  /// A run started on purpose to continue while the user is elsewhere, so the
  /// notice is the point of it: without one, "background" would only mean
  /// "hidden". Both kinds share one channel because they are the same story —
  /// work the user left this device to finish.
  Future<void> showBackgroundRun({
    required String title,
    required String body,
  }) async {
    await initialize();
    if (!_notificationsAvailable) return;

    const androidDetails = AndroidNotificationDetails(
      'background_runs',
      'Agent runs',
      channelDescription: 'Notifies when an agent run finishes or needs you',
      icon: _androidStatusIcon,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );
    const linuxDetails = LinuxNotificationDetails(
      category: LinuxNotificationCategory.transferComplete,
      urgency: LinuxNotificationUrgency.normal,
      defaultActionName: 'Open InstaLLM',
    );
    const windowsDetails = WindowsNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails,
      linux: linuxDetails,
      windows: windowsDetails,
    );

    try {
      await _plugin.show(
        id: title.hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (error, stackTrace) {
      AppLogger.warning(
        'LocalNotificationService failed to show notification: '
        '$error\n$stackTrace',
      );
    }
  }
}
