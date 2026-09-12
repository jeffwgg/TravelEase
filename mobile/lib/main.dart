import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';
import 'models/repositories/accessibility_preferences_repository.dart';
import 'services/announcement_notification_service.dart';
import 'services/app_notification_service.dart';
import 'services/background_notification_service.dart';
import 'services/chat_notification_service.dart';
import 'services/environment_sound_monitoring_service.dart';
import 'services/notification_settings.dart';
import 'services/queue_notification_service.dart';
import 'services/startup_permission_service.dart';
import 'services/asl_tflite_service.dart';
import 'services/venue_session_service.dart';
import 'services/public_announcement_capture_service.dart';
import 'services/auth_deep_link_service.dart';
import 'viewmodels/profile_viewmodel.dart';

import 'services/webrtc_service.dart';
import 'views/widgets/incoming_call_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await SupabaseClientHelper.initialize();
  await _loadNotificationPreferences();
  await AppNotificationService.instance.initialize(
    onNotificationTap: _handleNotificationTap,
    router: appRouter,
  );
  await QueueNotificationService.instance.initialize();
  await AslTfliteService().initialize();
  ChatNotificationService.instance.initialize();
  await AuthDeepLinkService.instance.initialize(
    onAuthSession: (isPasswordRecovery) async {
      if (isPasswordRecovery) {
        appRouter.go('/reset-password');
        return;
      }
      final viewModel = ProfileViewModel();
      final destination = await viewModel.authenticatedDestination();
      viewModel.dispose();
      appRouter.go(destination);
    },
  );
  await VenueSessionService.instance.restore();
  // Venue alert services: notifications keep flowing while the app is in the
  // background or its task is swiped away. Enabled by default for now.
  AnnouncementNotificationService.instance.start();
  PublicAnnouncementCaptureService.instance.start();
  runApp(const TravelEaseApp());
}

/// Loads the signed-in traveller's saved preferences before notification
/// channels and background polling start. This prevents their previous
/// default-on values from overriding the accessibility profile at launch.
Future<void> _loadNotificationPreferences() async {
  try {
    final data = await AccessibilityPreferencesRepository()
        .getCurrentUserPreferences();
    if (data == null) return;
    final alertPush = data['alert_notification_enabled'] as bool? ?? true;
    final generalPush = data['general_notification_enabled'] as bool? ?? true;
    await NotificationSettings.store(
      alertPush: alertPush,
      alertVibration:
          alertPush && (data['alert_vibration_enabled'] as bool? ?? true),
      alertFlash: alertPush && (data['alert_flash_enabled'] as bool? ?? true),
      generalPush: generalPush,
      generalVibration:
          generalPush && (data['general_vibration_enabled'] as bool? ?? true),
      generalFlash:
          generalPush && (data['general_flash_enabled'] as bool? ?? true),
    );
  } catch (_) {
    // Existing local values/defaults keep startup available while offline.
  }
}

void _handleNotificationTap(String route) {
  final context = appRouter.routerDelegate.navigatorKey.currentContext;
  if (context != null) {
    context.push(route);
  }
}

class TravelEaseApp extends StatefulWidget {
  const TravelEaseApp({super.key});

  @override
  State<TravelEaseApp> createState() => _TravelEaseAppState();
}

class _TravelEaseAppState extends State<TravelEaseApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Deep link from a notification tap that launched the app cold.
      final launchRoute = AppNotificationService.instance
          .consumeLaunchPayload();
      if (launchRoute != null) _handleNotificationTap(launchRoute);
      await StartupPermissionService.requestOnFirstEntry();
      await EnvironmentSoundMonitoringService.instance.initialize();
      // The foreground service must start once the activity is actually in
      // the foreground: Android 12+ rejects startForegroundService() issued
      // from main() during cold start.
      await AppNotificationService.instance.requestPermission();
      await startBackgroundNotificationService();
    });
    WebRTCService.instance.init().then((_) {
      WebRTCService.instance.subscribeToGlobalSignaling();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Devices such as MIUI reject the service start while the app launches
    // without a visible foreground (e.g. screen was off) — retry whenever the
    // traveller actually opens the app.
    if (state == AppLifecycleState.resumed) {
      startBackgroundNotificationService();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TravelEase',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      builder: (context, child) {
        return IncomingCallOverlay(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
