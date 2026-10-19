import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/models/quest.dart';
import 'package:level_me/models/stat_type.dart';
import 'package:level_me/models/boss.dart';
void main(){
 test('daily quest resets next day',(){
  final monday=DateTime(2026,10,19);
  final q=Quest(id:'1',title:'Study',createdAt:monday,
   rewards:const [QuestReward(stat:StatType.intelligence,exp:20)],
   cadence:QuestCadence.daily).completed(monday);
  expect(q.isDoneAt(monday),true);
  expect(q.isDoneAt(monday.add(const Duration(days:1))),false);
 });
 test('weekly quest resets on Monday',(){
  final monday=DateTime(2026,10,19);
  final q=Quest(id:'1',title:'Study',createdAt:monday,
   rewards:const [QuestReward(stat:StatType.intelligence,exp:20)],
   cadence:QuestCadence.weekly).completed(monday);
  expect(q.isDoneAt(monday.add(const Duration(days:6))),true);
  expect(q.isDoneAt(monday.add(const Duration(days:7))),false);
 });
 test('boss defeat restores HP and increments counter',(){
  const b=Boss(id:'1',title:'Boss',description:'Test',maxHp:100,hp:20,rewardExp:50,defeats:0);
  final next=b.damage(20);
  expect(next.hp,100);expect(next.defeats,1);
 });
}
