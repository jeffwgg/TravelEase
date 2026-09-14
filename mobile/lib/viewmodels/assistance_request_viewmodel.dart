import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../models/repositories/assistance_repository.dart';
import '../services/live_location_service.dart';

class AssistanceRequestViewModel extends ChangeNotifier {
  final AssistanceRepository _repository = AssistanceRepository();
  bool _isDisposed = false;

  // Form state
  String? selectedCategory;
  String contactMethod = 'chat';
  int urgencyLevel = 1;
  bool shareLocation = true;
  bool shareAnalytics = false;
  String venueName = '';
  String locationZone = '';
  double? currentLat;
  double? currentLng;
  bool isFetchingLocation = false;
  final TextEditingController descriptionController = TextEditingController();

  String get _googleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  // Submission state
  bool isSubmitting = false;
  String? errorMessage;
  Map<String, dynamic>? submittedRequest;

  void setCategory(String? value) {
    selectedCategory = value;
    notifyListeners();
  }

  void setContactMethod(String value) {
    contactMethod = value;
    notifyListeners();
  }

  void setUrgencyLevel(int value) {
    urgencyLevel = value;
    notifyListeners();
  }

  void setShareLocation(bool value) {
    shareLocation = value;
    notifyListeners();
  }

  void setShareAnalytics(bool value) {
    shareAnalytics = value;
    notifyListeners();
  }

  void setVenue(String name, {String zone = ''}) {
    venueName = name;
    locationZone = zone;
    notifyListeners();
  }

  String get urgencyLabel {
    switch (urgencyLevel) {
      case 0:
        return 'low';
      case 2:
        return 'high';
      default:
        return 'medium';
    }
  }

  String _generateRequestCode() {
    final random = Random();
    final code = 1000 + random.nextInt(9000);
    return 'REQ-$code';
  }

  Future<void> fetchCurrentLocation() async {
    isFetchingLocation = true;
    notifyListeners();

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        isFetchingLocation = false;
        notifyListeners();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      currentLat = position.latitude;
      currentLng = position.longitude;

      final resolved = await _reverseGeocode(position.latitude, position.longitude);
      venueName = resolved;
      locationZone = 'Current Location';
    } catch (e) {
      // Ignore errors and let user pick manually
    }

    isFetchingLocation = false;
    notifyListeners();
  }

  /// Tries Google Geocoding first, then Nominatim (OSM) as fallback.
  /// Returns a human-readable place name, never raw coordinates if avoidable.
  Future<String> _reverseGeocode(double lat, double lng) async {
    // ── 1. Try Google Geocoding API ───────────────────────────────────────────
    if (_googleApiKey.isNotEmpty &&
        _googleApiKey != 'YOUR_GOOGLE_MAPS_API_KEY_HERE') {
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_googleApiKey',
        );
        final response = await http.get(url).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK' && (data['results'] as List).isNotEmpty) {
            final result = data['results'][0];
            String shortName = result['formatted_address'] as String;
            for (var component in result['address_components']) {
              final types = List<String>.from(component['types'] as List);
              if (types.contains('point_of_interest') ||
                  types.contains('establishment')) {
                shortName = component['long_name'] as String;
                break;
              }
            }
            return shortName;
          }
        }
      } catch (_) {
        // Fall through to Nominatim
      }
    }

    // ── 2. Fallback: OpenStreetMap Nominatim ──────────────────────────────────
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'TravelEase/1.0'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final displayName = data['display_name'] as String? ?? '';
        final address = data['address'] as Map<String, dynamic>?;

        if (address != null) {
          String shortName = (address['tourism'] ??
              address['building'] ??
              address['amenity'] ??
              address['road'] ??
              address['suburb'] ??
              address['city'] ??
              displayName) as String;
          final city =
              (address['city'] ?? address['town'] ?? address['village'])
                  as String?;
          if (city != null && shortName != city) {
            shortName = '$shortName, $city';
          }
          return shortName;
        } else if (displayName.isNotEmpty) {
          return displayName;
        }
      }
    } catch (_) {
      // Fall through to raw coordinates
    }

    // ── 3. Last resort: raw coordinates ──────────────────────────────────────
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }

  Future<bool> submitRequest() async {
    if (selectedCategory == null) {
      errorMessage = 'Please select a help category';
      notifyListeners();
      return false;
    }

    if (venueName.isEmpty) {
      errorMessage = 'Please select or enter a location';
      notifyListeners();
      return false;
    }

    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      if (shareLocation && (currentLat == null || currentLng == null)) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 5),
            ),
          );
          currentLat = pos.latitude;
          currentLng = pos.longitude;
        } catch (_) {}
      }

      final result = await _repository.createAssistanceRequest(
        requestCode: _generateRequestCode(),
        preferredCommunication: contactMethod,
        category: selectedCategory!,
        venueName: venueName,
        locationZone: locationZone.isNotEmpty ? locationZone : venueName,
        description: descriptionController.text,
        urgency: urgencyLabel,
        shareLocation: shareLocation,
        analyticsConsent: shareAnalytics,
        latitude: shareLocation ? currentLat : null,
        longitude: shareLocation ? currentLng : null,
      );

      isSubmitting = false;

      if (result != null) {
        submittedRequest = result;
        if (shareLocation && result['id'] != null) {
          LiveLocationService.instance.start(
            sessionId: result['id'].toString(),
            sessionType: 'assistance',
          );
        }
        notifyListeners();
        return true;
      } else {
        errorMessage = 'Failed to submit request. Please try again.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      isSubmitting = false;
      errorMessage = 'Network error: $e';
      notifyListeners();
      return false;
    }
  }

  void reset() {
    selectedCategory = null;
    contactMethod = 'chat';
    urgencyLevel = 1;
    shareLocation = true;
    shareAnalytics = false;
    currentLat = null;
    currentLng = null;
    descriptionController.clear();
    errorMessage = null;
    submittedRequest = null;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    descriptionController.dispose();
    super.dispose();
  }
}
