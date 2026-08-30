class VenueSearchResult {
  final String id;
  final String name;
  final String branch;

  /// Coordinates of the institution venue, when the row carries location data.
  final double? latitude;
  final double? longitude;

  /// Distance in metres from the traveller's detected location, filled by the
  /// nearby-institution lookup.
  final double? distanceMeters;

  const VenueSearchResult({
    required this.id,
    required this.name,
    required this.branch,
    this.latitude,
    this.longitude,
    this.distanceMeters,
  });

  factory VenueSearchResult.fromJson(Map<String, dynamic> json) =>
      VenueSearchResult(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Institution',
        branch: json['branch'] as String? ?? 'Participating venue',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      );

  String get distanceLabel {
    final meters = distanceMeters;
    if (meters == null) return '';
    if (meters < 1000) return '${meters.round()} m';
    final kilometres = meters / 1000;
    return '${kilometres.toStringAsFixed(kilometres < 10 ? 1 : 0)} km';
  }
}
