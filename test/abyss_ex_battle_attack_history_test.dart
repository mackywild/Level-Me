import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_ex_battle_attack.dart';

ExBattleAttack attack(int slot,{int uses=0,int lastCast=0,int cooldown=0,int initialCooldown=0})=>ExBattleAttack(
 slot:slot,instanceId:'eq_1',skillId:'equipment_ex_skill:test_$slot',level:7,
 attribute:ExAttackAttribute.physical,powerBps:10000,physicalCost:0,magicCost:0,
 hpCostBps:0,lifeDays:0,cooldown:cooldown,initialCooldown:initialCooldown,
 maxUses:null,energyDiscount:false,maxHpBps:null,uses:uses,lastCast:lastCast,
);

void main(){
 test('RV-229: 未使用枠のlastCast=0重複と成立履歴を許可、slot順を保持',(){
  final unused=[attack(0),attack(1),attack(2)];
  expect(ExBattleAttack.validate(unused,1),unused);
  final valid=[attack(2,uses:2,lastCast:4,cooldown:1),attack(0,uses:1,lastCast:1),attack(1)];
  expect(ExBattleAttack.validate(valid,5),valid);
  final boundary=[attack(0,uses:2,lastCast:2),attack(1,uses:2,lastCast:4)];
  expect(ExBattleAttack.validate(boundary,5),boundary);
 });
 test('RV-229: 異なる枠の同一発動turnを拒否',(){
  final duplicate=[attack(0,uses:1,lastCast:2),attack(1,uses:1,lastCast:2)];
  expect(()=>ExBattleAttack.validate(duplicate,3),throwsFormatException);
  expect(()=>ExBattleAttack.validate(duplicate.reversed,3),throwsFormatException);
 });
 test('RV-229: 全体回数が範囲内でも途中時点の累積回数超過を拒否',(){
  final impossible=[attack(0,uses:2,lastCast:2),attack(1,uses:2,lastCast:3)];
  expect(()=>ExBattleAttack.validate(impossible,5),throwsFormatException);
  expect(()=>ExBattleAttack.validate(impossible.reversed,10),throwsFormatException);
  final three=[attack(0,uses:1,lastCast:1),attack(1,uses:1,lastCast:2),attack(2,uses:2,lastCast:3)];
  expect(()=>ExBattleAttack.validate(three,5),throwsFormatException);
 });
 test('RV-229: 大きな整数の累積をBigIntで比較し旧個別CD制約も維持',(){
  const largest=0x7fffffffffffffff;
  final large=[attack(0,uses:largest-2,lastCast:largest-2),attack(1,uses:largest-1,lastCast:largest-1)];
  expect(()=>ExBattleAttack.validate(large,largest),throwsFormatException);
  expect(()=>ExBattleAttack.validate([attack(0,uses:2,lastCast:2,cooldown:1)],4),throwsFormatException);
  expect(()=>ExBattleAttack.validate([attack(0,uses:1,lastCast:1,initialCooldown:1)],3),throwsFormatException);
 });
}
