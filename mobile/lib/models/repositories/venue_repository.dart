import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../entities/venue_search_result.dart';
import '../entities/venue_service_area.dart';

/// A location match is normally a specific service area. [serviceArea] is
/// null only for an institution that has not configured any service areas.
class VenueLocationMatch {
  const VenueLocationMatch({required this.venue, this.serviceArea});

  final VenueSearchResult venue;
  final VenueServiceArea? serviceArea;
}

class VenueRepository {
  /// Radius used when an institution row has no stored match radius.
  static const defaultMatchRadiusMeters = 500.0;

  final SupabaseClient _client = SupabaseClientHelper.client;

  Future<List<VenueSearchResult>> search(String query) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final response = await SupabaseClientHelper.client.functions.invoke(
      'search-venues',
      body: {'query': term},
    );
    final rows =
        (response.data as Map<String, dynamic>)['venues'] as List<dynamic>? ??
        const [];
    return rows
        .map((row) => VenueSearchResult.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Participating institutions that carry location data, sorted by distance
  /// from the given position (FR-M2-02). Lets the traveller choose a venue
  /// after the app detects their location.
  Future<List<VenueSearchResult>> nearby({
    required double latitude,
    required double longitude,
    double radiusKm = 25,
    int limit = 8,
  }) async {
    final rows = await _institutionsWithLocation();
    final results = <VenueSearchResult>[];
    for (final row in rows) {
      final rowLatitude = (row['latitude'] as num?)?.toDouble();
      final rowLongitude = (row['longitude'] as num?)?.toDouble();
      if (rowLatitude == null || rowLongitude == null) continue;
      final distance = _distanceMeters(
        latitude,
        longitude,
        rowLatitude,
        rowLongitude,
      );
      if (distance > radiusKm * 1000) continue;
      results.add(
        VenueSearchResult(
          id: row['id'] as String,
          name: row['name'] as String? ?? 'Institution',
          branch: row['branch'] as String? ?? 'Participating venue',
          latitude: rowLatitude,
          longitude: rowLongitude,
          distanceMeters: distance,
        ),
      );
    }
    results.sort(
      (a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0),
    );
    return results.take(limit).toList();
  }

  /// Finds the service area covering the position. An institution-level
  /// fallback is used only when that institution has no active service areas.
  /// The closest match wins when coverage circles overlap.
  Future<VenueLocationMatch?> matchLocation({
    required double latitude,
    required double longitude,
  }) async {
    final serviceAreaMatch = await _matchServiceArea(
      latitude: latitude,
      longitude: longitude,
    );
    if (serviceAreaMatch != null) return serviceAreaMatch;

    final rows = await _institutionsWithLocation();
    final institutionIdsWithAreas =
        await _institutionIdsWithActiveServiceAreas();
    VenueSearchResult? nearest;
    var nearestDistance = double.infinity;
    for (final row in rows) {
      final institutionId = row['id'] as String;
      if (institutionIdsWithAreas.contains(institutionId)) continue;
      final rowLatitude = (row['latitude'] as num?)?.toDouble();
      final rowLongitude = (row['longitude'] as num?)?.toDouble();
      if (rowLatitude == null || rowLongitude == null) continue;
      final radius =
          (row['location_match_radius_m'] as num?)?.toDouble() ??
          defaultMatchRadiusMeters;
      final distance = _distanceMeters(
        latitude,
        longitude,
        rowLatitude,
        rowLongitude,
      );
      if (distance <= radius && distance < nearestDistance) {
        nearestDistance = distance;
        nearest = VenueSearchResult(
          id: institutionId,
          name: row['name'] as String? ?? 'Institution',
          branch: row['branch'] as String? ?? 'Participating venue',
          latitude: rowLatitude,
          longitude: rowLongitude,
          distanceMeters: distance,
        );
      }
    }
    return nearest == null ? null : VenueLocationMatch(venue: nearest);
  }

  /// Service areas a traveller can choose after selecting an institution.
  Future<List<VenueServiceArea>> getActiveServiceAreas(
    String institutionId,
  ) async {
    final response = await _client
        .from('service_areas')
        .select(
          'id, institution_id, name, address, latitude, longitude, radius_m',
        )
        .eq('institution_id', institutionId)
        .eq('active', true)
        .order('name');
    return (response as List<dynamic>)
        .map((row) => VenueServiceArea.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<VenueLocationMatch?> _matchServiceArea({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client
        .from('service_areas')
        .select(
          'id, institution_id, name, address, latitude, longitude, radius_m, '
          'institutions!inner(id, name, branch, active)',
        )
        .eq('active', true)
        .eq('institutions.active', true);

    VenueLocationMatch? nearest;
    var nearestDistance = double.infinity;
    for (final rawRow in response as List<dynamic>) {
      final row = rawRow as Map<String, dynamic>;
      final area = VenueServiceArea.fromJson(row);
      final distance = _distanceMeters(
        latitude,
        longitude,
        area.latitude,
        area.longitude,
      );
      if (distance > area.radiusMeters || distance >= nearestDistance) continue;
      final institution = row['institutions'] as Map<String, dynamic>?;
      if (institution == null) continue;
      nearestDistance = distance;
      nearest = VenueLocationMatch(
        venue: VenueSearchResult(
          id: institution['id'] as String,
          name: institution['name'] as String? ?? 'Institution',
          branch: institution['branch'] as String? ?? 'Participating venue',
          distanceMeters: distance,
        ),
        serviceArea: area,
      );
    }
    return nearest;
  }

  Future<Set<String>> _institutionIdsWithActiveServiceAreas() async {
    final response = await _client
        .from('service_areas')
        .select('institution_id')
        .eq('active', true);
    return (response as List<dynamic>)
        .map((row) => (row as Map<String, dynamic>)['institution_id'] as String)
        .toSet();
  }

  Future<List<Map<String, dynamic>>> _institutionsWithLocation() async {
    final response = await _client
        .from('institutions')
        .select(
          'id, name, branch, latitude, longitude, location_match_radius_m',
        )
        .eq('active', true)
        .not('latitude', 'is', null)
        .not('longitude', 'is', null);
    return (response as List<dynamic>).cast<Map<String, dynamic>>();
  }

  double _distanceMeters(
    double latitude1,
    double longitude1,
    double latitude2,
    double longitude2,
  ) {
    const earthRadius = 6371000.0;
    final phi1 = latitude1 * math.pi / 180;
    final phi2 = latitude2 * math.pi / 180;
    final deltaPhi = (latitude2 - latitude1) * math.pi / 180;
    final deltaLambda = (longitude2 - longitude1) * math.pi / 180;
    final a =
        math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(deltaLambda / 2) *
            math.sin(deltaLambda / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
