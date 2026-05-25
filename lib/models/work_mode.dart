// lib/models/work_mode.dart
enum WorkModeType {
  deemed,  // みなし勤務（8:00-17:00固定）
  actual,  // 実勤務（出勤・退勤ボタン）
}

class WorkSession {
  WorkSession({
    required this.mode,
    required this.date,
    this.clockIn,
    this.clockOut,
    String? id,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  final String       id;
  final WorkModeType mode;
  final DateTime     date;
  final DateTime?    clockIn;
  final DateTime?    clockOut;

  DateTime get effectiveClockIn =>
      mode == WorkModeType.deemed
          ? DateTime(date.year, date.month, date.day, 8, 0)
          : (clockIn ?? DateTime(date.year, date.month, date.day, 8, 0));

  DateTime? get effectiveClockOut =>
      mode == WorkModeType.deemed
          ? DateTime(date.year, date.month, date.day, 17, 0)
          : clockOut;

  Duration? get workDuration {
    final out = effectiveClockOut;
    if (out == null) return null;
    return out.difference(effectiveClockIn);
  }

  String get clockInLabel {
    final t = effectiveClockIn;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String? get clockOutLabel {
    final t = effectiveClockOut;
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String get durationLabel {
    final d = workDuration;
    if (d == null) return '勤務中...';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return '$h時間${m > 0 ? '$m分' : ''}';
  }

  bool get isComplete => effectiveClockOut != null;

  Map<String, dynamic> toJson() => {
    'id':       id,
    'mode':     mode.name,
    'date':     date.toIso8601String(),
    'clockIn':  clockIn?.toIso8601String(),
    'clockOut': clockOut?.toIso8601String(),
  };

  static WorkSession fromJson(Map<String, dynamic> j) => WorkSession(
    id:       j['id'] as String?,
    mode:     WorkModeType.values.firstWhere(
      (m) => m.name == j['mode'], orElse: () => WorkModeType.deemed),
    date:     DateTime.parse(j['date'] as String),
    clockIn:  j['clockIn']  != null ? DateTime.tryParse(j['clockIn']  as String) : null,
    clockOut: j['clockOut'] != null ? DateTime.tryParse(j['clockOut'] as String) : null,
  );
}
