class SosHistoryEntry {
  SosHistoryEntry.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      triggeredAt = DateTime.parse(json['triggered_at'] as String),
      endedAt = DateTime.tryParse(json['ended_at'] as String? ?? ''),
      status = json['status'] as String? ?? 'unknown',
      latitude = (json['latitude'] as num?)?.toDouble(),
      longitude = (json['longitude'] as num?)?.toDouble(),
      institution = json['institution_name'] as String?,
      serviceArea = json['service_area_name'] as String?,
      requestStatus = (json['request'] as Map?)?['status'] as String?,
      assignedStaff = (json['request'] as Map?)?['staff_name'] as String?,
      staffContact = (json['request'] as Map?)?['staff_contact'] as String?,
      resolvedAt = DateTime.tryParse(
        (json['request'] as Map?)?['resolved_at'] as String? ?? '',
      ),
      institutionStatus = json['institution_status'] as String? ?? 'pending',
      contactName = json['contact_name'] as String?,
      contactStatus = json['contact_status'] as String? ?? 'notRecorded',
      contactAttemptedAt = DateTime.tryParse(
        json['contact_attempted_at'] as String? ?? '',
      ),
      institutionAttemptedAt = DateTime.tryParse(
        json['institution_attempted_at'] as String? ?? '',
      );

  final String id;
  final DateTime triggeredAt;
  final DateTime? endedAt;
  final String status;
  final double? latitude;
  final double? longitude;
  final String? institution;
  final String? serviceArea;
  final String? requestStatus;
  final String? assignedStaff;
  final String? staffContact;
  final DateTime? resolvedAt;
  final String institutionStatus;
  final String? contactName;
  final String contactStatus;
  final DateTime? contactAttemptedAt;
  final DateTime? institutionAttemptedAt;

  // Ending device alerts does not resolve an institution's emergency request.
  String get progressStatus => requestStatus ?? institutionStatus;
  bool get assistanceOngoing =>
      requestStatus != null && requestStatus != 'resolved';
  String get assistanceSummary => requestStatus == 'resolved'
      ? 'Assistance completed'
      : assistanceOngoing
      ? 'Assistance is ongoing'
      : 'No institution assistance confirmed';

  String get location => latitude == null || longitude == null
      ? 'Location unavailable'
      : '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}';

  List<EmergencyCommunicationEntry> get communications => [
    if (contactAttemptedAt != null)
      EmergencyCommunicationEntry(
        recipient: _nameOr(contactName, 'Emergency contact'),
        occurredAt: contactAttemptedAt!,
        type: 'Emergency contact notification',
        status: contactStatus == 'notified'
            ? 'Notification confirmed'
            : historyStatusLabel(contactStatus),
      ),
    if (institutionAttemptedAt != null &&
        (requestStatus != null ||
            institutionStatus == 'requestSent' ||
            institutionStatus == 'failed'))
      EmergencyCommunicationEntry(
        recipient: _nameOr(institution, 'Institution assistance'),
        occurredAt: institutionAttemptedAt!,
        type: 'Institution SOS request',
        status: historyStatusLabel(requestStatus ?? institutionStatus),
      ),
  ];
}

String _nameOr(String? value, String fallback) =>
    value == null || value.trim().isEmpty ? fallback : value.trim();

class EmergencyCommunicationEntry {
  const EmergencyCommunicationEntry({
    required this.recipient,
    required this.occurredAt,
    required this.type,
    required this.status,
  });
  final String recipient;
  final DateTime occurredAt;
  final String type;
  final String status;
}

String historyStatusLabel(String status) => switch (status) {
  'active' => 'Active',
  'ended' => 'Ended',
  'sent' || 'requestSent' => 'Request sent',
  'acknowledged' => 'Acknowledged',
  'assigned' => 'Staff assigned',
  'en_route' => 'On the way',
  'resolved' => 'Resolved',
  'failed' => 'Failed',
  'pending' => 'Pending / outcome not recorded',
  'noAffiliatedInstitution' => 'No affiliated institution nearby',
  'locationUnavailable' => 'Location unavailable',
  'notConfigured' => 'No verified contact configured',
  'notRecorded' => 'Not recorded',
  'unknown' => 'End time not recorded',
  _ => status,
};
