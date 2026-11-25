import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_chrono_finisher_candidates.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';
import 'helpers/extended_world_catalog.dart';

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
 const defs=ChronoFinisherCandidates.definitions;
 final still=defs.first.execution!,combo=defs.last.execution!;
 const stats=WorldStats(hp:100,physical:2,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 late SkillCatalog catalog;
 setUpAll((){
  loadExtendedWorldCatalog(12);
  catalog=SkillCatalog(defs);
 });
 WorldState world({int life=300,bool stage6=true,bool stage12=true,int cd=0})=>WorldState(
  physical:0,lifespan:BigInt.from(life),cleared:{if(stage6)'p06_main',if(stage12)'p12_main'},sequence:1,hpAt:now,energyAt:now,
  battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:10,rngState:1,activeSkills:[still,combo],acceleratedClaws:2,stopCooldown:cd),
 );
 test('候補値・習得ST12と超時連撃ST06・本番無効',(){
  expect((still.powerPercent,still.lifeCost,still.cooldown),(250,45,0));
  expect((combo.powerPercent,combo.lifeCost,combo.cooldown),(400,90,0));
  try{
   WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync());
   expect(()=>SkillCatalog(defs),throwsFormatException);
  }finally{loadExtendedWorldCatalog(12);}
  final raw=File(AbyssMaster.assetPath).readAsStringSync();
  final rows=(jsonDecode(raw) as Map<String,dynamic>)['skills'] as List;
  final state=SkillState(),w=WorldState();
  for(final d in defs){
   expect(rows.singleWhere((r)=>r['id']==d.id)['name'],d.name);
   expect(()=>catalog.learn(w,state,d.id),throwsStateError);
  }
  w.cleared.add('p12_main');
  catalog.learn(w,state,still.id);
  expect(()=>catalog.learn(w,state,combo.id),throwsStateError);
  w.cleared.add('p06_main');
  catalog.learn(w,state,combo.id);
  expect(state.learned.length,2);
  expect(AbyssMaster.fromJson(raw).skills.definitions,isEmpty);
 });
 test('静止爪撃は寿命のみ消費、停止・共有CD5・加速残数維持',(){
  final engine=WorldEngine(),w=world(life:45),b=w.battle!;
  engine.actActiveSkill(w,still.id,1,1,now);
  expect(w.lifespan,BigInt.zero);
  expect(w.physical,0);
  expect(w.hp,100);
  expect(b.enemyHp,6);
  expect(b.turn,2);
  expect(b.acceleratedClaws,2);
  expect(b.stopCooldown,5);
  expect(b.skillCooldowns,isEmpty);
  expect(engine.activeSkillCooldown(b,still),5);
  expect(engine.activeSkillCooldown(b,combo),5);
  expect(b.rngState,48271*48271%BattleRandom.modulus);
 });
 test('超時連撃と既存複合爪撃は同じ戦闘結果・乱数・費用',(){
  final engine=WorldEngine(),w=world(life:90),other=world(life:90);
  engine.actActiveSkill(w,combo.id,1,1,now);
  engine.act(other,WorldCommand.compositeClaw,1,1,now);
  expect(w.hp,other.hp);
  expect(w.lifespan,BigInt.zero);
  expect(w.lifespan,other.lifespan);
  expect(w.physical,other.physical);
  expect(w.battle!.enemyHp,3);
  expect(w.battle!.enemyHp,other.battle!.enemyHp);
  expect(w.battle!.rngState,other.battle!.rngState);
  expect(w.battle!.stopCooldown,other.battle!.stopCooldown);
  expect(w.battle!.acceleratedClaws,other.battle!.acceleratedClaws);
  expect(w.battle!.turn,other.battle!.turn);
 });
 test('停止・複合・奥義の相互CD制約、満了後の再使用',(){
  final engine=WorldEngine();
  for(final first in [WorldCommand.stopTime,WorldCommand.compositeClaw]){
   final w=world(),b=w.battle!;
   engine.act(w,first,1,1,now);
   final before=jsonEncode(w.toJson());
   for(final spec in [still,combo]){
    expect(()=>engine.actActiveSkill(w,spec.id,1,2,now),throwsStateError);
   }
   expect(jsonEncode(w.toJson()),before);
   expect(b.stopCooldown,5);
  }
  final w=world(),b=w.battle!;
  engine.actActiveSkill(w,still.id,1,1,now);
  final before=jsonEncode(w.toJson());
  for(final cmd in [WorldCommand.stopTime,WorldCommand.compositeClaw]){
   expect(()=>engine.act(w,cmd,1,2,now),throwsStateError);
  }
  expect(()=>engine.actActiveSkill(w,combo.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
  for(var i=0;i<5;i++){engine.act(w,WorldCommand.guard,1,b.turn,now);}
  expect(b.stopCooldown,0);
  expect(engine.activeSkillUnavailable(w,combo.id),isNull);
  engine.actActiveSkill(w,combo.id,1,b.turn,now);
  expect(w.battle,isNull);
  expect(w.lifespan,BigInt.from(165));
 });
 test('時間耐性は停止のみ無効、攻撃と寿命消費は成立',(){
  final raw=jsonDecode(File(WorldCatalog.assetPath).readAsStringSync()) as Map<String,dynamic>;
  final row=(raw['encounters'] as List).singleWhere((r)=>r['id']=='p01_main') as Map<String,dynamic>;
  row['timeResistant']=true;
  WorldCatalog.loadJson(jsonEncode(raw));
  try{
   final engine=WorldEngine();
   for(final spec in [still,combo]){
    final w=world(life:spec.lifeCost),b=w.battle!;
    engine.actActiveSkill(w,spec.id,1,1,now);
    expect(w.hp,98);
    expect(w.lifespan,BigInt.zero);
    expect(b.enemyHp,spec==still?6:3);
    expect(b.stopCooldown,5);
    expect(b.log.any((l)=>l.contains('時間停止は無効化')),true);
   }
  }finally{loadExtendedWorldCatalog(12);}
 });
 test('解放条件・寿命不足・旧turn・不正定義と独立CDを拒否',(){
  final engine=WorldEngine();
  for(final w in [world(stage12:false),world(stage6:false),world(life:89),world(cd:1)]){
   final before=jsonEncode(w.toJson());
   expect(()=>engine.actActiveSkill(w,combo.id,1,1,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
  final w=world(),before=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,still.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
  for(final bad in [
   {...combo.toJson(),'lifeCost':89},{...combo.toJson(),'powerPercent':401},
   {...combo.toJson(),'cooldown':5},{...combo.toJson(),'hits':2},
   {...combo.toJson(),'physicalCost':1},{...combo.toJson(),'id':'skill:unknown'},
  ]){
   expect(()=>ActiveSkillSpec.fromJson(bad),throwsFormatException);
  }
  expect(()=>WorldBattle.fromJson({...w.battle!.toJson(),'skillCooldowns':{combo.id:5}}),throwsFormatException);
  engine.actActiveSkill(w,still.id,1,1,now);
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  expect(restored.battle!.stopCooldown,5);
  expect(engine.activeSkillUnavailable(restored,combo.id),'クールダウン中');
 });
 test('実ファイル：超時連撃の勝利・保存失敗・再起動再試行',() async{
  final dir=await Directory.systemTemp.createTemp('chrono-finisher-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.addAll(['p06_main','p12_main']);
  c.state.world.lifespan=BigInt.from(90);
  await store.save(c.state);
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(combo.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(combo.id,expectedGeneration:gen,expectedRevision:1);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.useBattleActiveSkill(combo.id,id,1,expectedGeneration:gen),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  final rg=restored.restoreGeneration;
  await restored.useBattleActiveSkill(combo.id,id,1,expectedGeneration:rg);
  expect(jsonEncode(restored.state.toJson()),attempted);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.world.lifespan,BigInt.zero);
  expect(restored.state.world.physical,27);
  expect(restored.state.skills.learned[combo.id],1);
  await expectLater(restored.useBattleActiveSkill(combo.id,id,1,expectedGeneration:rg),throwsStateError);
 });
}
