// lib/services/todo_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/todo.dart';
import 'calendar_service.dart';
import 'fatigue_service.dart';

class TodoRepository {
  TodoRepository(this._calendar);

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final CalendarService _calendar;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _colFor(String uid) =>
      _db.collection('users').doc(uid).collection('todos');

  // ===== 読み取りストリーム =====
  Stream<List<Todo>> watchActive() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _colFor(uid)
        .where('state', whereIn: ['active', 'switchedToReal'])
        .orderBy('displayedDue', descending: false)
        .snapshots()
        .map((s) => s.docs.map((d) => Todo.fromDoc(d)).toList());
  }

  Stream<List<Todo>> watchCompleted() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _colFor(uid)
        .where('state', isEqualTo: 'completed')
        .orderBy('completedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Todo.fromDoc(d)).toList());
  }

  Future<List<Todo>> fetchActiveOnce() async {
    final uid = _uid;
    if (uid == null) return [];
    final qs = await _colFor(
      uid,
    ).where('state', whereIn: ['active', 'switchedToReal']).get();
    return qs.docs.map((d) => Todo.fromDoc(d)).toList();
  }

  // ===== 追加 =====
  Future<void> addTodo({
    required String title,
    required DateTime realDue,
    int bufferDays = 3,
    bool syncToCalendar = true,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final now = DateTime.now();

    final displayed = realDue.subtract(Duration(days: bufferDays));

    String? eventId;
    if (syncToCalendar) {
      eventId = await _calendar.createEvent(
        summary: title,
        start: _anchor0900(displayed),
        end: _anchor0900(displayed).add(const Duration(hours: 1)),
        description: 'source=todo-app',
      );
    }

    await _colFor(uid).add({
      'title': title,
      'displayedDue': Timestamp.fromDate(_anchor0900(displayed)),
      'realDue': Timestamp.fromDate(_anchor0900(realDue)),
      'calendarEventId': eventId,
      'state': 'active',
      'completedAt': null,
      'switchedAt': null,
      'leadDays': 0,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  // ===== 表示→実期限への切替 =====
  Future<int> switchOverdueToReal() async {
    final uid = _uid;
    if (uid == null) return 0;
    final now = DateTime.now();

    final qs = await _colFor(uid)
        .where('state', isEqualTo: 'active')
        .where('displayedDue', isLessThanOrEqualTo: Timestamp.fromDate(now))
        .get();

    int updated = 0;
    for (final doc in qs.docs) {
      final data = doc.data();
      final eventId = data['calendarEventId'] as String?;
      final realDue = (data['realDue'] as Timestamp?)?.toDate();

      await doc.reference.update({
        'state': 'switchedToReal',
        'switchedAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
      });
      updated++;

      if (eventId != null && realDue != null) {
        final start = _anchor0900(realDue);
        await _calendar.updateEventStart(
          eventId: eventId,
          newStart: start,
          newEnd: start.add(const Duration(hours: 1)),
        );
      }
    }
    return updated;
  }

  // ===== “1日だけ”前倒し（疲労ロジックから呼ばれる） =====
  /// 前倒しに成功したら “新しい displayedDue” を返す。不可なら null。
  Future<DateTime?> frontloadOneDay(Todo todo) async {
    if (todo.state != TodoState.active) return null;
    if (todo.realDue == null || todo.displayedDue == null) return null;

    final real = todo.realDue!;
    final displayed = todo.displayedDue!;

    // 実締切48h以内は前倒し禁止
    final now = DateTime.now();
    if (real.difference(now) <= FatigueService.minRealDueGap) return null;

    // 最大5日まで（displayed >= real - 5日）
    final floorDisplay = real.subtract(
      Duration(days: FatigueService.maxFrontloadDays),
    );
    final candidate = displayed.subtract(const Duration(days: 1));
    final nextDisplayed = candidate.isBefore(floorDisplay)
        ? floorDisplay
        : candidate;

    if (!nextDisplayed.isBefore(displayed)) return null; // 変化なし

    await _colFor(_uid!).doc(todo.id).update({
      'displayedDue': Timestamp.fromDate(_anchor0900(nextDisplayed)),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    return _anchor0900(nextDisplayed);
  }

  // ===== 完了処理 =====
  Future<void> complete(Todo todo) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final now = DateTime.now();
    final real = todo.realDue ?? todo.displayedDue ?? now;
    final lead = Todo.earlyDaysOnComplete(realDue: real, completedAt: now);

    await _colFor(uid).doc(todo.id).update({
      'state': 'completed',
      'completedAt': Timestamp.fromDate(now),
      'leadDays': lead,
      'updatedAt': Timestamp.fromDate(now),
    });

    if (todo.calendarEventId != null) {
      await _calendar.updateEventTitle(
        eventId: todo.calendarEventId!,
        newTitle: '[DONE] ${todo.title}',
      );
    }
  }

  // 実期限も過ぎて未完のものはリストに残す（仕様どおり）。拡張用のフック。
  Future<void> markLateIfNeeded(Todo todo) async {
    if (todo.realDue == null) return;
    final now = DateTime.now();
    if (now.isAfter(todo.realDue!) && todo.state != TodoState.completed) {
      await _colFor(
        _uid!,
      ).doc(todo.id).update({'updatedAt': Timestamp.fromDate(now)});
    }
  }

  DateTime _anchor0900(DateTime base) =>
      DateTime(base.year, base.month, base.day, 9, 0);
}
