// // 修正後の HistoryPage（差し替え）
// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import '../models/todo.dart';
// import '../services/todo_repository.dart';

// class HistoryPage extends StatelessWidget {
//   const HistoryPage({super.key, required this.repo});

//   final TodoRepository repo;

//   @override
//   Widget build(BuildContext context) {
//     return StreamBuilder<List<Todo>>(
//       stream: repo.watchCompleted(),
//       builder: (context, snap) {
//         if (snap.hasError) {
//           return Center(
//             child: Padding(
//               padding: const EdgeInsets.all(16),
//               child: Text('履歴の取得に失敗: ${snap.error}'),
//             ),
//           );
//         }
//         if (snap.connectionState == ConnectionState.waiting) {
//           return const Center(child: CircularProgressIndicator());
//         }

//         final done = snap.data ?? const <Todo>[];
//         if (done.isEmpty) {
//           return const Center(child: Text('完了したタスクはまだありません'));
//         }

//         final totalLead = done.fold<int>(0, (sum, e) => sum + e.leadDays);

//         return ListView(
//           padding: const EdgeInsets.only(bottom: 24),
//           children: [
//             Padding(
//               padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
//               child: Text(
//                 '達成履歴（余裕日数 合計: $totalLead 日）',
//                 style: Theme.of(context).textTheme.titleMedium,
//               ),
//             ),
//             ...done.map(
//               (t) => ListTile(
//                 leading: const Icon(Icons.check_circle, color: Colors.green),
//                 title: Text(t.title),
//                 subtitle: Text(
//                   '余裕: ${t.leadDays}日 / 完了: '
//                   '${t.completedAt == null ? '---' : DateFormat('yyyy/MM/dd HH:mm').format(t.completedAt!)}',
//                 ),
//               ),
//             ),
//           ],
//         );
//       },
//     );
//   }
// }
