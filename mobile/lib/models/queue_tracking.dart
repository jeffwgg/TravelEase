class QueueLineInfo {
  final String id;
  final String name;
  final String serviceArea;
  final String counter;
  final String currentNumber;
  final String upcomingNumber;
  final String status;
  final int estimatedServiceMinutes;
  final String? operatingHours;

  const QueueLineInfo({
    required this.id,
    required this.name,
    required this.serviceArea,
    required this.counter,
    required this.currentNumber,
    required this.upcomingNumber,
    required this.status,
    required this.estimatedServiceMinutes,
    this.operatingHours,
  });

  factory QueueLineInfo.fromJson(Map<String, dynamic> json) => QueueLineInfo(
    id: json['id'] as String,
    name: json['name'] as String,
    serviceArea: json['service_area'] as String,
    counter: json['counter'] as String,
    currentNumber: json['current_number'] as String,
    upcomingNumber: json['upcoming_number'] as String,
    status: json['status'] as String,
    estimatedServiceMinutes: json['estimated_service_minutes'] as int? ?? 5,
    operatingHours: json['operating_hours'] as String?,
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
