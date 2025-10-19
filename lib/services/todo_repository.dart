// lib/services/todo_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/todo.dart';
import 'calendar_service.dart';
import 'fatigue_service.dart';
import 'dart:math'; // 日付の前倒しをランダムにするために追加 (issue-5)

class TodoRepository {
  TodoRepository(this._calendar);

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final CalendarService _calendar;
  static const List<int> initialBufferDays = [1, 2, 3, 4, 5, 6, 7]; // 前倒し用ランダム日数リスト
  static const List<int> anchorHours = [0, 6, 12, 18]; // 前倒し用ランダム時刻リスト
  final _random = Random();

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

  /// 全タスクを購読（active/real/complete をすべて含む）
  /// 変更があるたびに最新の一覧を流します。
  Stream<List<Todo>> watchAll() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _colFor(uid)
        .orderBy('updatedAt', descending: true)
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
    int bufferDays = 3, // 諸悪の根源(issue-5)
    bool syncToCalendar = true,
    required int moodValue, //issue-11
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 前倒し日数リストからランダムで選択(issue-5)
    final int randomIndex = _random.nextInt(initialBufferDays.length);
    final int randomDays = initialBufferDays[randomIndex];
    final int backDays = randomDays + moodValue;

    // final displayed = realDue.subtract(Duration(days: bufferDays));
    final candidate_displayed = realDue.subtract(Duration(days: backDays)); // ランダムに選択された日数を引くように修正(issue-5)
    final displayed = candidate_displayed.isBefore(today) ? today : candidate_displayed; // 今日の日付よりも前になっていないかを確認(issue-5)

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

Future<void> updateDisplayedDue(String todoId, DateTime newDisplayed) async {
  final uid = _uid;
  if (uid == null) return;

  await _colFor(uid).doc(todoId).update({
    'displayedDue': Timestamp.fromDate(newDisplayed),
    // 端末時間の誤差を避けたい場合はサーバ時刻
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<List<Todo>> listAll() async {
  final uid = _uid;
  if (uid == null) return [];

  // ⚠ ここでは複合 orderBy を使わない（= インデックス不要）
  final qs = await _colFor(uid).get();

  final list = qs.docs.map((d) => Todo.fromDoc(d)).toList();

  // ↓ 並びはメモリ上で安定ソート（state → displayedDue/realDue → id）
  int stateRank(Todo t) {
    switch (t.state) {
      case TodoState.active: return 0;
      case TodoState.switchedToReal: return 1;
      case TodoState.completed: return 2;
    }
  }

  DateTime far = DateTime(9999);
  list.sort((a, b) {
    final sa = stateRank(a), sb = stateRank(b);
    if (sa != sb) return sa - sb;

    final da = (a.displayedDue ?? a.realDue) ?? far;
    final db = (b.displayedDue ?? b.realDue) ?? far;
    final c = da.compareTo(db);
    if (c != 0) return c;

    return a.id.compareTo(b.id);
  });

  return list;
  }

//   DateTime _anchor0900(DateTime base) =>
//       DateTime(base.year, base.month, base.day, 9, 0);
// }
  // DateTime _anchor0900(DateTime base){ // 0900とは言っているが、時間をランダムに変更したもの(issue-5)
  //   final int randomIndex = _random.nextInt(anchorHours.length);
  //   final int randomHour = anchorHours[randomIndex];
  //   return DateTime(base.year, base.month, base.day, randomHour, 0);
  // }
DateTime _anchor0900(DateTime base){ // 0900とは言っているが、時間をランダムに変更したもの(issue-5)
		final now = DateTime.now();
		
		if (base.year == now.year && base.month == now.month && base.day == now.day) {

			final List<int> validHours = [];
			for (final hour in anchorHours) {
				final candidateTime = DateTime(base.year, base.month, base.day, hour, 0);
				
				// 厳密に現在時刻より後であるかを確認 (12:16 > 12:00 を回避)
				if (candidateTime.isAfter(now)) {
					validHours.add(hour);
				}
			}

			if (validHours.isNotEmpty) {
				// 使える時間がある場合: ランダム
				final randomIndex = _random.nextInt(validHours.length);
				final randomHour = validHours[randomIndex];
				return DateTime(base.year, base.month, base.day, randomHour, 0);
			} else {
				// 使える時間がない場合（今日のアンカー時刻をすべて過ぎた）今日の23時59分を返す
				return DateTime(base.year, base.month, base.day, 23, 59);
			}
		} 
		
		final int randomIndex = _random.nextInt(anchorHours.length);
		final int randomHour = anchorHours[randomIndex];
		return DateTime(base.year, base.month, base.day, randomHour, 0);
	}
}