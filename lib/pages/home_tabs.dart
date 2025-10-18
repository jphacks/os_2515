import 'package:flutter/material.dart';
import '../services/todo_repository.dart';
import 'todo_page.dart';
// import 'history_page.dart';

class HomeTabs extends StatelessWidget {
  const HomeTabs({super.key, required this.repo});
  final TodoRepository repo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: TodoPage(repo: repo)),
    );
  }
}
