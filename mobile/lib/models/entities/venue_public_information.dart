/// Public institution details shown to travellers after they identify a venue.
/// These values are maintained by the institution profile on the web portal.
class VenuePublicInformation {
  final String id;
  final String name;
  final String branch;
  final String? hotline;
  final String? address;
  final double? latitude;
  final double? longitude;
  final double radiusMeters;

  const VenuePublicInformation({
    required this.id,
    required this.name,
    required this.branch,
    required this.radiusMeters,
    this.hotline,
    this.address,
    this.latitude,
    this.longitude,
  });

  factory VenuePublicInformation.fromJson(Map<String, dynamic> json) {
    return VenuePublicInformation(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Institution',
      branch: json['branch'] as String? ?? 'Participating venue',
      hotline: json['official_contact'] as String?,
      address: json['service_address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      radiusMeters:
          (json['location_match_radius_m'] as num?)?.toDouble() ?? 500,
    );
  }
}
