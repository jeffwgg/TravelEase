import 'dart:async';

import 'package:geolocator/geolocator.dart';

class CurrentLocationResult {
  const CurrentLocationResult.retrieved({
    required this.latitude,
    required this.longitude,
  }) : unavailableReason = null;

  const CurrentLocationResult.unavailable(this.unavailableReason)
    : latitude = null,
      longitude = null;

  final double? latitude;
  final double? longitude;
  final String? unavailableReason;

  bool get isRetrieved => latitude != null && longitude != null;
}

class CurrentLocationService {
  const CurrentLocationService();

  Future<CurrentLocationResult> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const CurrentLocationResult.unavailable(
          'Location services are disabled.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const CurrentLocationResult.unavailable(
          'Location permission was denied.',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        return const CurrentLocationResult.unavailable(
          'Location permission is disabled in device settings.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return CurrentLocationResult.retrieved(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on TimeoutException {
      return const CurrentLocationResult.unavailable(
        'Location request timed out.',
      );
    } on LocationServiceDisabledException {
      return const CurrentLocationResult.unavailable(
        'Location services are disabled.',
      );
    } catch (_) {
      return const CurrentLocationResult.unavailable(
        'Current location could not be retrieved.',
      );
    }
  }
}
