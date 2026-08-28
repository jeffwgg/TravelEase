class VenueSearchResult {
  final String id;
  final String name;
  final String branch;

  const VenueSearchResult({
    required this.id,
    required this.name,
    required this.branch,
  });

  factory VenueSearchResult.fromJson(Map<String, dynamic> json) =>
      VenueSearchResult(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Institution',
        branch: json['branch'] as String? ?? 'Participating venue',
      );
}
