// lib/services/fatigue_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 疲労スコアのデータソース抽象
abstract class FatigueDataSource {
  /// 0.0〜1.0 の疲労スコアを返す（後で Google Fit / Health Connect 実装に差し替え）
  Future<double> readFatigueScore();
}

/// とりあえずの仮実装（固定値）
class DummyFatigueDataSource implements FatigueDataSource {
  @override
  Future<double> readFatigueScore() async => 0.62;
}

class FatigueService {
  /// テスト用：true にすると毎回 shouldFire=true を返す
  static bool debugAlwaysFire = false;

  FatigueService({FatigueDataSource? source})
    : _ds = source ?? DummyFatigueDataSource();

  final FatigueDataSource _ds;
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // チューニング用（Remote Configに逃がしてもOK）
  static const double alpha = 0.5; // EMA
  static const double tHigh = 0.60; // 発火しきい値
  static const double tLow = 0.45; // 再武装しきい値
  static const int quietStart = 23; // 23:00〜
  static const int quietEnd = 7; // 〜07:00
  static const int maxFrontloadDays = 5; // 最大前倒し日数
  static const Duration minRealDueGap = Duration(hours: 48); // 実締切48h以内は前倒し禁止

  DocumentReference<Map<String, dynamic>> _metaDoc(String uid) =>
      _db.collection('users').doc(uid).collection('system').doc('fatigue');

  static bool isQuietHour(DateTime now) {
    final h = now.hour;
    return (h >= quietStart) || (h < quietEnd);
  }

  /// 疲労スコア→EMA更新→ヒステリシス判定（★debugAlwaysFire を統合）
  Future<FatigueDecision> checkAndUpdate() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const FatigueDecision(shouldFire: false);
    }

    final now = DateTime.now();
    final metaRef = _metaDoc(uid);
    final snap = await metaRef.get();
    final data = snap.data() ?? {};

    // ★ 強制発火モード（テスト用）
    if (debugAlwaysFire) {
      await metaRef.set({
        'ema': 0.99,
        'armed': true,
        'firedTodayDate': '', // 連続発火できるように空にしておく
        'updatedAt': now.toIso8601String(),
      }, SetOptions(merge: true));
      return FatigueDecision(
        shouldFire: true,
        ema: 0.99,
        quiet: isQuietHour(now),
      );
    }

    final prevEma = (data['ema'] as num?)?.toDouble() ?? 0.5;
    final armed = (data['armed'] as bool?) ?? true;
    final firedTodayStr = data['firedTodayDate'] as String?;
    final firedToday = firedTodayStr == _yyyymmdd(now);

    final x = (await _ds.readFatigueScore()).clamp(0.0, 1.0);
    final ema = alpha * x + (1 - alpha) * prevEma;

    bool nextArmed = armed;
    bool shouldFire = false;

    if (armed && ema > tHigh) {
      shouldFire = !firedToday;
      nextArmed = false;
    } else if (!armed && ema < tLow) {
      nextArmed = true;
    }

    await metaRef.set({
      'ema': ema,
      'armed': nextArmed,
      'firedTodayDate': shouldFire ? _yyyymmdd(now) : (firedTodayStr ?? ''),
      'updatedAt': now.toIso8601String(),
    }, SetOptions(merge: true));

    return FatigueDecision(
      shouldFire: shouldFire,
      ema: ema,
      quiet: isQuietHour(now),
    );
  }

  static String _yyyymmdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}

class FatigueDecision {
  final bool shouldFire;
  final double? ema;
  final bool quiet;
  const FatigueDecision({
    required this.shouldFire,
    this.ema,
    this.quiet = false,
  });
}
