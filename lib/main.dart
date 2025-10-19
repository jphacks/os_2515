import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/todo_repository.dart';
import 'services/calendar_service.dart';
import 'pages/todo_page.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/notification_service.dart';
import 'background/notification_worker.dart';

final auth = AuthService();
final repo = TodoRepository(CalendarService(auth));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //通知の初期化
  await NotificationService.instance.init();
  //Android13+の通知許可（ユーザに一度だけ聞く)
  await FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();

  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    'daily-deadline-check',
    kDailyTaskName,
    frequency: const Duration(hours: 24),
    initialDelay: _initialDelayTo9AM(),
    backoffPolicy: BackoffPolicy.exponential,
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await auth.initialize();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: TodoPage(repo: repo), // ← TodoPage 単体ではなく HomeTabs に
    ),
  );
}

Duration _initialDelayTo9AM() {
  final now = DateTime.now();
  final nine = DateTime(now.year, now.month, now.day, 9); //本番用　アプリを閉じていても毎朝9時に
  final first = now.isBefore(nine) ? nine : nine.add(const Duration(days: 1));
  return first.difference(now);
}
