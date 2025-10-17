import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class SignInGate extends StatelessWidget {
  final Widget child;
  final AuthService auth;
  const SignInGate({super.key, required this.child, required this.auth});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snap) {
        // 通信中表示（お好みで）
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snap.data;
        if (user == null) {
          // ★ サインイン画面を Scaffold で包む
          return Scaffold(
            appBar: AppBar(title: const Text('Sign in')),
            body: Center(
              child: FilledButton.icon(
                onPressed: () async {
                  try {
                    await auth.signInWithGoogle();
                    if (!context.mounted) return; // ★ await 後の安全策
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('サインインしました')));
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sign-in failed: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.login),
                label: const Text('Google でサインイン'),
              ),
            ),
          );
        }

        // サインイン済みは通常の画面へ（child 側に Scaffold がある前提）
        return child;
      },
    );
  }
}
