// Web stub: flutter_local_notifications is not supported on web

class FlutterLocalNotificationsPlugin {
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    void Function(dynamic)? onDidReceiveNotificationResponse,
  }) async => null;

  Future<void> cancelAll() async {}
  Future<void> cancel(int id) async {}

  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    dynamic scheduledDate,
    NotificationDetails notificationDetails, {
    required AndroidScheduleMode androidScheduleMode,
    required UILocalNotificationDateInterpretation uiLocalNotificationDateInterpretation,
    DateTimeComponents? matchDateTimeComponents,
    String? payload,
  }) async {}
}

class AndroidInitializationSettings {
  final String defaultIcon;
  const AndroidInitializationSettings(this.defaultIcon);
}

class DarwinInitializationSettings {
  final bool requestAlertPermission;
  final bool requestBadgePermission;
  final bool requestSoundPermission;
  const DarwinInitializationSettings({
    this.requestAlertPermission = true,
    this.requestBadgePermission = true,
    this.requestSoundPermission = true,
  });
}

class InitializationSettings {
  final AndroidInitializationSettings? android;
  final DarwinInitializationSettings? iOS;
  const InitializationSettings({this.android, this.iOS});
}

class NotificationDetails {
  final AndroidNotificationDetails? android;
  final DarwinNotificationDetails? iOS;
  const NotificationDetails({this.android, this.iOS});
}

class AndroidNotificationDetails {
  final String channelId;
  final String channelName;
  final String? channelDescription;
  final Importance? importance;
  final Priority? priority;
  const AndroidNotificationDetails(
    this.channelId,
    this.channelName, {
    this.channelDescription,
    this.importance,
    this.priority,
  });
}

class DarwinNotificationDetails {
  const DarwinNotificationDetails();
}

class Importance {
  // ignore: unused_field
  final int _value;
  const Importance._(this._value);
  static const Importance defaultImportance = Importance._(3);
  static const Importance high = Importance._(4);
  static const Importance max = Importance._(5);
}

class Priority {
  // ignore: unused_field
  final int _value;
  const Priority._(this._value);
  static const Priority defaultPriority = Priority._(0);
  static const Priority high = Priority._(1);
}

class AndroidScheduleMode {
  // ignore: unused_field
  final String _value;
  const AndroidScheduleMode._(this._value);
  static const AndroidScheduleMode exact = AndroidScheduleMode._('exact');
  static const AndroidScheduleMode exactAllowWhileIdle = AndroidScheduleMode._('exactAllowWhileIdle');
  static const AndroidScheduleMode inexact = AndroidScheduleMode._('inexact');
  static const AndroidScheduleMode inexactAllowWhileIdle = AndroidScheduleMode._('inexactAllowWhileIdle');
}

class UILocalNotificationDateInterpretation {
  // ignore: unused_field
  final String _value;
  const UILocalNotificationDateInterpretation._(this._value);
  static const UILocalNotificationDateInterpretation absoluteTime =
      UILocalNotificationDateInterpretation._('absoluteTime');
  static const UILocalNotificationDateInterpretation wallClockTime =
      UILocalNotificationDateInterpretation._('wallClockTime');
}

class DateTimeComponents {
  // ignore: unused_field
  final String _value;
  const DateTimeComponents._(this._value);
  static const DateTimeComponents time = DateTimeComponents._('time');
  static const DateTimeComponents dayOfWeekAndTime = DateTimeComponents._('dayOfWeekAndTime');
  static const DateTimeComponents dayOfMonthAndTime = DateTimeComponents._('dayOfMonthAndTime');
  static const DateTimeComponents dateAndTime = DateTimeComponents._('dateAndTime');
}
