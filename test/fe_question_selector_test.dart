import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/models/fe_question.dart';
import 'package:level_me/services/fe_question_selector.dart';

void main() {
  FeQuestion question(String id, String section, String domain) => FeQuestion(
        id: id,
        section: section,
        domain: domain,
        stem: 'Question $id',
        options: const ['A', 'B', 'C', 'D'],
        answerIndex: 0,
        explanation: 'Explanation $id',
      );

  test('Section B exam set has 16 algorithm and 4 security questions', () {
    final pool = [
      for (var i = 0; i < 40; i++) question('a$i', 'B', 'algorithm'),
      for (var i = 0; i < 20; i++) question('s$i', 'B', 'security'),
      question('a-not-b', 'A', 'algorithm'),
      question('s-not-b', 'A', 'security'),
    ];

    final selected = FeQuestionSelector.selectBExamSet(pool, random: Random(7));

    expect(selected, hasLength(20));
    expect(selected.where((q) => q.domain == 'algorithm'), hasLength(16));
    expect(selected.where((q) => q.domain == 'security'), hasLength(4));
    expect(selected.every((q) => q.section == 'B'), isTrue);
    expect(selected.map((q) => q.id).toSet(), hasLength(20));
  });

  test('Section B exam set rejects a pool missing a required category', () {
    final pool = [
      for (var i = 0; i < 16; i++) question('a$i', 'B', 'algorithm'),
      for (var i = 0; i < 3; i++) question('s$i', 'B', 'security'),
    ];

    expect(
      () => FeQuestionSelector.selectBExamSet(pool, random: Random(1)),
      throwsA(isA<StateError>()),
    );
  });
}
