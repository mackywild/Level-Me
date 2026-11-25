import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_awakening_candidate.dart';
import 'package:level_me/world/abyss_chrono_finisher_candidates.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/abyss_ultimate_candidate.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';
import 'helpers/extended_world_catalog.dart';

void main(){
 const now=1700000000000;
 const stats=WorldStats(hp:100,physical:2,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 const awakening=AwakeningSkillCandidate.definition;
 final combo=ChronoFinisherCandidates.definitions.last;
 const ultimate=UltimateSkillCandidate.definition;
 const parent=SkillDefinition(id:'skill:parent',name:'前提攻撃',kind:SkillKind.active,execution:ActiveSkillSpec(id:'skill:parent',name:'前提攻撃',powerPercent:100,physicalCost:1,cooldown:0));
 const child=SkillDefinition(id:'skill:child',name:'試験受動',kind:SkillKind.passive,acquisition:SkillAcquisition(clearedStage:3,prerequisiteId:'skill:parent',prerequisiteLevel:2,gold:100,magicCrystals:5));
 setUpAll(()=>loadExtendedWorldCatalog(21));
 WorldState world()=>WorldState(cleared:{'p03_main','p06_main','p12_main','p18_main'},hpAt:now,energyAt:now,lifespan:BigInt.from(1000));
 test('実装済み特殊IDの他効果への置換と未来視別IDを拒否',(){
  for(final id in ActiveSkillSpec.reservedEffects.keys){
   final invalid=ActiveSkillSpec(id:id,name:'不正',powerPercent:100,physicalCost:4,cooldown:0);
   expect(invalid.validate,throwsFormatException,reason:id);
   expect(()=>ActiveSkillSpec.fromJson(invalid.toJson()),throwsFormatException);
   expect(()=>SkillCatalog([SkillDefinition(id:id,name:'不正',kind:SkillKind.passive)]),throwsFormatException);
  }
  const invalid=ActiveSkillSpec(id:'skill:fake',name:'不正未来視',powerPercent:0,physicalCost:0,cooldown:5,effect:ActiveSkillEffect.foresight,lifeCost:14);
  expect(invalid.validate,throwsFormatException);
  expect(()=>SkillCatalog([SkillDefinition(id:invalid.id,name:invalid.name,kind:SkillKind.active,execution:invalid)]),throwsFormatException);
 });
 test('未解放の能動snapshotは戦闘開始前に拒否、複数STも全て必要',(){
  final engine=WorldEngine();
  for(final pair in [(awakening.execution!,12),(combo.execution!,6),(combo.execution!,12),(ultimate.execution!,18)]){
   final w=world()..cleared.remove(WorldCatalog.mainId(pair.$2));
   final before=jsonEncode(w.toJson());
   expect(()=>engine.start(w,stats,'p01_main',now,activeSkills:[pair.$1]),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
 });
 test('全保存版で非発動の装着能動も必要ST欠落を拒否',(){
  final engine=WorldEngine(),w=world();
  engine.start(w,stats,'p01_main',now,activeSkills:[awakening.execution!,combo.execution!,ultimate.execution!]);
  final v3=w.battle!.toJson(),v2={...v3,'executionVersion':2}..remove('activeRuleSnapshots');
  final v1={...v2,'executionVersion':1}..remove('encounterSnapshot');
  final legacy={...v1}..remove('executionVersion')..remove('lifeRewardPercent')..remove('lifeRewardBonuses');
  for(final battle in [v3,v2,v1,legacy]){
   expect(WorldState.fromJson({...w.toJson(),'battle':battle}).battle!.activeSkills.length,3);
   for(final stage in [6,12,18]){
    final cleared=w.cleared.where((id)=>id!=WorldCatalog.mainId(stage)).toList();
    expect(()=>WorldState.fromJson({...w.toJson(),'battle':battle,'cleared':cleared}),throwsFormatException);
   }
  }
 });
 test('習得済みのST・前提習得・熟練度を照合、支払済み通貨は再要求しない',(){
  final catalog=SkillCatalog(const [parent,child]),w=world();
  final valid=SkillState.fromJson({'version':2,'revision':4,'learned':{parent.id:10,child.id:0},'active':<String>[],'passive':[child.id]});
  catalog.validateProgress(w,valid);
  expect(w.gold,0);
  expect(w.magicCrystals,0);
  for(final learned in [{child.id:0},{parent.id:9,child.id:0}]){
   final invalid=SkillState.fromJson({...valid.toJson(),'learned':learned});
   expect(()=>catalog.validateProgress(w,invalid),throwsFormatException);
   expect(()=>catalog.validateBattle(w,invalid),throwsFormatException);
  }
  w.cleared.remove('p03_main');
  expect(()=>catalog.validateProgress(w,valid),throwsFormatException);
  final unequipped=SkillState.fromJson({...valid.toJson(),'passive':<String>[]});
  final before=jsonEncode(unequipped.toJson());
  expect(()=>catalog.equip(w,unequipped,child.id),throwsStateError);
  expect(jsonEncode(unequipped.toJson()),before);
  expect(()=>catalog.validateProgress(w,unequipped),throwsFormatException);
 });
 test('覚醒の残りCDから最短turnを検証し実際の経過は受理',(){
  final engine=WorldEngine(),w=world();
  engine.start(w,stats,'p01_main',now,activeSkills:[awakening.execution!]);
  final b=w.battle!;
  engine.actActiveSkill(w,awakening.id,b.id,1,now);
  for(var i=0;i<5;i++){
   final raw=b.toJson();
   expect(WorldBattle.fromJson(raw).awakeningTurns,b.awakeningTurns);
   expect(()=>WorldBattle.fromJson({...raw,'turn':b.turn-1}),throwsFormatException);
   engine.act(w,WorldCommand.guard,b.id,b.turn,now);
  }
  expect(b.awakeningTurns,0);
  expect(b.skillCooldowns,isEmpty);
  engine.actActiveSkill(w,awakening.id,b.id,b.turn,now);
  expect(WorldState.fromJson(w.toJson()).battle!.awakeningTurns,3);
 });
 test('実ファイル：未解放の習得・装着と戦闘snapshotを起動時拒否し原本を保持',() async{
  final dir=await Directory.systemTemp.createTemp('skill-unlock-save-');
  addTearDown(()=>dir.delete(recursive:true));
  final catalog=SkillCatalog(const [awakening]),store=LocalStore(directory:dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.add('p12_main');
  c.state.world.lifespan=BigInt.from(30);
  await store.save(c.state);
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(awakening.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(awakening.id,expectedGeneration:gen,expectedRevision:1);
  await c.startWorldBattle('p01_main');
  final primary=File('${dir.path}/${LocalStore.fileName}'),backup=File('${dir.path}/${LocalStore.fileName}.bak');
  final original=await primary.readAsString(),backupBytes=await backup.readAsString();
  final bad=jsonDecode(original) as Map<String,dynamic>;
  final badWorld=bad['world'] as Map<String,dynamic>;
  (badWorld['cleared'] as List).remove('p12_main');
  for(final battle in [badWorld['battle'],null]){
   badWorld['battle']=battle;
   final bytes=jsonEncode(bad);
   await primary.writeAsString(bytes,flush:true);
   final rejected=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
   addTearDown(rejected.dispose);
   await expectLater(rejected.initialize(),throwsFormatException);
   expect(rejected.ready,false);
   expect(await primary.readAsString(),bytes);
   expect(await backup.readAsString(),backupBytes);
  }
  await primary.writeAsString(original,flush:true);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  await restored.useBattleActiveSkill(awakening.id,restored.state.world.battle!.id,1,expectedGeneration:restored.restoreGeneration);
  expect(restored.state.world.battle!.awakeningTurns,3);
  expect(restored.state.world.lifespan,BigInt.zero);
 });
}
