import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../../core/theme.dart';

class LocationPickerView extends StatefulWidget {
  const LocationPickerView({super.key});

  @override
  State<LocationPickerView> createState() => _LocationPickerViewState();
}

class _LocationPickerViewState extends State<LocationPickerView> {
  GoogleMapController? _mapController;

  // Default center: Kuala Lumpur
  LatLng _selectedLocation = const LatLng(3.1390, 101.6869);
  String _placeName = '';
  bool _isGeocoding = false;
  bool _isLocating = false;
  bool _hasSelection = false;

  // Retrieve Google Maps API Key from environment variables
  String get _googleApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  @override
  void initState() {
    super.initState();
    _tryGetCurrentLocation();
  }

  Future<void> _tryGetCurrentLocation() async {
    setState(() => _isLocating = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _isLocating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      setState(() {
        _selectedLocation = LatLng(position.latitude, position.longitude);
        _hasSelection = true;
        _isLocating = false;
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _selectedLocation, zoom: 16.0),
        ),
      );
      _reverseGeocode(_selectedLocation);
    } catch (e) {
      setState(() => _isLocating = false);
    }
  }

  Future<void> _reverseGeocode(LatLng position) async {
    setState(() => _isGeocoding = true);

    try {
      if (_googleApiKey == 'YOUR_GOOGLE_MAPS_API_KEY_HERE') {
        // Fallback to nominatim if no Google key is provided to prevent total failure
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json&addressdetails=1',
        );
        final response = await http.get(url, headers: {'User-Agent': 'TravelEase/1.0'});

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final displayName = data['display_name'] as String? ?? '';
          final address = data['address'] as Map<String, dynamic>?;
          String shortName = '';
          if (address != null) {
            shortName = address['tourism'] ??
                address['building'] ??
                address['amenity'] ??
                address['road'] ??
                address['suburb'] ??
                address['city'] ??
                displayName;
            final city = address['city'] ?? address['town'] ?? address['village'];
            if (city != null && shortName != city) {
              shortName = '$shortName, $city';
            }
          } else {
            shortName = displayName;
          }
          setState(() {
            _placeName = shortName;
            _isGeocoding = false;
          });
          return;
        }
      } else {
        // Use Google Maps Geocoding API
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$_googleApiKey',
        );

        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status'] == 'OK' && data['results'].isNotEmpty) {
            final result = data['results'][0];
            // Try to find a concise name (e.g. point of interest or route)
            String shortName = result['formatted_address'];
            for (var component in result['address_components']) {
              final types = List<String>.from(component['types']);
              if (types.contains('point_of_interest') || types.contains('establishment')) {
                shortName = component['long_name'];
                break;
              }
            }
            setState(() {
              _placeName = shortName;
              _isGeocoding = false;
            });
            return;
          }
        }
      }
      
      // Fallback
      setState(() {
        _placeName = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        _isGeocoding = false;
      });
    } catch (e) {
      setState(() {
        _placeName = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        _isGeocoding = false;
      });
    }
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _selectedLocation = point;
      _hasSelection = true;
    });
    _reverseGeocode(point);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Location'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selectedLocation,
              zoom: 14.0,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onTap: _onMapTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _hasSelection
                ? {
                    Marker(
                      markerId: const MarkerId('selected'),
                      position: _selectedLocation,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                    ),
                  }
                : {},
          ),

          // Locate me button
          Positioned(
            right: 16,
            bottom: 180,
            child: FloatingActionButton.small(
              heroTag: 'locate_me',
              backgroundColor: AppColors.surface,
              onPressed: _isLocating ? null : _tryGetCurrentLocation,
              child: _isLocating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, color: AppColors.primary),
            ),
          ),

          // Bottom card with location info + confirm
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  Text(
                    'Selected Location',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),

                  if (_isGeocoding)
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text('Finding place name...',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    )
                  else if (_hasSelection && _placeName.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _placeName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Tap on the map to select a location',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted,
                          ),
                    ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _hasSelection && !_isGeocoding
                          ? () {
                              Navigator.pop(context, {
                                'name': _placeName,
                                'lat': _selectedLocation.latitude,
                                'lng': _selectedLocation.longitude,
                              });
                            }
                          : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm Location'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Instruction overlay when no selection
          if (!_hasSelection && !_isLocating)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.touch_app, size: 20, color: AppColors.primary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tap anywhere on the map to select your location',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
