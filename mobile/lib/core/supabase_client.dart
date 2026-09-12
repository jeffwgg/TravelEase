import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseClientHelper {
  static const String supabaseUrl = 'https://pewpzfxubdgquvcahemh.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBld3B6Znh1YmRncXV2Y2FoZW1oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU3NDY2NTgsImV4cCI6MjEwMTMyMjY1OH0.yyxMdTFf7cIUy5oA-e_4vRzNsR_1WXpDTf2QiKbLtiY';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUri: true,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
