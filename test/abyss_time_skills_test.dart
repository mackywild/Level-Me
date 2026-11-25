import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/abyss_time_candidates.dart';
import 'package:level_me/world/world_catalog.dart';
import 'helpers/extended_world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Store extends LocalStore {
 _Store(Directory dir):super(directory:dir);
 bool fail=false;
 String? attempted;
 @override Future<void> save(AppStateData state) async{
  attempted=jsonEncode(state.toJson());
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}

void main(){
 const now=1700000000000;
 const def=TimeSkillCandidates.foresight;
 final spec=def.execution!;
 late SkillCatalog catalog;
 const stats=WorldStats(hp:100,physical:40,magic:45,defense:10,physicalMax:27,magicMax:38,crit:0.05);
 setUpAll((){
  loadExtendedWorldCatalog(9);
  catalog=SkillCatalog(const [def]);
 });
 WorldState world({int life=14,bool unlocked=true,Map<BattleBuff,int>? buffs,Map<BattleStatus,int>? statuses})=>WorldState(physical:0,lifespan:BigInt.from(life),cleared:{if(unlocked)'p09_main'},sequence:1,hpAt:now,energyAt:now,battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:10,rngState:1,activeSkills:[spec],buffs:buffs,statuses:statuses,slowTurns:1,stopCooldown:3));
 test('未公開ST09を実マスターのまま習得カタログに登録できない',(){
  try{
   WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync());
   expect(()=>SkillCatalog(const [def]),throwsFormatException);
  }finally{loadExtendedWorldCatalog(9);}
 });
 test('設計書候補値・ST09習得条件・本番無効',(){
  expect(spec.lifeCost,14);
  expect(spec.effect,ActiveSkillEffect.foresight);
  expect(def.acquisition.clearedStage,9);
  final state=SkillState(),w=WorldState();
  expect(()=>catalog.learn(w,state,def.id),throwsStateError);
  w.cleared.add('p09_main');
  catalog.learn(w,state,def.id);
  expect(state.learned[def.id],0);
  expect(AbyssMaster.fromJson(File(AbyssMaster.assetPath).readAsStringSync()).skills.definitions,isEmpty);
 });
 test('寿命のみ全額消費、通常反撃無効、毒・CD・遅延経過、回避乱数非消費',(){
  final w=world(buffs:{BattleBuff.energyDiscount:2,BattleBuff.evasion:2,BattleBuff.lethalProtection:1},statuses:{BattleStatus.poison:2});
  final engine=WorldEngine(),b=w.battle!;
  engine.actActiveSkill(w,def.id,1,1,now);
  expect(w.lifespan,BigInt.zero);
  expect(w.physical,0);
  expect(w.hp,95);
  expect(b.enemyHp,10);
  expect(b.turn,2);
  expect(b.rngState,1);
  expect(b.slowTurns,0);
  expect(b.stopCooldown,2);
  expect(b.skillCooldowns[def.id],5);
  expect(b.statuses[BattleStatus.poison],1);
  expect(b.buffs[BattleBuff.lethalProtection],1);
  expect(b.buffs[BattleBuff.evasion],1);
  expect(b.buffs[BattleBuff.energyDiscount],1);
  expect(b.log.any((l)=>l.contains('反撃を無効化')),true);
  final before=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,def.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
 });
 test('未解放・寿命不足・古いターンは非消費',(){
  final engine=WorldEngine();
  for(final w in [world(unlocked:false),world(life:13)]){
   final before=jsonEncode(w.toJson());
   expect(()=>engine.actActiveSkill(w,def.id,1,1,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
  final w=world(),before=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,def.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
 });
 test('旧物理定義互換・不正効果と費用拒否・snapshot照合',(){
  const old=ActiveSkillSpec(id:'skill:test',name:'試験',powerPercent:100,physicalCost:4,cooldown:0);
  final legacy=ActiveSkillSpec.fromJson(old.toJson()..remove('effect')..remove('lifeCost'));
  expect(legacy.effect,ActiveSkillEffect.physical);
  expect(legacy.lifeCost,0);
  final raw=spec.toJson();
  for(final invalid in [
   {...raw,'effect':null},{...raw,'effect':'unknown'},{...raw,'lifeCost':null},
   {...raw,'lifeCost':13},{...raw,'physicalCost':1},{...raw,'powerPercent':1},
   {...raw,'cooldown':0},{...raw,'hits':2},{...old.toJson(),'lifeCost':14},
  ]){
   expect(()=>ActiveSkillSpec.fromJson(invalid),throwsFormatException);
  }
  final s=SkillState(),empty=WorldState(cleared:{'p09_main'});
  catalog.learn(empty,s,def.id);catalog.equip(empty,s,def.id);
  final w=world();
  catalog.validateBattle(w,s);
  final altered=WorldState.fromJson({...w.toJson(),'battle':{...w.battle!.toJson(),'activeSkills':[{...raw,'cooldown':6}]}});
  expect(()=>catalog.validateBattle(altered,s),throwsFormatException);
 });
 test('実ファイル：寿命・熟練度・CDの保存失敗と再試行、再起動',() async{
  final dir=await Directory.systemTemp.createTemp('foresight-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.add('p09_main');
  c.state.world.lifespan=BigInt.from(14);
  await store.save(c.state);
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(def.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(def.id,expectedGeneration:gen,expectedRevision:1);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.useBattleActiveSkill(def.id,id,1,expectedGeneration:gen),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.fail=false;
  await c.useBattleActiveSkill(def.id,id,1,expectedGeneration:gen);
  expect(jsonEncode(c.state.toJson()),attempted);
  expect(c.state.world.lifespan,BigInt.zero);
  expect(c.state.skills.learned[def.id],1);
  expect(c.state.world.battle!.skillCooldowns[def.id],5);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.toJson(),c.state.world.battle!.toJson());
  expect(restored.state.world.lifespan,BigInt.zero);
  expect(restored.state.skills.learned[def.id],1);
  await expectLater(restored.useBattleActiveSkill(def.id,id,1,expectedGeneration:restored.restoreGeneration),throwsStateError);
 });
}
