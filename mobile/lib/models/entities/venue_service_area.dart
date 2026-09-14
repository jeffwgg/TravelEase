/// A geographic service area owned by a participating institution.
///
/// This is the precise location used for venue sessions and official
/// announcement delivery. An institution without service areas can still
/// have an institution-level session.
class VenueServiceArea {
  final String id;
  final String institutionId;
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  const VenueServiceArea({
    required this.id,
    required this.institutionId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.address,
  });

  factory VenueServiceArea.fromJson(Map<String, dynamic> json) {
    return VenueServiceArea(
      id: json['id'] as String,
      institutionId: json['institution_id'] as String,
      name: json['name'] as String? ?? 'Service area',
      address: json['address'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['radius_m'] as num).toDouble(),
    );
  }
}
