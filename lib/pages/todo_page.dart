import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/todo.dart';
import '../services/calendar_service.dart';
import '../services/fatigue_service.dart' as fatigue;
// import '../services/frontload_scheduler.dart';
import '../services/todo_repository.dart';
import '../widgets/sign_in_button.dart';
import '../main.dart' show auth; // ← main.dart のグローバル auth を再利用
import 'package:table_calendar/table_calendar.dart';
import '../services/notification_service.dart';

class TodoPage extends StatefulWidget {
  const TodoPage({super.key, required this.repo});
  final TodoRepository repo;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  late final CalendarService _calendar;
  late final TodoRepository _repo;
  //late final FrontloadScheduler _frontload;

  @override
  void initState() {
    super.initState();

    // ★ テスト時のみ ON。テスト後は false に戻すのを忘れずに！
    fatigue.FatigueService.debugAlwaysFire = true;

    // 依存の初期化（auth は main.dart のグローバルを使う）
    _calendar = CalendarService(auth);
    _repo = TodoRepository(_calendar);
    // _frontload = FrontloadScheduler(fatigue.FatigueService(), _repo, _calendar);

    //初回フレーム後に実行：前倒し → （必要なら）実期限へ切替
    // WidgetsBinding.instance.addPostFrameCallback((_) async {
    //   final changed = await _frontload.tickAndMaybeFrontload();
    //   if (mounted &&
    //       changed > 0 &&
    //       !fatigue.FatigueService.isQuietHour(DateTime.now())) {
    // ScaffoldMessenger.of(
    //   context,
    // ).showSnackBar(SnackBar(content: Text('疲労度により $changed 件の期限を前倒ししました')));
    // }

    // final switched = await _repo.switchOverdueToReal();
    // if (mounted && switched > 0) {
    // ScaffoldMessenger.of(
    //   context,
    // ).showSnackBar(SnackBar(content: Text('$switched 件を本当の期限へ更新しました')));
    //     }
    //   });
  }

  @override
  Widget build(BuildContext context) {
    return SignInGate(
      auth: auth,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leeway'),
          actions: [
            // Button(
            //   tooltip: 'カレンダーから取り込み',
            //   icon: const Icon(Icons.download_outlined),
            //   onPressed: () async {
            //     final now = DateTime.now();
            //     final from = now.subtract(const Duration(days: 7));
            //     final to = now.add(const Duration(days: 30));
            //     final count = await _repo.importFromCalendar(from, to);
            //     if (!context.mounted) return;
            //     ScaffoldMessenger.of(
            //       context,
            //     ).showSnackBar(SnackBar(content: Text('$count 件取り込みました')));
            //   },
            // ),
            // IconButton(
            //   tooltip: 'サインアウト',
            //   icon: const Icon(Icons.logout),
            //   onPressed: () => auth.signOut(),
            // ),
          ],
        ),
        body: StreamBuilder<List<Todo>>(
          stream: _repo.watchAll(),
          builder: (context, snap) {
            // 🔸エラーが出ていたら画面に表示（原因が分かる）
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('読み込みに失敗: ${snap.error}'),
                ),
              );
            }

            // 🔸最初の接続中だけローディング表示
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            // 🔸データを取り出す（全件：active / switchedToReal / completed）
            final all = snap.data ?? const <Todo>[];

            // ✅ タスクが0件でもカレンダーは常に表示する
            //    → 下段リストだけ空表示にする
            final showEmptyList = all.isEmpty;

            // 🔸 カレンダー（日別集計）は“全件”で作る（達成もライトグリーンで残す）

            final Map<DateTime, List<Todo>> byDay = {};
            for (final t in all) {
              DateTime? effective; // ← この“effective”がカレンダーの基準日
              switch (t.state) {
                case TodoState.active:
                  effective = t.displayedDue; // 前倒し中は前倒し期限
                  break;
                case TodoState.switchedToReal:
                  effective = t.realDue; // 実期限へ切替後は実期限
                  break;
                case TodoState.completed:
                  effective =
                      t.displayedDue ?? t.displayedDue; // 達成済みも期限のマスにライトグリーンで残す
                  break;
              }
              if (effective == null) continue;
              final key = DateTime(
                effective.year,
                effective.month,
                effective.day,
              );
              (byDay[key] ??= <Todo>[]).add(t);
            }

