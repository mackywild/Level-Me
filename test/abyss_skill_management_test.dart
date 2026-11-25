import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/screens/abyss_skill_screen.dart';

void main(){
 const now=1700000000000;
 const def=SkillDefinition(id:'skill:test',name:'試験スキル',kind:SkillKind.active);
 final catalog=SkillCatalog(const [def]);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 test('変更番号の旧形式・不正値・上限と熟練度予約値を検証',(){
  final raw=SkillState().toJson();
  expect(SkillState.fromJson(Map<String,dynamic>.of(raw)..remove('revision')).revision,0);
  for(final bad in [null,-1,0.0,'0']){
   expect(()=>SkillState.fromJson({...raw,'revision':bad}),throwsFormatException);
  }
  expect(()=>SkillState.fromJson({...raw,'learned':{def.id:1}}),throwsFormatException);
  for(final bad in [null,[],1]){
   expect(()=>AppStateData.fromJson({...AppStateData.initial().toJson(),'skills':bad}),throwsFormatException);
  }
  final s=SkillState.fromJson({...raw,'revision':0x7fffffffffffffff});
  final before=jsonEncode(s.toJson());
  expect(()=>catalog.learn(WorldState(),s,def.id),throwsStateError);
  expect(jsonEncode(s.toJson()),before);
 });
 test('候補42種を検証するが公開せず、不正候補と有効化を拒否',(){
  Map<String,dynamic> root()=>jsonDecode(File(AbyssMaster.assetPath).readAsStringSync()) as Map<String,dynamic>;
  final j=root(),rows=j['skills'] as List;
  expect(rows.length,42);
  expect(rows.where((r)=>r['kind']=='passive').length,6);
  expect(AbyssMaster.fromJson(jsonEncode(j)).skills.definitions,isEmpty);
  j['enabled']=true;
  expect(AbyssMaster.fromJson(jsonEncode(j)).skills.definitions,isEmpty);
  for(final change in <void Function(Map<String,dynamic>)>[
   (j){j['skillEnabled']=true;},
   (j){j['skillEnabled']=null;},
   (j){j['skills']=null;},
   (j){(j['skills'] as List).add((j['skills'] as List).first);},
   (j){(j['skills'] as List).first['kind']='passive';},
   (j){(j['skills'] as List).first['family']='unknown';},
   (j){(j['skills'] as List).first['id']='item:invalid';},
  ]){
   final bad=root();change(bad);
   expect(()=>AbyssMaster.fromJson(jsonEncode(bad)),throwsFormatException);
  }
 });
 test('同一世代の装着解除再装着後にも旧要求を拒否する',() async{
  final dir=await Directory.systemTemp.createTemp('skill-revision-');
  addTearDown(()=>dir.delete(recursive:true));
  final c=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(def.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(def.id,expectedGeneration:gen,expectedRevision:1);
  await c.unequipWorldSkill(def.id,expectedGeneration:gen,expectedRevision:2);
  await c.equipWorldSkill(def.id,expectedGeneration:gen,expectedRevision:3);
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final bytes=await primary.readAsString();
  await expectLater(c.unequipWorldSkill(def.id,expectedGeneration:gen,expectedRevision:2),throwsStateError);
  expect(c.state.skills.revision,4);
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.skills.revision,4);
  expect(restored.state.skills.active,[def.id]);
 });
 testWidgets('習得確認取消と確定、装着可能表示',(tester) async{
  final dir=await Directory.systemTemp.createTemp('skill-ui-');
  addTearDown(()=>dir.delete(recursive:true));
  final c=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  await tester.pumpWidget(MaterialApp(home:AbyssSkillScreen(controller:c)));
  // 下部の候補までスクロールする。
  final target=find.byKey(const ValueKey('skill-skill:test'));
  await tester.scrollUntilVisible(target,250,scrollable:find.byType(Scrollable).first);
  await tester.tap(target);await tester.pumpAndSettle();
  await tester.tap(find.text('キャンセル'));await tester.pumpAndSettle();
  expect(c.state.skills.revision,0);
  await tester.tap(target);await tester.pumpAndSettle();
  await tester.tap(find.text('確定'));
  await tester.runAsync(() async{
   for(var i=0;i<200&&c.inventoryBusy;i++){await Future<void>.delayed(const Duration(milliseconds:10));}
   expect(c.inventoryBusy,false);
  });
  await tester.pumpAndSettle();
  expect(c.state.skills.learned.containsKey(def.id),true);
  expect(c.state.skills.revision,1);
  expect(find.text('装着'),findsOneWidget);
 });
}
