import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/todo_repository.dart';
import 'services/calendar_service.dart';
import 'pages/home_tabs.dart';

final auth = AuthService();
final repo = TodoRepository(CalendarService(auth));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await auth.initialize();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: HomeTabs(repo: repo), // ← TodoPage 単体ではなく HomeTabs に
    ),
  );
}