            // 🔸 下段リストは「未完了のみ」を表示（期限が迫っている順）
            final listTodos =
                [
                  for (final t in all)
                    if (t.state != TodoState.completed) t,
                ]..sort((a, b) {
                  DateTime? da = switch (a.state) {
                    TodoState.active => a.displayedDue,
                    TodoState.switchedToReal => a.realDue,
                    _ => null,
                  };
                  DateTime? db = switch (b.state) {
                    TodoState.active => b.displayedDue,
                    TodoState.switchedToReal => b.realDue,
                    _ => null,
                  };
                  if (da == null && db == null) return 0;
                  if (da == null) return 1; // 期限なしは後ろ
                  if (db == null) return -1;
                  return da.compareTo(db); // 早いほうを先に
                });

            // 🔸 上半分にカレンダー、下半分にリストを表示
            return Column(
              children: [
                // 🗓 上半分：カレンダー表示
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.45,
                  child: TableCalendar(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: DateTime.now(),
                    calendarFormat: CalendarFormat.month, // ← 月表示に固定
                    availableCalendarFormats: const {
                      CalendarFormat.month: 'Month', // ← 1種類にすればボタンが消える
                    },
                    eventLoader: (day) {
                      final d = DateTime(day.year, day.month, day.day);
                      return byDay[d] ?? [];
                    },
                    calendarStyle: const CalendarStyle(
                      todayDecoration: BoxDecoration(
                        color: Colors.blueAccent,
                        shape: BoxShape.circle,
                      ),
                      markerDecoration: BoxDecoration(
                        color: Colors.deepOrange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    calendarBuilders: CalendarBuilders(
                      // その日のタスクぶん「●」を並べて表示
                      // active / switchedToReal = 赤, completed = ライトグリーン
                      markerBuilder: (context, day, events) {
                        if (events.isEmpty) return const SizedBox.shrink();
                        final items = events.cast<Todo>();
                        return Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Wrap(
                              spacing: 2,
                              runSpacing: 2,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final t in items.take(6)) // 多すぎる日は最大6個まで
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: switch (t.state) {
                                        TodoState.completed =>
                                          Colors.lightGreen, // ✅ ライトグリーン
                                        _ => Colors.redAccent, // それ以外は赤
                                      },
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                const Divider(height: 1),

                // 🗒 下半分：タスクリスト(未完了のみ)
                Expanded(
                  child: showEmptyList
                      ? const _EmptyState()
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 96),
                          children: [
                            ...listTodos.map(
                              (t) => ListTile(
                                title: Text(t.title, style: const TextStyle()),
                                subtitle: Text(_daysLeftLabel(t)),
                                trailing: FilledButton.icon(
                                  onPressed: () async {
                                    final ok =
                                        await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title: const Text('達成しますか？'),
                                            content: Text(
                                              '"${t.title}" を達成済みにします',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, false),
                                                child: const Text('キャンセル'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, true),
                                                child: const Text('達成する'),
                                              ),
                                            ],
                                          ),
                                        ) ??
                                        false;
                                    if (!ok) return;

                                    await _repo.complete(t);
                                    if (!context.mounted) return;
                                    final now = DateTime.now();
                                    final due =
                                        t.realDue ?? t.displayedDue ?? now;
                                    final lead = Todo.earlyDaysOnComplete(
                                      realDue: due,
                                      completedAt: now,
                                    );

                                    await showDialog<void>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('🎉 Congratulation!'),
                                        content: Text(
                                          '「${t.title}」を達成！\n$lead 日の余裕をつくれました',
                                        ),
                                        actions: [
                                          FilledButton(
                                            onPressed: () => Navigator.pop(c),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.rocket_launch),
                                  label: const Text('達成'),
                                ),
                                onTap: () => _edit(t),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add),
          label: const Text('追加'),
        ),
      ),
    );
  }

  String _daysLeftLabel(Todo t) {
    final now = DateTime.now();
    final due = switch (t.state) {
      TodoState.active => t.displayedDue,
      TodoState.switchedToReal => t.realDue,
      TodoState.completed => t.completedAt, // ここは基本使わない
    };
    if (due == null) return '';
    final x = Todo.daysLeftCeil(now, due);
    return 'あと$x日（期限: ${DateFormat('yyyy/MM/dd').format(due)}）';
  }

  Future<void> _add() async {
    final data = await _showEditDialog();
    if (data == null || data.title.trim().isEmpty) return;
    await _repo.addTodo(
      title: data.title.trim(),
      realDue: data.due ?? DateTime.now().add(const Duration(days: 7)),
      bufferDays: 3, // 前倒しの既定日数（必要ならUIから渡す）
      syncToCalendar: data.syncCal,
    );

    const bool debugNotification = true; // ← あなたのフラグ

    // 2) 期限がある場合のみデモ通知
    if (debugNotification && data.due != null) {
      final daysLeft = _daysLeftFromNow(data.due!, DateTime.now());
      await NotificationService.instance.scheduleTaskReminderInSeconds(
        title: data.title.trim(),
        daysLeft: daysLeft,
        seconds: 5,
      );
    }
  }

  // 日数計算
  int _daysLeftFromNow(DateTime due, DateTime now) {
    final d0 = DateTime(now.year, now.month, now.day);
    final d1 = DateTime(due.year, due.month, due.day);
    return d1.difference(d0).inDays;
  }

  Future<void> _edit(Todo t) async {
    final data = await _showEditDialog(initial: t);
    if (data == null) return;
    // 同じ内容なら何もしない
    final newTitle = data.title.trim();
    final currentDue = t.realDue ?? t.displayedDue;
    final same = newTitle == t.title && data.due == currentDue;

    if (same) return;

    // いったん削除して作り直す（カレンダーも再同期）
    await _repo.addTodo(
      title: newTitle,
      realDue: (data.due ?? DateTime.now().add(const Duration(days: 7))),
      bufferDays: 3,
      syncToCalendar: data.syncCal,
    );
  }

  Future<_EditData?> _showEditDialog({Todo? initial}) async {
    final titleCtrl = TextEditingController(text: initial?.title ?? '');
    DateTime? due = initial == null
        ? null
        : (initial.realDue ?? initial.displayedDue);
    bool syncCal = initial?.calendarEventId != null;

    return showDialog<_EditData>(
      context: context,
      builder: (context) {
        final nav = Navigator.of(context); // ← 退避
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(initial == null ? '新しいタスク' : 'タスクを編集'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '例）レポート提出'),
                  onSubmitted: (_) =>
                      nav.pop(_EditData(titleCtrl.text, due, syncCal)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        due == null
                            ? '期限: なし'
                            : '期限: ${DateFormat('yyyy/MM/dd HH:mm').format(due!)}',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final date = await showDatePicker(
                          context: context,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 2),
                          initialDate: due ?? now,
                        );
                        if (date == null) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(due ?? now),
                        );
                        if (time == null) return;
                        setState(() {
                          due = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      },
                      icon: const Icon(Icons.event),
                      label: const Text('期限設定'),
                    ),
                  ],
                ),
                CheckboxListTile(
                  value: syncCal,
                  onChanged: (v) => setState(() => syncCal = v ?? false),
                  title: const Text('Google カレンダーに登録/更新する'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => nav.pop(),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () =>
                    nav.pop(_EditData(titleCtrl.text, due, syncCal)),
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditData {
  final String title;
  final DateTime? due;
  final bool syncCal;

  _EditData(this.title, this.due, this.syncCal);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.checklist, size: 64),
            const SizedBox(height: 12),
            Text('まだタスクがありません', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('右下の「追加」からタスクを作成しましょう。'),
          ],
        ),
      ),
    );
  }
}
