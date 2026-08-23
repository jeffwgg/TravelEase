import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_notification_service.dart';

class StartupPermissionService {
  static const _requestedKey = 'startup_permissions_requested';

  static Future<void> requestOnFirstEntry() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_requestedKey) ?? false) return;
    try {
      await [
        Permission.camera,
        Permission.microphone,
        Permission.speech,
        Permission.locationWhenInUse,
      ].request();
      await AppNotificationService.instance.requestPermission();
    } finally {
      await preferences.setBool(_requestedKey, true);
    }
  }
}
