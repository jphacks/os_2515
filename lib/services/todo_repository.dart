// lib/services/todo_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/todo.dart';
import 'calendar_service.dart';
import 'fatigue_service.dart';
import 'dart:math'; // 日付の前倒しをランダムにするために追加 (issue-5)
import 'dart:math' show exp;

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
  // Future<void> addTodo({
  //   required String title,
  //   required DateTime realDue,
  //   int bufferDays = 3, // 諸悪の根源(issue-5)
  //   bool syncToCalendar = true,
  //   required int moodValue, //issue-11
  // }) async {
  //   final uid = _uid;
  //   if (uid == null) throw StateError('Not signed in');
  //   final now = DateTime.now();
  //   final today = DateTime(now.year, now.month, now.day);

  //   // 前倒し日数リストからランダムで選択(issue-5)
  //   final int randomIndex = _random.nextInt(initialBufferDays.length);
  //   final int randomDays = initialBufferDays[randomIndex];
  //   final int backDays = randomDays + moodValue;

  //   // final displayed = realDue.subtract(Duration(days: bufferDays));
  //   final candidate_displayed = realDue.subtract(Duration(days: backDays)); // ランダムに選択された日数を引くように修正(issue-5)
  //   final displayed = candidate_displayed.isBefore(today) ? today : candidate_displayed; // 今日の日付よりも前になっていないかを確認(issue-5)

  //   String? eventId;
  //   if (syncToCalendar) {
  //     eventId = await _calendar.createEvent(
  //       summary: title,
  //       start: await _anchor0900(displayed),
  //       end: (await _anchor0900(displayed)).add(const Duration(hours: 1)),
  //       description: 'source=todo-app',
  //     );
  //   }

  //   await _colFor(uid).add({
  //     'title': title,
  //     'displayedDue': Timestamp.fromDate(await _anchor0900(displayed)),
  //     'realDue': Timestamp.fromDate(await _anchor0900(realDue)),
  //     'calendarEventId': eventId,
  //     'state': 'active',
  //     'completedAt': null,
  //     'switchedAt': null,
  //     'leadDays': 0,
  //     'createdAt': Timestamp.fromDate(now),
  //     'updatedAt': Timestamp.fromDate(now),
  //   });
  // }

  // 変更点: Future<void> を Future<DateTime> に変更
	Future<DateTime> addTodo({ 
		required String title,
		required DateTime realDue,
		int bufferDays = 3,
		bool syncToCalendar = true,
		required int moodValue,
	}) async {
		final uid = _uid;
		if (uid == null) throw StateError('Not signed in');
		final now = DateTime.now();
		final today = DateTime(now.year, now.month, now.day);

		// 前倒し日数リストからランダムで選択(issue-5)
		final int randomIndex = _random.nextInt(initialBufferDays.length);
		final int randomDays = initialBufferDays[randomIndex];
		final int backDays = randomDays + moodValue;

		// 前倒しされた日付を計算
		final candidate_displayed = realDue.subtract(Duration(days: backDays));
		final displayed = candidate_displayed.isBefore(today) ? today : candidate_displayed;

		// 💡 Softmax時刻付きの前倒し期限を計算 (displayedDue)
		final finalDisplayedDue = await _anchor0900(displayed); // 👈 変数に格納
		final finalRealDue = await _anchor0900(realDue);

		String? eventId;
		if (syncToCalendar) {
			final eventEnd = finalDisplayedDue.add(const Duration(hours: 1)); // 👈 格納した変数を使用
			eventId = await _calendar.createEvent(
				summary: title,
				start: finalDisplayedDue, // 👈 格納した変数を使用
				end: eventEnd,
				description: 'source=todo-app',
			);
		}

		await _colFor(uid).add({
			'title': title,
			'displayedDue': Timestamp.fromDate(finalDisplayedDue), // 👈 格納した変数を使用
			'realDue': Timestamp.fromDate(finalRealDue), // 👈 格納した変数を使用
			'calendarEventId': eventId,
			'state': 'active',
			'completedAt': null,
			'switchedAt': null,
			'leadDays': 0,
			'createdAt': Timestamp.fromDate(now),
			'updatedAt': Timestamp.fromDate(now),
		});
		
		// 💡 変更点: 確定した前倒し後の期限を返す
		return finalDisplayedDue; 
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
        final start = await _anchor0900(realDue);
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
      'displayedDue': Timestamp.fromDate(await _anchor0900(nextDisplayed)),
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    return await _anchor0900(nextDisplayed);
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

  // 過去の全てのタスクの真の期限を取得
  Future<List<DateTime>> _fetchAllRealDues() async {
    final uid = _uid;
    if (uid == null) return [];
    
    // 完了済みだけでなく、Firestore上の全てのタスクを取得する
    final qs = await _colFor(uid).get();
      
    return qs.docs
      .map((d) => (d.data()['realDue'] as Timestamp?)?.toDate())
      .whereType<DateTime>()
      .toList();
  }

  // Softmax
  Map<int, double> _softmax(Map<int, int> counts) {
    if (counts.isEmpty) return {};
    
    final Map<int, double> exponents = counts.map((key, value) => MapEntry(key, exp(value.toDouble())));
    final double sumOfExponents = exponents.values.fold(0.0, (prev, element) => prev + element);
    
    if (sumOfExponents == 0) {
      // 全てのカウントが0の場合、均等な確率を割り当てる
      final double uniformProb = 1.0 / counts.length;
      return counts.map((key, value) => MapEntry(key, uniformProb));
    }
    
    // 確率を計算
    return exponents.map((key, value) => MapEntry(key, value / sumOfExponents));
  }

  // 確率分布に基づいてサンプリング
  int _sampleFromProbabilities(Map<int, double> probabilities) {
    if (probabilities.isEmpty) return 0;
    
    final double rand = _random.nextDouble();
    double cumulativeProbability = 0.0;
    
    // キーをソート
    final sortedEntries = probabilities.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    for (final entry in sortedEntries) {
      cumulativeProbability += entry.value;
      if (rand < cumulativeProbability) {
        return entry.key; // サンプリングされた値（時間または分）
      }
    }
    
    return sortedEntries.last.key; // フォールバック
  }


  // DateTime _anchor0900(DateTime base){ // 0900とは言っているが、時間をランダムに変更したもの(issue-5)
	// 	final now = DateTime.now();
		
	// 	if (base.year == now.year && base.month == now.month && base.day == now.day) {

	// 		final List<int> validHours = [];
	// 		for (final hour in anchorHours) {
	// 			final candidateTime = DateTime(base.year, base.month, base.day, hour, 0);
				
	// 			// 厳密に現在時刻より後であるかを確認 (12:16 > 12:00 を回避)
	// 			if (candidateTime.isAfter(now)) {
	// 				validHours.add(hour);
	// 			}
	// 		}

	// 		if (validHours.isNotEmpty) {
	// 			// 使える時間がある場合: ランダム
	// 			final randomIndex = _random.nextInt(validHours.length);
	// 			final randomHour = validHours[randomIndex];
	// 			return DateTime(base.year, base.month, base.day, randomHour, 0);
	// 		} else {
	// 			// 使える時間がない場合（今日のアンカー時刻をすべて過ぎた）今日の23時59分を返す
	// 			return DateTime(base.year, base.month, base.day, 23, 59);
	// 		}
	// 	} 
		
	// 	final int randomIndex = _random.nextInt(anchorHours.length);
	// 	final int randomHour = anchorHours[randomIndex];
	// 	return DateTime(base.year, base.month, base.day, randomHour, 0);
	// }
  Future<DateTime> _anchor0900(DateTime base) async { 
    final now = DateTime.now();
    final realDues = await _fetchAllRealDues();

    final hourCounts = <int, int>{};
    for (int i = 0; i < 24; i++) hourCounts[i] = 0; // 0時から23時まで初期化

    for (final due in realDues) {
      hourCounts[due.hour] = (hourCounts[due.hour] ?? 0) + 1;
    }

    final hourProbabilities = _softmax(hourCounts);
    
    if (base.year == now.year && base.month == now.month && base.day == now.day) {
      
      final availableHourProbabilities = Map<int, double>.fromEntries(
        hourProbabilities.entries.where((entry) => 
          DateTime(base.year, base.month, base.day, entry.key, 0).isAfter(now)
        )
      );
      
      if (availableHourProbabilities.isNotEmpty) {

        final sumAvailableProb = availableHourProbabilities.values.fold(0.0, (p, e) => p + e);
        final renormalizedAvailableProb = sumAvailableProb > 0
          ? availableHourProbabilities.map((k, v) => MapEntry(k, v / sumAvailableProb))
          : availableHourProbabilities;
        
        final sampledHour = _sampleFromProbabilities(renormalizedAvailableProb);
        
        final sampledMinute = 0;

        return DateTime(base.year, base.month, base.day, sampledHour, sampledMinute);
      } else {
        // 使える時間がない場合: 今日の23時59分を返す
        return DateTime(base.year, base.month, base.day, 23, 59);
      }
    }
    
    // 4. baseの日付が未来（明日以降）の場合: 全ての時刻からサンプリング
    final sampledHour = _sampleFromProbabilities(hourProbabilities);
    // 分はランダム (現在は分の履歴を考慮せずに固定)
    final sampledMinute = 0; 

    return DateTime(base.year, base.month, base.day, sampledHour, sampledMinute);
  }
}