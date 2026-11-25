import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_acceleration_candidates.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/world_catalog.dart';
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
 const defs=AccelerationSkillCandidates.definitions;
 final speed=defs.first.execution!,gale=defs.last.execution!;
 late SkillCatalog catalog;
 const stats=WorldStats(hp:100,physical:2,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 setUpAll((){
  WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync());
  catalog=SkillCatalog(defs);
 });
 WorldState world(ActiveSkillSpec spec,{int life=45,int enemyHp=10,bool unlocked=true,int hp=100})=>WorldState(
  hp:hp,physical:0,lifespan:BigInt.from(life),cleared:{if(unlocked)'p06_main'},sequence:1,hpAt:now,energyAt:now,
  battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:enemyHp,rngState:1,activeSkills:[spec],
   acceleratedClaws:2,stopCooldown:3,buffs:{BattleBuff.energyDiscount:2}),
 );
 test('設計候補値とST06習得条件・本番無効',(){
  expect((speed.id,speed.powerPercent,speed.hits,speed.lifeCost),('skill:speed_claw',250,1,10));
  expect((gale.id,gale.powerPercent,gale.hits,gale.lifeCost),('skill:gale_claws',50,8,45));
  final raw=File(AbyssMaster.assetPath).readAsStringSync();
  final rows=(jsonDecode(raw) as Map<String,dynamic>)['skills'] as List;
  final state=SkillState(),w=WorldState();
  for(final d in defs){
   expect(rows.singleWhere((r)=>r['id']==d.id)['name'],d.name);
   expect(d.acquisition.clearedStage,6);
   expect(()=>catalog.learn(w,state,d.id),throwsStateError);
  }
  w.cleared.add('p06_main');
  for(final d in defs){catalog.learn(w,state,d.id);}
  expect(state.learned.length,2);
  expect(AbyssMaster.fromJson(raw).skills.definitions,isEmpty);
 });
 test('単発・8hitとも寿命だけ消費し既存加速回数を維持',(){
  final engine=WorldEngine();
  for(final spec in [speed,gale]){
   final w=world(spec,life:spec.lifeCost),b=w.battle!;
   engine.actActiveSkill(w,spec.id,1,1,now);
   expect(w.lifespan,BigInt.zero);
   expect(w.physical,0);
   expect(w.hp,98);
   expect(b.turn,2);
   expect(b.acceleratedClaws,2);
   expect(b.stopCooldown,2);
   expect(b.skillCooldowns[spec.id],5);
   expect(b.buffs[BattleBuff.energyDiscount],1);
   expect(b.enemyHp,spec==speed?6:2);
   var rng=1;
   for(var i=0;i<spec.hits*2;i++){rng=rng*48271%BattleRandom.modulus;}
   expect(b.rngState,rng);
   final before=jsonEncode(w.toJson());
   expect(()=>engine.actActiveSkill(w,spec.id,1,2,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
 });
 test('未解放・寿命不足・古いターンを非消費で拒否',(){
  final engine=WorldEngine();
  for(final spec in [speed,gale]){
   for(final w in [world(spec,unlocked:false),world(spec,life:spec.lifeCost-1)]){
    final before=jsonEncode(w.toJson());
    expect(()=>engine.actActiveSkill(w,spec.id,1,1,now),throwsStateError);
    expect(jsonEncode(w.toJson()),before);
   }
   final w=world(spec),before=jsonEncode(w.toJson());
   expect(()=>engine.actActiveSkill(w,spec.id,1,2,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
 });
 test('寿命費用・効果種別・hit数の不正定義とsnapshot改変拒否',(){
  final raw=gale.toJson();
  expect(ActiveSkillSpec.fromJson(raw).toJson(),raw);
  for(final bad in [
   {...raw,'lifeCost':44},{...raw,'lifeCost':null},{...raw,'physicalCost':1},
   {...raw,'hits':7},{...raw,'powerPercent':51},{...raw,'cooldown':0},
   {...raw,'effect':'physical'},{...raw,'id':'skill:unknown'},
  ]){
   expect(()=>ActiveSkillSpec.fromJson(bad),throwsFormatException);
  }
  final state=SkillState(),empty=WorldState(cleared:{'p06_main'});
  catalog.learn(empty,state,gale.id);catalog.equip(empty,state,gale.id);
  final w=world(gale);
  catalog.validateBattle(w,state);
  final altered=WorldState.fromJson({...w.toJson(),'battle':{...w.battle!.toJson(),'activeSkills':[{...raw,'cooldown':6}]}});
  expect(()=>catalog.validateBattle(altered,state),throwsFormatException);
 });
 test('実ファイル：寿命攻撃の勝利・保存失敗・再起動後再試行',() async{
  final dir=await Directory.systemTemp.createTemp('acceleration-skill-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.add('p06_main');
  c.state.world.lifespan=BigInt.from(10);
  await store.save(c.state);
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(speed.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(speed.id,expectedGeneration:gen,expectedRevision:1);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.useBattleActiveSkill(speed.id,id,1,expectedGeneration:gen),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  await restored.useBattleActiveSkill(speed.id,id,1,expectedGeneration:restored.restoreGeneration);
  expect(jsonEncode(restored.state.toJson()),attempted);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.skills.learned[speed.id],1);
  expect(restored.state.world.physical,27);
  await expectLater(restored.useBattleActiveSkill(speed.id,id,1,expectedGeneration:restored.restoreGeneration),throwsStateError);
 });
}
