import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../entities/venue_search_result.dart';

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

  /// The institution whose stored coordinates cover the given position, or
  /// null when the traveller is not at a participating venue. Nearest match
  /// wins when institutions overlap.
  Future<VenueSearchResult?> matchLocation({
    required double latitude,
    required double longitude,
  }) async {
    final rows = await _institutionsWithLocation();
    VenueSearchResult? nearest;
    var nearestDistance = double.infinity;
    for (final row in rows) {
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
          id: row['id'] as String,
          name: row['name'] as String? ?? 'Institution',
          branch: row['branch'] as String? ?? 'Participating venue',
          latitude: rowLatitude,
          longitude: rowLongitude,
          distanceMeters: distance,
        );
      }
    }
    return nearest;
  }

  Future<List<Map<String, dynamic>>> _institutionsWithLocation() async {
    final response = await _client
        .from('institutions')
        .select('id, name, branch, latitude, longitude, location_match_radius_m')
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
