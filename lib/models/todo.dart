// lib/models/todo.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// タスクの状態
enum TodoState {
  /// 表示用の前倒し期限（displayedDue）で運用中
  active,

  /// 表示用期限を過ぎ、本当の期限（realDue）で運用中
  switchedToReal,

  /// 完了（履歴）
  completed,
}

class Todo {
  final String id;
  final String title;

  /// 表示用の“前倒し期限”。ユーザーに見せる/通知するのは原則こちら。
  final DateTime? displayedDue;

  /// 本当の期限。UIには原則出さない（未達確定後だけUI/カレンダー反映）。
  final DateTime? realDue;

  /// GoogleカレンダーのイベントID（同期時に利用）
  final String? calendarEventId;

  /// 状態
  final TodoState state;

  /// 完了日時（completed 時にセット）
  final DateTime? completedAt;

  /// 表示用→本当の期限へ切り替えた日時（switchedToReal 時にセット）
  final DateTime? switchedAt;

  /// 何日早く終えたか（完了確定時に保存：実期限 - 完了日時 を切り上げ）
  /// 0 未満（遅れた）は 0 として扱う運用を想定
  final int leadDays;

  /// 作成・更新
  final DateTime createdAt;
  final DateTime updatedAt;

  const Todo({
    required this.id,
    required this.title,
    required this.displayedDue,
    required this.realDue,
    required this.calendarEventId,
    required this.state,
    required this.completedAt,
    required this.switchedAt,
    required this.leadDays,
    required this.createdAt,
    required this.updatedAt,
  });

  /// UI表示で使う“現在の期限っぽいもの”
  /// - active: displayedDue
  /// - switchedToReal: realDue
  /// - completed: completedAt（残日数ではなく完了時刻）
  DateTime? get currentDueLike {
    switch (state) {
      case TodoState.active:
        return displayedDue;
      case TodoState.switchedToReal:
        return realDue;
      case TodoState.completed:
        return completedAt;
    }
  }

  /// 便利：アクティブ系か？
  bool get isActiveLike =>
      state == TodoState.active || state == TodoState.switchedToReal;

  /// Firestore → Model（既存データ: done/due のみでも吸収）
  factory Todo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? const <String, dynamic>{};

    // 後方互換：古いスキーマ（done/due）
    final bool? legacyDone = map['done'] as bool?;
    final Timestamp? legacyDueTs = map['due'] as Timestamp?;
    final DateTime? legacyDue = legacyDueTs?.toDate();

    final String stateStr =
        (map['state'] as String?) ??
        (legacyDone == true ? 'completed' : 'active');

    final TodoState state = switch (stateStr) {
      'active' => TodoState.active,
      'switchedToReal' => TodoState.switchedToReal,
      'completed' => TodoState.completed,
      _ => TodoState.active,
    };

    return Todo(
      id: doc.id,
      title: (map['title'] as String?) ?? '',
      displayedDue: (map['displayedDue'] as Timestamp?)?.toDate() ?? legacyDue,
      realDue: (map['realDue'] as Timestamp?)?.toDate() ?? legacyDue,
      calendarEventId: map['calendarEventId'] as String?,
      state: state,
      completedAt: (map['completedAt'] as Timestamp?)?.toDate(),
      switchedAt: (map['switchedAt'] as Timestamp?)?.toDate(),
      leadDays: (map['leadDays'] as int?) ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Model → Firestore
  Map<String, dynamic> toMap() => {
    'title': title,
    'displayedDue': displayedDue == null
        ? null
        : Timestamp.fromDate(displayedDue!),
    'realDue': realDue == null ? null : Timestamp.fromDate(realDue!),
    'calendarEventId': calendarEventId,
    'state': switch (state) {
      TodoState.active => 'active',
      TodoState.switchedToReal => 'switchedToReal',
      TodoState.completed => 'completed',
    },
    'completedAt': completedAt == null
        ? null
        : Timestamp.fromDate(completedAt!),
    'switchedAt': switchedAt == null ? null : Timestamp.fromDate(switchedAt!),
    'leadDays': leadDays,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  /// 部分更新に便利
  Todo copyWith({
    String? id,
    String? title,
    DateTime? displayedDue,
    DateTime? realDue,
    String? calendarEventId,
    TodoState? state,
    DateTime? completedAt,
    DateTime? switchedAt,
    int? leadDays,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Todo(
      id: id ?? this.id,
      title: title ?? this.title,
      displayedDue: displayedDue ?? this.displayedDue,
      realDue: realDue ?? this.realDue,
      calendarEventId: calendarEventId ?? this.calendarEventId,
      state: state ?? this.state,
      completedAt: completedAt ?? this.completedAt,
      switchedAt: switchedAt ?? this.switchedAt,
      leadDays: leadDays ?? this.leadDays,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// “あとX日”用のヘルパ（切り上げ。負は0）
  static int daysLeftCeil(DateTime from, DateTime to) {
    final diffMinutes = to.difference(from).inMinutes;
    final days = diffMinutes / (60 * 24);
    final ceil = days.ceil();
    return ceil < 0 ? 0 : ceil;
  }

  /// 完了時の “何日早かったか” を算出（負は0）
  static int earlyDaysOnComplete({
    required DateTime realDue,
    required DateTime completedAt,
  }) {
    final diffMinutes = realDue.difference(completedAt).inMinutes;
    final days = (diffMinutes / (60 * 24)).ceil();
    return days < 0 ? 0 : days;
  }
}
