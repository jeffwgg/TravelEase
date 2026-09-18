class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.userId,
    required this.name,
    required this.relationship,
    required this.phoneNumber,
    required this.email,
    required this.isPrimary,
    required this.isVerified,
  });

  final String id;
  final String userId;
  final String name;
  final String relationship;
  final String phoneNumber;
  final String email;
  final bool isPrimary;
  final bool isVerified;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      relationship: json['relationship'] as String,
      phoneNumber: json['phone_number'] as String,
      email: json['email'] as String? ?? '',
      isPrimary: json['is_primary'] as bool? ?? false,
      isVerified: json['is_verified'] as bool? ?? false,
    );
  }

  EmergencyContact copyWith({bool? isPrimary, bool? isVerified}) {
    return EmergencyContact(
      id: id,
      userId: userId,
      name: name,
      relationship: relationship,
      phoneNumber: phoneNumber,
      email: email,
      isPrimary: isPrimary ?? this.isPrimary,
      isVerified: isVerified ?? this.isVerified,
    );
  }
}
