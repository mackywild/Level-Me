import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/models/stat_type.dart';
import 'package:level_me/models/quest.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/world_engine.dart';

class MemoryStore extends LocalStore {
 String? data;
 bool fail=false;
 @override Future<AppStateData> load() async=>data==null?AppStateData.initial():AppStateData.fromJson(jsonDecode(data!) as Map<String,dynamic>);
 @override Future<void> save(AppStateData state) async {
  if(fail)throw StateError('simulated disk failure');
  data=jsonEncode(state.toJson());
 }
}
void main(){
 late MemoryStore store;
 late AppController controller;
 setUp(() async {store=MemoryStore();controller=AppController(store);await controller.initialize();});
 tearDown(()=>controller.dispose());
 test('25 minutes preserves baseline and duplicate claim only records time',() async {
  final q=controller.state.quests.first;
  await controller.completeQuest(q,activeSeconds:1500);
  expect(controller.state.stats[StatType.intelligence],20);
  final exp=controller.state.totalExp;
  await controller.completeQuest(q,activeSeconds:1500);
  expect(controller.state.totalExp,exp);
  expect(controller.state.sessionHistory.length,2);
  expect(controller.state.sessionHistory.last['rewarded'],false);
 });
 test('failure restores state and allows retry',() async {
  final q=controller.state.quests.first;
  store.fail=true;
  await expectLater(controller.completeQuest(q,activeSeconds:1500),throwsStateError);
  expect(controller.state.totalExp,0);
  expect(controller.state.completionCount,0);
  expect(controller.state.sessionHistory,isEmpty);
  store.fail=false;
  await controller.completeQuest(q,activeSeconds:1500);
  expect(controller.state.completionCount,1);
 });
 test('session survives reload and is cleared on finish',() async {
  final q=controller.state.quests.first;
  await controller.saveSession(q.id,{'seconds':120,'incorrect':['A1']});
  final restored=AppController(store);
  await restored.initialize();
  expect(restored.sessionFor(q.id)?['seconds'],120);
  await restored.completeQuest(q,activeSeconds:120,reviewIds:['A1']);
  expect(restored.sessionFor(q.id),isNull);
  expect(restored.state.quests.where((q)=>q.reviewQuestionIds.contains('A1')).length,1);
  restored.dispose();
 });
 test('timed quest rejects instant completion',() async {
  await expectLater(controller.completeQuest(controller.state.quests.first),throwsArgumentError);
  expect(controller.state.completionCount,0);
 });
 test('quest editing and archiving preserve awarded EXP and completion',() async {
  await controller.addQuest(title:'Project',cadence:QuestCadence.daily,rewards:const [QuestReward(stat:StatType.creativity,exp:20),QuestReward(stat:StatType.intelligence,exp:10)]);
  final q=controller.state.quests.first;
  await controller.completeQuest(q);
  final exp=controller.state.totalExp;
  await controller.editQuest(q.id,title:'Project revised',cadence:QuestCadence.daily,rewards:const [QuestReward(stat:StatType.creativity,exp:30)]);
  expect(controller.state.quests.first.isCompleted,true);
  await controller.archiveQuest(q.id);
  expect(controller.state.quests.first.archived,true);
  await expectLater(controller.completeQuest(q),throwsStateError);
  await controller.restoreQuest(q.id);
  expect(controller.state.quests.first.archived,false);
  await controller.completeQuest(q);
  expect(controller.state.totalExp,exp);
 });
 test('cadence cannot change after claim',() async {
  await controller.addQuest(title:'Daily',cadence:QuestCadence.daily,rewards:const [QuestReward(stat:StatType.social,exp:10)]);
  final q=controller.state.quests.first;
  await controller.completeQuest(q);
  await expectLater(controller.editQuest(q.id,title:q.title,rewards:q.rewards,cadence:QuestCadence.oneTime),throwsStateError);
 });
 test('starter quests cannot be archived',() async {
  await expectLater(controller.archiveQuest('starter-study'),throwsStateError);
 });
 test('legacy state accepts missing session fields',(){
  final json=AppStateData.initial().toJson()..remove('sessions')..remove('sessionHistory');
  final restored=AppStateData.fromJson(json);
  expect(restored.sessions,isEmpty);
  expect(restored.sessionHistory,isEmpty);
 });
 test('world victory persists rewards without granting daily EXP',() async {
  final exp=controller.state.totalExp;
  await controller.startWorldBattle('p01_main');
  final battle=controller.state.world.battle!;
  await controller.worldCommand(WorldCommand.claw,battle.id,battle.turn);
  expect(controller.state.world.cleared,contains('p01_main'));
  expect(controller.state.world.summonTickets,3);
  expect(controller.state.totalExp,exp);
  await expectLater(controller.worldCommand(WorldCommand.claw,battle.id,1),throwsStateError);
  final restored=AppController(store);
  await restored.initialize();
  expect(restored.state.world.summonTickets,3);
  expect(restored.state.totalExp,exp);
  restored.dispose();
 });
 test('failed world save rolls back battle turn and currency',() async {
  await controller.startWorldBattle('p01_main');
  final battle=controller.state.world.battle!;
  store.fail=true;
  await expectLater(controller.worldCommand(WorldCommand.claw,battle.id,battle.turn),throwsStateError);
  expect(controller.state.world.battle!.enemyHp,10);
  expect(controller.state.world.battle!.turn,1);
  expect(controller.state.world.gold,0);
  expect(controller.state.world.cleared,isEmpty);
  store.fail=false;
  await controller.worldCommand(WorldCommand.claw,battle.id,1);
  expect(controller.state.world.gold,40);
 });
}
