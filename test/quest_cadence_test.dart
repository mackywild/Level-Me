import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/models/app_state.dart';
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
 test('review question IDs survive quest persistence and completion',(){
  final created=DateTime(2026,10,22);
  final q=Quest(id:'review',title:'FE review',createdAt:created,
   rewards:const [QuestReward(stat:StatType.intelligence,exp:10)],
   reviewQuestionIds:const ['FE-A-0001','FE-B-0001']);
  final restored=Quest.fromJson(q.toJson()).completed(created);
  expect(restored.reviewQuestionIds,['FE-A-0001','FE-B-0001']);
  expect(restored.isDoneAt(created),true);
 });
 test('old saved quests load without review question metadata',(){
  final q=Quest.fromJson({
   'id':'old','title':'Old quest','rewards':[{'stat':'intelligence','exp':10}],
   'createdAt':'2026-10-22T00:00:00.000','completedAt':null,
  });
  expect(q.reviewQuestionIds,isEmpty);
 });
 test('default daily study quest is the FE study task',(){
  final quest=AppStateData.initial().quests.first;
  expect(quest.id,'starter-study');
  expect(quest.title,'基本情報技術者の勉強をする');
  expect(quest.cadence,QuestCadence.daily);
 });
 test('boss defeat restores HP and increments counter',(){
  const b=Boss(id:'1',title:'Boss',description:'Test',maxHp:100,hp:20,rewardExp:50,defeats:0);
  final next=b.damage(20);
  expect(next.hp,100);expect(next.defeats,1);
 });
}
