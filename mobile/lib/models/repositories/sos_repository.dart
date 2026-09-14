import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

enum InstitutionSosResult { requestSent, noMatch }

class InstitutionSosResponse {
  const InstitutionSosResponse({
    required this.result,
    this.sosRequestId,
  });

  final InstitutionSosResult result;
  final String? sosRequestId;
}

class SosRepository {
  SosRepository({SupabaseClient? client})
    : _client = client ?? SupabaseClientHelper.client;

  final SupabaseClient _client;

  Future<InstitutionSosResponse> matchServiceAreaAndCreateRequest({
    required double latitude,
    required double longitude,
    required DateTime triggeredAt,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('No authenticated traveller is available.');
    }

    final rows = await _client
        .from('service_areas')
        .select('id, institution_id, latitude, longitude, radius_m')
        .eq('active', true);

    _ServiceAreaMatch? closestMatch;
    for (final row in rows) {
      final area = _ServiceArea.fromJson(row);
      final distance = distanceInMeters(
        latitude,
        longitude,
        area.latitude,
        area.longitude,
      );
      if (distance <= area.radiusM &&
          (closestMatch == null || distance < closestMatch.distanceM)) {
        closestMatch = _ServiceAreaMatch(area: area, distanceM: distance);
      }
    }

    if (closestMatch == null) {
      return const InstitutionSosResponse(result: InstitutionSosResult.noMatch);
    }

    final inserted = await _client.from('sos_requests').insert({
      'traveller_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'service_area_id': closestMatch.area.id,
      'institution_id': closestMatch.area.institutionId,
      'triggered_at': triggeredAt.toUtc().toIso8601String(),
      'status': 'sent',
    }).select('id').single();

    return InstitutionSosResponse(
      result: InstitutionSosResult.requestSent,
      sosRequestId: inserted['id']?.toString(),
    );
  }

  static double distanceInMeters(
    double firstLatitude,
    double firstLongitude,
    double secondLatitude,
    double secondLongitude,
  ) {
    const earthRadiusM = 6371000.0;
    final latitudeDelta = _toRadians(secondLatitude - firstLatitude);
    final longitudeDelta = _toRadians(secondLongitude - firstLongitude);
    final firstLatitudeRadians = _toRadians(firstLatitude);
    final secondLatitudeRadians = _toRadians(secondLatitude);
    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(firstLatitudeRadians) *
            math.cos(secondLatitudeRadians) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    final safeHaversine = haversine.clamp(0.0, 1.0).toDouble();
    final angularDistance = 2 * math.atan2(
      math.sqrt(safeHaversine),
      math.sqrt(1 - safeHaversine),
    );
    return earthRadiusM * angularDistance;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}

class _ServiceArea {
  const _ServiceArea({
    required this.id,
    required this.institutionId,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
  });

  final String id;
  final String institutionId;
  final double latitude;
  final double longitude;
  final double radiusM;

  factory _ServiceArea.fromJson(Map<String, dynamic> json) {
    return _ServiceArea(
      id: json['id'] as String,
      institutionId: json['institution_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusM: (json['radius_m'] as num).toDouble(),
    );
  }
}

class _ServiceAreaMatch {
  const _ServiceAreaMatch({required this.area, required this.distanceM});

  final _ServiceArea area;
  final double distanceM;
}
