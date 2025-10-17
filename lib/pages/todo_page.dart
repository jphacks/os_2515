import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/todo.dart';
import '../services/calendar_service.dart';
import '../services/fatigue_service.dart' as fatigue;
import '../services/frontload_scheduler.dart';
import '../services/todo_repository.dart';
import '../widgets/sign_in_button.dart';
import '../main.dart' show auth; // ← main.dart のグローバル auth を再利用

class TodoPage extends StatefulWidget {
  const TodoPage({super.key, required this.repo});
  final TodoRepository repo;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  late final CalendarService _calendar;
  late final TodoRepository _repo;
  late final FrontloadScheduler _frontload;

  @override
  void initState() {
    super.initState();

    // ★ テスト時のみ ON。テスト後は false に戻すのを忘れずに！
    fatigue.FatigueService.debugAlwaysFire = true;

    // 依存の初期化（auth は main.dart のグローバルを使う）
    _calendar = CalendarService(auth);
    _repo = TodoRepository(_calendar);
    _frontload = FrontloadScheduler(fatigue.FatigueService(), _repo, _calendar);

    // 初回フレーム後に実行：前倒し → （必要なら）実期限へ切替
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final changed = await _frontload.tickAndMaybeFrontload();
      if (mounted &&
          changed > 0 &&
          !fatigue.FatigueService.isQuietHour(DateTime.now())) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('疲労度により $changed 件の期限を前倒ししました')));
      }

      final switched = await _repo.switchOverdueToReal();
      if (mounted && switched > 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$switched 件を本当の期限へ更新しました')));
      }
    });
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
          stream: _repo.watchActive(),
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
            // 🔸データを取り出す（null安全）
            final todos = snap.data ?? const <Todo>[];
            if (todos.isEmpty) return const _EmptyState();
            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                // ===== アクティブ一覧 =====
                ...todos.map(
                  (t) => ListTile(
                    title: Text(t.title, style: const TextStyle()),
                    subtitle: Text(_daysLeftLabel(t)),
                    trailing: FilledButton.icon(
                      onPressed: () async {
                        // ← ここはあなたの “達成” ダイアログ＆complete() 呼び出しの中身をそのまま流用してください
                        // 例：
                        final ok =
                            await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('達成しますか？'),
                                content: Text('"${t.title}" を達成済みにします'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('キャンセル'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
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
                        final due = t.realDue ?? t.displayedDue ?? now;
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
      realDue:
          (data.due ??
          DateTime.now().add(const Duration(days: 7))), // 期限未指定なら仮で+7日
      bufferDays: 3, // 前倒しの既定日数（必要ならUIから渡す）
      syncToCalendar: data.syncCal,
    );
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
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(initial == null ? '新しいタスク' : 'タスクを編集'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: '例）レポート提出'),
                onSubmitted: (_) => Navigator.of(
                  context,
                ).pop(_EditData(titleCtrl.text, due, syncCal)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      due == null
                          ? '期限: なし'
                          : '期限: ' +
                                DateFormat('yyyy/MM/dd HH:mm').format(due!),
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(_EditData(titleCtrl.text, due, syncCal)),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
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
