import 'dart:math';

import '../models/fe_question.dart';

/// Builds a 20-question Section B set matching the official 16:4 split.
class FeQuestionSelector {
  static const algorithmQuestionCount = 16;
  static const securityQuestionCount = 4;

  static List<FeQuestion> selectForReview(
    List<FeQuestion> questions,
    Map<String, List<bool>> history,
    Set<String> flaggedIds,
    {Set<String>? targetIds}
  ) {
    return questions.where((question) {
      if(targetIds!=null)return targetIds.contains(question.id);
      final attempts = history[question.id];
      return flaggedIds.contains(question.id) ||
          (attempts != null && attempts.isNotEmpty && !attempts.last);
    }).toList();
  }

  static List<FeQuestion> selectBExamSet(
    List<FeQuestion> questions, {
    Random? random,
  }) {
    final rng = random ?? Random();
    final algorithm = questions
        .where((q) => q.section == 'B' && q.domain == 'algorithm')
        .toList();
    final security = questions
        .where((q) => q.section == 'B' && q.domain == 'security')
        .toList();

    if (algorithm.length < algorithmQuestionCount ||
        security.length < securityQuestionCount) {
      throw StateError(
        '科目B模擬構成にはアルゴリズム16問、情報セキュリティ4問が必要です。',
      );
    }

    algorithm.shuffle(rng);
    security.shuffle(rng);
    final selected = [
      ...algorithm.take(algorithmQuestionCount),
      ...security.take(securityQuestionCount),
    ]..shuffle(rng);
    return selected;
  }
}
