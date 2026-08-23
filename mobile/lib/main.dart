import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';
import 'services/app_notification_service.dart';
import 'services/environment_sound_monitoring_service.dart';
import 'services/queue_notification_service.dart';
import 'services/startup_permission_service.dart';

import 'services/webrtc_service.dart';
import 'views/widgets/incoming_call_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await SupabaseClientHelper.initialize();
  await AppNotificationService.instance.initialize();
  await QueueNotificationService.instance.initialize();
  runApp(const TravelEaseApp());
}

class TravelEaseApp extends StatefulWidget {
  const TravelEaseApp({super.key});

  @override
  State<TravelEaseApp> createState() => _TravelEaseAppState();
}

class _TravelEaseAppState extends State<TravelEaseApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await StartupPermissionService.requestOnFirstEntry();
      await EnvironmentSoundMonitoringService.instance.initialize();
    WebRTCService.instance.init().then((_) {
      WebRTCService.instance.subscribeToGlobalSignaling();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TravelEase',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
      builder: (context, child) => IncomingCallOverlay(child: child ?? const SizedBox.shrink()),
    );
  }
}
