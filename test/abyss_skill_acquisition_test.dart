import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Store extends LocalStore {
 _Store(Directory dir):super(directory:dir);
 bool fail=false;
 Completer<void>? entered,gate;
 @override Future<void> save(AppStateData state) async {
  if(gate!=null){entered!.complete();await gate!.future;}
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}

void main(){
 const now=1700000000000;
 const parent=SkillDefinition(id:'skill:parent',name:'前提攻撃',kind:SkillKind.active,execution:ActiveSkillSpec(id:'skill:parent',name:'前提攻撃',powerPercent:1,physicalCost:1,cooldown:0));
 const target=SkillDefinition(id:'skill:target',name:'試験習得',kind:SkillKind.passive,acquisition:SkillAcquisition(playerLevel:2,clearedStage:1,prerequisiteId:'skill:parent',prerequisiteLevel:2,gold:100,magicCrystals:5));
 const paid=SkillDefinition(id:'skill:paid',name:'有料試験',kind:SkillKind.active,acquisition:SkillAcquisition(gold:100,magicCrystals:5));
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 test('全条件を満たす場合のみ習得し、通貨と変更番号を一度だけ変更',(){
  final catalog=SkillCatalog(const [parent,target]);
  final w=WorldState(gold:100,magicCrystals:5);
  final s=SkillState();
  void reject(int level){
   final before=jsonEncode([w.toJson(),s.toJson()]);
   expect(catalog.learnUnavailable(w,s,target.id,playerLevel:level),isNotNull);
   expect(()=>catalog.learn(w,s,target.id,playerLevel:level),throwsStateError);
   expect(jsonEncode([w.toJson(),s.toJson()]),before);
  }
  reject(1);reject(2);
  w.cleared.add('p01_main');
  reject(2);
  catalog.learn(w,s,parent.id);
  reject(2);
  final ready=SkillState.fromJson({...s.toJson(),'learned':{parent.id:10}});
  w.gold=99;
  expect(catalog.learnUnavailable(w,ready,target.id,playerLevel:2),'ゴールド不足');
  w.gold=100;w.magicCrystals=4;
  expect(catalog.learnUnavailable(w,ready,target.id,playerLevel:2),'魔晶石不足');
  final before=jsonEncode([w.toJson(),ready.toJson()]);
  expect(()=>catalog.learn(w,ready,target.id,playerLevel:2),throwsStateError);
  expect(jsonEncode([w.toJson(),ready.toJson()]),before);
  w.magicCrystals=5;
  expect(catalog.learnUnavailable(w,ready,target.id,playerLevel:2),isNull);
  catalog.learn(w,ready,target.id,playerLevel:2);
  expect(w.gold,0);expect(w.magicCrystals,0);
  expect(ready.learned[target.id],0);
  expect(ready.revision,2);
  expect(ready.passive,isEmpty);
  expect(()=>catalog.learn(w,ready,target.id,playerLevel:2),throwsStateError);
  expect(ready.revision,2);
 });
 test('不正条件・未知参照・循環参照・到達不能熟練度を拒否',(){
  SkillDefinition def(String id,SkillAcquisition rule)=>SkillDefinition(id:id,name:id,kind:SkillKind.active,acquisition:rule);
  for(final rule in const [
   SkillAcquisition(playerLevel:0),SkillAcquisition(clearedStage:-1),
   SkillAcquisition(clearedStage:999999),SkillAcquisition(gold:-1),
   SkillAcquisition(magicCrystals:1000001),SkillAcquisition(prerequisiteLevel:2),
   SkillAcquisition(prerequisiteId:'skill:unknown'),
   SkillAcquisition(prerequisiteId:'skill:a'),
   SkillAcquisition(prerequisiteId:'skill:parent',prerequisiteLevel:11),
  ]){
   expect(()=>SkillCatalog([parent,def('skill:a',rule)]),throwsFormatException);
  }
  expect(()=>SkillCatalog([def('skill:a',const SkillAcquisition(prerequisiteId:'skill:b')),def('skill:b',const SkillAcquisition(prerequisiteId:'skill:a'))]),throwsFormatException);
  expect(()=>SkillCatalog([def('skill:a',const SkillAcquisition(prerequisiteId:'skill:b',prerequisiteLevel:2)),def('skill:b',const SkillAcquisition())]),throwsFormatException);
 });
 test('戦闘中と変更番号上限の習得は非消費',(){
  final catalog=SkillCatalog(const [paid]);
  final w=WorldState(gold:100,magicCrystals:5),s=SkillState();
  final max=SkillState.fromJson({...s.toJson(),'revision':0x7fffffffffffffff});
  expect(()=>catalog.learn(w,max,paid.id),throwsStateError);
  expect(w.gold,100);expect(w.magicCrystals,5);expect(max.learned,isEmpty);
  WorldEngine().start(w,WorldStats.fromRanks(level:1,fitness:1,intelligence:1,discipline:1,creativity:1),'p01_main',now);
  final before=jsonEncode([w.toJson(),s.toJson()]);
  expect(()=>catalog.learn(w,s,paid.id),throwsStateError);
  expect(jsonEncode([w.toJson(),s.toJson()]),before);
 });
 test('実ファイル：遅延保存・失敗・再試行・二重要求・再起動・外部復元',() async{
  final dir=await Directory.systemTemp.createTemp('skill-acquisition-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir),catalog=SkillCatalog(const [paid]);
  final c=AppController(store,skillCatalog:catalog,portableBackup:PortableBackup(directory:dir),clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.gold=100;c.state.world.magicCrystals=5;
  await store.save(c.state);
  final initial=await c.exportPortableBackup(),generation=c.restoreGeneration;
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final bytes=await primary.readAsString(),before=jsonEncode(c.state.toJson());
  store.entered=Completer<void>();store.gate=Completer<void>();store.fail=true;
  final failed=expectLater(c.learnWorldSkill(paid.id,expectedGeneration:generation,expectedRevision:0),throwsStateError);
  await store.entered!.future;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  await expectLater(c.learnWorldSkill(paid.id,expectedGeneration:generation,expectedRevision:0),throwsStateError);
  store.gate!.complete();
  await failed;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.gate=null;store.fail=false;
  await c.learnWorldSkill(paid.id,expectedGeneration:generation,expectedRevision:0);
  expect(c.state.world.gold,0);expect(c.state.world.magicCrystals,0);
  expect(c.state.skills.learned[paid.id],0);expect(c.state.skills.revision,1);
  await expectLater(c.learnWorldSkill(paid.id,expectedGeneration:generation,expectedRevision:0),throwsStateError);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,portableBackup:PortableBackup(directory:dir),clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.gold,0);expect(restored.state.world.magicCrystals,0);
  expect(restored.state.skills.learned[paid.id],0);expect(restored.state.skills.revision,1);
  final oldGeneration=restored.restoreGeneration;
  await restored.importPortableBackup(initial);
  expect(restored.state.world.gold,100);expect(restored.state.world.magicCrystals,5);
  expect(restored.state.skills.learned,isEmpty);
  await expectLater(restored.learnWorldSkill(paid.id,expectedGeneration:oldGeneration,expectedRevision:0),throwsStateError);
  expect(restored.state.world.gold,100);
 });
}
