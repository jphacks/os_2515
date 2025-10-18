import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fln = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 通知初期化
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _fln.initialize(init);

    // 予約通知に必要（デモなので固定で Asia/Tokyo）
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
  }

  // その場通知（任意）
  Future<void> showTaskReminder(String title, int daysLeft) {
    return _fln.show(
      Random().nextInt(1 << 31),
      title,
      'タスクの期限まであと${daysLeft}日です！',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'leeway_deadlines',
          'Leeway Deadlines',
          channelDescription: 'タスク期限のリマインド',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  // ★ デモ用：N秒後に一回だけ通知
  Future<void> scheduleTaskReminderInSeconds({
    required String title,
    required int daysLeft,
    int seconds = 5,
  }) async {
    await Future.delayed(Duration(seconds: seconds));
    await _fln.show(
      Random().nextInt(1 << 31),
      title,
      'タスクの期限まであと${daysLeft}日です！',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'leeway_deadlines',
          'Leeway Deadlines',
          channelDescription: 'タスク期限のリマインド',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
