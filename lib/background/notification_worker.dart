// lib/background/notification_worker.dart

import 'package:workmanager/workmanager.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase_options.dart';
import '../services/notification_service.dart';

const kDailyTaskName = 'leeway_daily_deadline_check';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await NotificationService.instance.init();

    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('uid'); // ← サインイン時に保存（下の補足参照）
    if (uid == null) return true;

    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('todos');

    final snap = await col.where('done', isEqualTo: false).get();

    final now = DateTime.now();
    for (final doc in snap.docs) {
      final data = doc.data();

      // Timestamp? を DateTime? に変換して優先順位で採用
      DateTime? pickTs(Map<String, dynamic> m, String k) {
        final v = m[k];
        if (v is Timestamp) return v.toDate();
        return null;
      }

      final due =
          pickTs(data, 'displayedDue') ??
          pickTs(data, 'realDue') ??
          pickTs(data, 'due');
      if (due == null) continue;

      final daysLeft = _daysLeftFromNow(due, now);
      if (daysLeft == 7 || daysLeft == 3 || daysLeft == 1 || daysLeft == 0) {
        final title = (data['title'] as String?) ?? 'タスク';
        await NotificationService.instance.showTaskReminder(title, daysLeft);
      }
    }
    return true;
  });
}

int _daysLeftFromNow(DateTime due, DateTime now) {
  final d0 = DateTime(now.year, now.month, now.day);
  final d1 = DateTime(due.year, due.month, due.day);
  return d1.difference(d0).inDays;
}
