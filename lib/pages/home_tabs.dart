import 'package:flutter/material.dart';
import '../services/todo_repository.dart';
import 'todo_page.dart';
import 'history_page.dart';

class HomeTabs extends StatelessWidget {
  const HomeTabs({super.key, required this.repo});
  final TodoRepository repo;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leeway'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'タスク'),
              Tab(text: '履歴'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            TodoPage(repo: repo),
            HistoryPage(repo: repo),
          ],
        ),
      ),
    );
  }
}
