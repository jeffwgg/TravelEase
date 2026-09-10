/// An active venue session binding the traveller to a participating
/// institution (FR-M2-03, FR-M2-04). The session stays alive across app
/// restarts until the traveller quits it.
class VenueSession {
  final String institutionId;
  final String institutionName;
  final String? branch;
  final DateTime startedAt;

  const VenueSession({
    required this.institutionId,
    required this.institutionName,
    required this.startedAt,
    this.branch,
  });
}
