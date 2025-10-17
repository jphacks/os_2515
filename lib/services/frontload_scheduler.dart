// lib/services/frontload_scheduler.dart
import 'fatigue_service.dart';
import 'todo_repository.dart';
import 'calendar_service.dart';

class FrontloadScheduler {
  FrontloadScheduler(this._fatigue, this._repo, this._calendar);

  final FatigueService _fatigue;
  final TodoRepository _repo;
  final CalendarService _calendar;

  /// 1日複数回（起動時／ホーム復帰時など）呼ぶ
  /// 発火したら “その時点のアクティブタスク” を1日だけ前倒し
  Future<int> tickAndMaybeFrontload() async {
    final decision = await _fatigue.checkAndUpdate();
    if (!decision.shouldFire) return 0;

    final items = await _repo.fetchActiveOnce();
    int changed = 0;

    for (final t in items) {
      final nextDisplayed = await _repo.frontloadOneDay(t);
      if (nextDisplayed == null) continue; // スキップ
      changed++;

      // カレンダーの開始時刻も前倒し（09:00アンカー）
      if (t.calendarEventId != null) {
        final start = _anchor0900(nextDisplayed);
        await _calendar.updateEventStart(
          eventId: t.calendarEventId!,
          newStart: start,
          newEnd: start.add(const Duration(hours: 1)),
        );
      }
    }

    // 通知自体はUI/通知サービスに任せる（静かな時間帯は翌朝へ繰延など）
    return changed;
  }

  DateTime _anchor0900(DateTime base) =>
      DateTime(base.year, base.month, base.day, 9, 0);
}
