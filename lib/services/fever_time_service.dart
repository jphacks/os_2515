import 'dart:math';
import '../models/todo.dart';
import 'todo_repository.dart';
import 'calendar_service.dart';

/// フィーバー：displayedDue を「今週」に前倒しして詰める
/// - realDue は変更しない
/// - already overdue の扱いは repo 側の表示ロジックに準拠
/// - 時刻は 0/6/12/18 のいずれかに揃える（リポジトリのアンカー仕様と一致）
class FeverTimeService {
  FeverTimeService(this.repo, this.calendar);

  final TodoRepository repo;
  final CalendarService calendar;

  /// 0/6/12/18 時のアンカー（repo 側の `_anchor0900` に合わせる）
  static const List<int> _anchorHours = [0, 6, 12, 18];

  /// フィーバーを発火。
  /// - selectProb: 抽出確率
  /// - maxPerDay: 1日あたり上限（過密防止）
  /// - returns: 実際に前倒しできた件数
Future<int> trigger({
  DateTime? now,
  double selectProb = 1.0, // ← デモは全部前倒しの方が分かりやすいので 1.0 を既定に
  int maxPerDay = 4,
  bool syncCalendar = true,
}) async {
  final baseNow = now ?? DateTime.now();
  final today = DateTime(baseNow.year, baseNow.month, baseNow.day);

  // 今日〜7日
  final days = List<DateTime>.generate(7, (i) => today.add(Duration(days: i)));

  // 1) 候補取得
  final todos = await repo.listAll();

  // 2) 対象抽出：
  //   - active のみ（UIはactive=displayedDueを見るため、確実に動く）
  //   - 完了は除外
  //   - 有効日時 = displayedDue ?? realDue が「現在以降」にある
  //   - selectProb で抽選（既定は 1.0 = 全部）
  final rng = Random();
  final candidates = <Todo>[];
  for (final t in todos) {
    if (t.state != TodoState.active) continue;           // ★ active のみ
    if (t.completedAt != null) continue;

    final effective = t.displayedDue ?? t.realDue;
    if (effective == null) continue;
    if (effective.isBefore(baseNow)) continue;

    if (rng.nextDouble() <= selectProb) {
      candidates.add(t);
    }
  }
  if (candidates.isEmpty) return 0;

  // 3) 期日（effective）近い順で安定ソート
  candidates.sort((a, b) {
    final da = (a.displayedDue ?? a.realDue)!;
    final db = (b.displayedDue ?? b.realDue)!;
    final c = da.compareTo(db);
    return c != 0 ? c : a.id.compareTo(b.id);
  });

  // 4) 均等割り当て：ラウンドロビンで day0..6 を回す
  final perDayCount = List<int>.filled(7, 0);
  int applied = 0;
  int dayIndex = 0;

  for (final t in candidates) {
    // 空きのある日を探す（最大 7 回まで進める）
    int tries = 0;
    int picked = -1;
    while (tries < 7) {
      final d = (dayIndex + tries) % 7;
      if (perDayCount[d] < maxPerDay) {
        picked = d;
        break;
      }
      tries++;
    }
    if (picked == -1) break; // 全日上限に到達

    // 今日（picked==0）は「今より後のアンカー」を優先
    DateTime scheduled = _pickAnchoredDate(days[picked], baseNow, rng, sameDay: picked == 0);
    if (picked == 0 && scheduled.isBefore(baseNow)) {
      // 今日のアンカーが全て過ぎていた → 翌日に送る
      final next = (picked + 1 < 7) ? picked + 1 : picked;
      scheduled = _pickAnchoredDate(days[next], baseNow, rng, sameDay: false);
    }

    await repo.updateDisplayedDue(t.id, scheduled);

    if (syncCalendar && t.calendarEventId != null) {
      await calendar.updateEventStart(eventId: t.calendarEventId!, newStart: scheduled);
    }

    perDayCount[picked] += 1;
    applied += 1;

    // 次の候補は翌日に回す（= ラウンドロビン）
    dayIndex = (picked + 1) % 7;
  }

  return applied;
}


  /// d日目のアンカー時刻を選ぶ。
  /// sameDay=true のときは「現在時刻より後のアンカー」を優先して選ぶ。
  DateTime _pickAnchoredDate(DateTime day, DateTime now, Random rng, {required bool sameDay}) {
    // 0/6/12/18 の候補
    final anchors = List<int>.from(_anchorHours);

    if (sameDay) {
      // 今より後のアンカーだけに絞る。無ければいったん最終（18時）を選ぶ（呼び元で翌日にずらす）
      anchors.removeWhere((h) {
        final dt = DateTime(day.year, day.month, day.day, h);
        return dt.isBefore(now);
      });
      if (anchors.isEmpty) {
        return DateTime(day.year, day.month, day.day, 18);
      }
    }

    final hour = anchors[rng.nextInt(anchors.length)];
    // 同日内の密集を少し散らす（±60分 / 30分刻み）
    final offsetMin = (rng.nextInt(5) - 2) * 30;
    return DateTime(day.year, day.month, day.day, hour).add(Duration(minutes: offsetMin));
  }


  // ===== internal helpers =====

  // Future<List<Todo>> _safeListAll() async {
  //   // あなたのリポジトリにある “全部/アクティブだけ” を返す読み出しに置換してください。
  //   // 例:
  //   // return await repo.listAll();
  //   // もし listAll が無い場合は、watch 系の生実装を使って一度だけ取ってくる読み出しを
  //   // 既存 repo に小さく足すのが一番安全です。
  //   return await repo.listAll();
  // }

  // Future<void> _updateDisplayedDue(Todo t, DateTime newDisplayed) async {
  //   await repo.updateDisplayedDue(t.id, newDisplayed);
  // }
}
