import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService();

  // Firebase コンソールの「ウェブ クライアント ID」に置き換える
  static const _webClientId =
      '993398968251-41fmqpbm8rl02du84nu3rr7sd7f2lj28.apps.googleusercontent.com';

  final _auth = FirebaseAuth.instance;

  bool _initialized = false;

  /// 起動時に一度だけ
  /// 起動時に一度だけ呼べばOK。呼び忘れがあっても _ensureInitialized() で保険をかける。
  Future<void> initialize() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    // 可能ならサイレント認証（失敗しても気にしない）
    unawaited(GoogleSignIn.instance.attemptLightweightAuthentication());
    _initialized = true;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await initialize();
  }

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// 「Googleでサインイン」ボタン
  Future<UserCredential> signInWithGoogle() async {
    await _ensureInitialized(); // ★未初期化ならここで初期化
    // v7: authenticate() でアカウント選択 UI
    final account = await GoogleSignIn.instance.authenticate();

    // Firebase 用の idToken を取得（serverClientId を設定していないと null になりがち）
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw Exception('Failed to get Google ID token');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  /// Google Calendar API を叩くときの認証ヘッダを取得
  /// （必要ならこの時点で追加スコープの同意画面が出る）
  Future<Map<String, String>> calendarAuthHeaders() async {
    const scopes = <String>['https://www.googleapis.com/auth/calendar.events'];

    final headers = await GoogleSignIn.instance.authorizationClient
        .authorizationHeaders(scopes, promptIfNecessary: true);

    if (headers == null || headers.isEmpty) {
      throw Exception('Authorization failed or cancelled');
    }
    return headers;
  }
}
