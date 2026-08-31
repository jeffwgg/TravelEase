import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';
import 'services/announcement_notification_service.dart';
import 'services/app_notification_service.dart';
import 'services/background_notification_service.dart';
import 'services/environment_sound_monitoring_service.dart';
import 'services/public_announcement_capture_service.dart';
import 'services/queue_notification_service.dart';
import 'services/startup_permission_service.dart';
import 'services/venue_session_service.dart';
import 'services/auth_deep_link_service.dart';
import 'viewmodels/profile_viewmodel.dart';

import 'services/webrtc_service.dart';
import 'views/widgets/incoming_call_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await SupabaseClientHelper.initialize();
  await AppNotificationService.instance.initialize(
    onNotificationTap: _handleNotificationTap,
  );
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
  await AppNotificationService.instance.initialize();
  await QueueNotificationService.instance.initialize();
  await VenueSessionService.instance.restore();
  // Venue alert services: notifications keep flowing while the app is in the
  // background or its task is swiped away. Enabled by default for now.
  AnnouncementNotificationService.instance.start();
  PublicAnnouncementCaptureService.instance.start();
  runApp(const TravelEaseApp());
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
      final launchRoute = AppNotificationService.instance.consumeLaunchPayload();
      if (launchRoute != null) _handleNotificationTap(launchRoute);
      await StartupPermissionService.requestOnFirstEntry();
      await EnvironmentSoundMonitoringService.instance.initialize();
      // The foreground service must start once the activity is actually in
      // the foreground: Android 12+ rejects startForegroundService() issued
      // from main() during cold start.
      await AppNotificationService.instance.requestPermission();
      await startBackgroundNotificationService();
    });
    WebRTCService.instance.init().then((_) async {
      await WebRTCService.instance.init();
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
