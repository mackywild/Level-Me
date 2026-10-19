import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/services/level_calculator.dart';
void main(){
 test('level one starts at 0 XP',(){
  final p=LevelCalculator.fromTotalExp(0);
  expect(p.level,1);expect(p.expToNextLevel,100);
 });
 test('100 EXP is level two',(){expect(LevelCalculator.fromTotalExp(100).level,2);});
 test('225 EXP is level three',(){expect(LevelCalculator.fromTotalExp(225).level,3);});
 test('attribute ranks',(){expect(LevelCalculator.statRankFromExp(100),2);});
}
