import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../models/repositories/assistance_repository.dart';

class AssistanceRequestViewModel extends ChangeNotifier {
  final AssistanceRepository _repository = AssistanceRepository();
  bool _isDisposed = false;

  // Form state
  String? selectedCategory;
  String contactMethod = 'chat';
  int urgencyLevel = 1;
  bool shareLocation = true;
  String venueName = '';
  String locationZone = '';
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

      // Reverse geocode
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$_googleApiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final result = data['results'][0];
          String shortName = result['formatted_address'];
          for (var component in result['address_components']) {
            final types = List<String>.from(component['types']);
            if (types.contains('point_of_interest') || types.contains('establishment')) {
              shortName = component['long_name'];
              break;
            }
          }
          
          venueName = shortName;
          // Set a default zone if we want, or just leave empty
          locationZone = 'Current Location';
        } else {
          venueName = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        }
      } else {
        venueName = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      }
    } catch (e) {
      // Ignore errors and let user pick manually
    }

    isFetchingLocation = false;
    notifyListeners();
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
      final result = await _repository.createAssistanceRequest(
        requestCode: _generateRequestCode(),
        travelerName: 'Jeff Wong',
        preferredCommunication: contactMethod,
        category: selectedCategory!,
        venueName: venueName,
        locationZone: locationZone.isNotEmpty ? locationZone : venueName,
        description: descriptionController.text,
        urgency: urgencyLabel,
      );

      isSubmitting = false;

      if (result != null) {
        submittedRequest = result;
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
