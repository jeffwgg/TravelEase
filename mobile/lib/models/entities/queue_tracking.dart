class QueueLineInfo {
  final String id;
  final String name;
  final String serviceArea;
  final String? serviceAreaId;

  /// Optional service counter label. The web portal no longer sets it, so it
  /// may be absent — [counterLabel] falls back to the service area.
  final String? counter;
  final String prefix;
  final String currentNumber;
  final String upcomingNumber;
  final String status;
  final int estimatedServiceMinutes;
  final String? operatingHours;

  /// How many numbers ahead of the currently served number travellers can
  /// register and track. Falls back to the system default of 100 when the
  /// queue line does not define a value.
  final int maxTrackingNumber;

  static const defaultMaxTrackingNumber = 100;

  const QueueLineInfo({
    required this.id,
    required this.name,
    required this.serviceArea,
    this.serviceAreaId,
    this.counter,
    required this.prefix,
    required this.currentNumber,
    required this.upcomingNumber,
    required this.status,
    required this.estimatedServiceMinutes,
    this.operatingHours,
    this.maxTrackingNumber = defaultMaxTrackingNumber,
  });

  /// Where the traveller should go when called: the counter when one is
  /// configured, otherwise the line's service area.
  String get counterLabel {
    final value = counter?.trim();
    if (value != null && value.isNotEmpty) return value;
    return serviceArea;
  }

  factory QueueLineInfo.fromJson(Map<String, dynamic> json) => QueueLineInfo(
    id: json['id'] as String,
    name: json['name'] as String,
    serviceArea: json['service_area'] as String,
    serviceAreaId: json['service_area_id'] as String?,
    counter: json['counter'] as String?,
    prefix: json['prefix'] as String? ?? '',
    currentNumber: json['current_number'] as String,
    upcomingNumber: json['upcoming_number'] as String,
    status: json['status'] as String,
    estimatedServiceMinutes: json['estimated_service_minutes'] as int? ?? 5,
    operatingHours: json['operating_hours'] as String?,
    maxTrackingNumber:
        json['max_tracking_number'] as int? ?? defaultMaxTrackingNumber,
  );
}

class QueueTrackingData {
  final String id;
  final String number;
  final String status;
  final DateTime? calledAt;
  final QueueLineInfo line;

  const QueueTrackingData({
    required this.id,
    required this.number,
    required this.status,
    required this.line,
    this.calledAt,
  });

  factory QueueTrackingData.fromJson(Map<String, dynamic> json) =>
      QueueTrackingData(
        id: json['id'] as String,
        number: json['number'] as String,
        status: json['status'] as String,
        calledAt: json['called_at'] == null
            ? null
            : DateTime.parse(json['called_at'] as String),
        line: QueueLineInfo.fromJson(
          json['queue_lines'] as Map<String, dynamic>,
        ),
      );

  int get peopleAhead {
    if (status != 'waiting') return 0;
    final mine = int.tryParse(
      RegExp(r'\d+$').firstMatch(number)?.group(0) ?? '',
    );
    final current = int.tryParse(
      RegExp(r'\d+$').firstMatch(line.currentNumber)?.group(0) ?? '',
    );
    if (mine == null || current == null) return 0;
    final difference = mine - current;
    if (difference < 0) return 0;
    return difference > 999 ? 999 : difference;
  }

  int get estimatedWaitMinutes => peopleAhead * line.estimatedServiceMinutes;
}
