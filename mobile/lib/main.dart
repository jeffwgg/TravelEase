import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseClientHelper.initialize();
  runApp(const TravelEaseApp());
}

class TravelEaseApp extends StatelessWidget {
  const TravelEaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TravelEase',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: appRouter,
    );
  }
}

