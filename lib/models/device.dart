// ============================================================
// lib/models/device.dart - デバイスモデル
// ============================================================

class Device {
  final String deviceId;
  final String userId;
  final String deviceName;
  final String deviceType; // 'smartphone', 'tablet', 'pc'
  final String? osType; // 'android', 'ios', 'windows', 'macos', 'linux'
  final String? modelName;
  final String? fcmToken;
  final bool isPrimary;
  final bool isActive;
  final DateTime? lastUsedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Device({
    required this.deviceId,
    required this.userId,
    required this.deviceName,
    required this.deviceType,
    this.osType,
    this.modelName,
    this.fcmToken,
    required this.isPrimary,
    required this.isActive,
    this.lastUsedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  // JSON から Device オブジェクトを生成
  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      deviceId: json['device_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      deviceName: json['device_name'] as String? ?? '',
      deviceType: json['device_type'] as String? ?? 'smartphone',
      osType: json['os_type'] as String?,
      modelName: json['model_name'] as String?,
      fcmToken: json['fcm_token'] as String?,
      isPrimary: json['is_primary'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  // Device オブジェクトを JSON に変換
  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'user_id': userId,
      'device_name': deviceName,
      'device_type': deviceType,
      'os_type': osType,
      'model_name': modelName,
      'fcm_token': fcmToken,
      'is_primary': isPrimary,
      'is_active': isActive,
      'last_used_at': lastUsedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // デバイスのコピー（更新用）
  Device copyWith({
    String? deviceId,
    String? userId,
    String? deviceName,
    String? deviceType,
    String? osType,
    String? modelName,
    String? fcmToken,
    bool? isPrimary,
    bool? isActive,
    DateTime? lastUsedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Device(
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      deviceName: deviceName ?? this.deviceName,
      deviceType: deviceType ?? this.deviceType,
      osType: osType ?? this.osType,
      modelName: modelName ?? this.modelName,
      fcmToken: fcmToken ?? this.fcmToken,
      isPrimary: isPrimary ?? this.isPrimary,
      isActive: isActive ?? this.isActive,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'Device(deviceId: $deviceId, deviceName: $deviceName, deviceType: $deviceType, isPrimary: $isPrimary)';
  }
}