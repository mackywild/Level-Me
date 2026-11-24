import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/models/stat_type.dart';
import 'package:level_me/services/local_store.dart';

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
 test('legacy state accepts missing session fields',(){
  final json=AppStateData.initial().toJson()..remove('sessions')..remove('sessionHistory');
  final restored=AppStateData.fromJson(json);
  expect(restored.sessions,isEmpty);
  expect(restored.sessionHistory,isEmpty);
 });
}
