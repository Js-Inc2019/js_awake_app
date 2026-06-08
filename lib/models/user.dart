// ============================================================
// lib/models/user.dart - ユーザーモデル
// ============================================================

class User {
  final String userId;
  final String name;
  final String? phoneNumber;
  final String? email;
  final String company;
  final String role; // 'worker', 'boss', 'admin_office', 'admin_exec'
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  User({
    required this.userId,
    required this.name,
    this.phoneNumber,
    this.email,
    required this.company,
    required this.role,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  // JSON から User オブジェクトを生成
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phoneNumber: json['phone_number'] as String?,
      email: json['email'] as String?,
      company: json['company'] as String? ?? '',
      role: json['role'] as String? ?? 'worker',
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  // User オブジェクトを JSON に変換
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'phone_number': phoneNumber,
      'email': email,
      'company': company,
      'role': role,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // ユーザーのコピー（更新用）
  User copyWith({
    String? userId,
    String? name,
    String? phoneNumber,
    String? email,
    String? company,
    String? role,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      company: company ?? this.company,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'User(userId: $userId, name: $name, role: $role, company: $company)';
  }
}