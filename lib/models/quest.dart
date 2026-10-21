import 'stat_type.dart';

enum QuestCadence { oneTime, daily, weekly }

class QuestReward {
  const QuestReward({required this.stat, required this.exp});
  final StatType stat;
  final int exp;
  Map<String, dynamic> toJson() => {'stat': stat.name, 'exp': exp};
  factory QuestReward.fromJson(Map<String, dynamic> json) => QuestReward(
    stat: StatType.values.byName(json['stat'] as String),
    exp: json['exp'] as int,
  );
}

class Quest {
  const Quest({required this.id, required this.title, required this.rewards,
    required this.createdAt, this.completedAt, this.cadence = QuestCadence.oneTime,
    this.completionKeys = const [], this.reviewQuestionIds = const []});
  final String id;
  final String title;
  final List<QuestReward> rewards;
  final DateTime createdAt;
  final DateTime? completedAt;
  final QuestCadence cadence;
  final List<String> completionKeys;
  final List<String> reviewQuestionIds;

  static String periodKey(QuestCadence cadence, DateTime time) {
    final date = DateTime(time.year, time.month, time.day);
    if (cadence == QuestCadence.weekly) {
      final monday = date.subtract(Duration(days: date.weekday - 1));
      return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
    }
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool isDoneAt(DateTime time) => cadence == QuestCadence.oneTime
      ? completedAt != null
      : completionKeys.contains(periodKey(cadence, time));

  bool get isCompleted => isDoneAt(DateTime.now());
  int get totalExp => rewards.fold(0, (sum, reward) => sum + reward.exp);

  Quest completed(DateTime now) => Quest(id: id, title: title, rewards: rewards,
    createdAt: createdAt, completedAt: cadence == QuestCadence.oneTime ? now : completedAt,
    cadence: cadence, completionKeys: cadence == QuestCadence.oneTime ? completionKeys :
      [...completionKeys, periodKey(cadence, now)], reviewQuestionIds: reviewQuestionIds);

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'rewards': rewards.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(), 'completedAt': completedAt?.toIso8601String(),
    'cadence': cadence.name, 'completionKeys': completionKeys,
    'reviewQuestionIds': reviewQuestionIds,
  };

  factory Quest.fromJson(Map<String, dynamic> json) => Quest(
    id: json['id'] as String, title: json['title'] as String,
    rewards: (json['rewards'] as List<dynamic>).map((e) => QuestReward.fromJson(e as Map<String, dynamic>)).toList(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    completedAt: json['completedAt'] == null ? null : DateTime.parse(json['completedAt'] as String),
    cadence: QuestCadence.values.firstWhere((e) => e.name == json['cadence'], orElse: () => QuestCadence.oneTime),
    completionKeys: (json['completionKeys'] as List<dynamic>? ?? []).cast<String>(),
    reviewQuestionIds: (json['reviewQuestionIds'] as List<dynamic>? ?? []).cast<String>(),
  );
}
