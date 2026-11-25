import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_repair_candidates.dart';
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
 const defs=RepairSkillCandidates.definitions;
 late SkillCatalog catalog;
 final heal=defs.first.execution!,cleanse=defs[2].execution!;
 const stats=WorldStats(hp:100,physical:40,magic:45,defense:10,physicalMax:27,magicMax:38,crit:0.05);
 setUpAll((){
  // ST03は実マスターに存在する。未公開ステージを本番に追加しない。
  WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync());
  catalog=SkillCatalog(defs);
 });
 WorldState world(ActiveSkillSpec spec,{int hp=20,int? life,bool unlocked=true,Map<BattleStatus,int>? statuses})=>WorldState(
  hp:hp,physical:0,lifespan:BigInt.from(life??spec.lifeCost),cleared:{if(unlocked)'p03_main'},sequence:1,hpAt:now,energyAt:now,
  battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:10,rngState:1,activeSkills:[spec],
   statuses:statuses,acceleratedClaws:2,stopCooldown:3,buffs:{BattleBuff.energyDiscount:2}),
 );
 test('設計書5候補の名前・回復率・寿命と習得条件、本番無効を確認',(){
  final raw=File(AbyssMaster.assetPath).readAsStringSync();
  final rows=(jsonDecode(raw) as Map<String,dynamic>)['skills'] as List;
  final expected={'skill:wound_repair':(10,7),'skill:body_repair':(25,21),'skill:time_cleanse':(0,30),'skill:life_rewind':(50,180),'skill:full_repair':(100,365)};
  final state=SkillState(),w=WorldState();
  expect(catalog.definitions.length,5);
  for(final d in defs){
   final s=d.execution!;
   expect((s.repairPercent,s.lifeCost),expected[d.id]);
   expect(rows.singleWhere((r)=>r['id']==d.id)['name'],d.name);
   expect(d.acquisition.clearedStage,3);
   expect(()=>catalog.learn(w,state,d.id),throwsStateError);
  }
  w.cleared.add('p03_main');
  for(final d in defs){catalog.learn(w,state,d.id);}
  expect(state.learned.length,5);
  expect(AbyssMaster.fromJson(raw).skills.definitions,isEmpty);
 });
 test('HP修復4種は最大HP基準で上限まで回復し反撃・CDを1回処理',(){
  final engine=WorldEngine();
  for(final d in defs.where((d)=>d.execution!.effect==ActiveSkillEffect.repairHp)){
   final spec=d.execution!,w=world(d.execution!),b=w.battle!;
   final amount=WorldEngine.recoveryAmount(20,100,spec.repairPercent);
   engine.actActiveSkill(w,spec.id,1,1,now);
   expect(w.hp,20+amount-2);
   expect(w.lifespan,BigInt.zero);
   expect(w.physical,0);
   expect(w.itemUseSequence,0);
   expect(b.enemyHp,10);
   expect(b.turn,2);
   expect(b.rngState,1);
   expect(b.skillCooldowns[spec.id],5);
   expect(b.stopCooldown,2);
   expect(b.acceleratedClaws,2);
   expect(b.buffs[BattleBuff.energyDiscount],1);
   expect(b.log.any((l)=>l.contains('HP +$amount')),true);
  }
  expect(WorldEngine.recoveryAmount(99,100,10),1);
  expect(WorldEngine.recoveryAmount(1,2,10),1);
  expect(WorldEngine.recoveryAmount(100,100,100),0);
  expect(WorldEngine.recoveryAmount(0,0x7fffffffffffffff,100),0x7fffffffffffffff);
  expect(()=>WorldEngine.recoveryAmount(101,100,10),throwsStateError);
 });
 test('浄化は毒を反撃前に除去し、HP修復は毒を除去しない',(){
  final engine=WorldEngine();
  final purified=world(cleanse,statuses:{BattleStatus.poison:2});
  engine.actActiveSkill(purified,cleanse.id,1,1,now);
  expect(purified.hp,18);
  expect(purified.battle!.statuses,isEmpty);
  expect(purified.lifespan,BigInt.zero);
  expect(purified.battle!.skillCooldowns[cleanse.id],5);
  expect(purified.itemUseSequence,0);
  final repaired=world(heal,statuses:{BattleStatus.poison:2});
  engine.actActiveSkill(repaired,heal.id,1,1,now);
  expect(repaired.hp,23);
  expect(repaired.battle!.statuses[BattleStatus.poison],1);
 });
 test('満タン・毒なし・寿命不足・未解放・古いターン・CDは非消費',(){
  final engine=WorldEngine();
  for(final w in [world(heal,hp:100),world(heal,hp:0),world(heal,life:6),world(heal,unlocked:false),world(cleanse)]){
   final spec=w.battle!.activeSkills.single;
   final before=jsonEncode(w.toJson());
   expect(engine.activeSkillUnavailable(w,spec.id),isNotNull);
   expect(()=>engine.actActiveSkill(w,spec.id,1,1,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
  final w=world(heal,life:14),before=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,heal.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
  engine.actActiveSkill(w,heal.id,1,1,now);
  final after=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,heal.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),after);
 });
 test('修復定義の不正なID・費用・攻撃・CDとsnapshot改変を拒否',(){
  final raw=heal.toJson();
  expect(ActiveSkillSpec.fromJson(raw).repairPercent,10);
  for(final bad in [
   {...raw,'lifeCost':6},{...raw,'lifeCost':null},{...raw,'physicalCost':1},
   {...raw,'hits':2},{...raw,'powerPercent':1},{...raw,'cooldown':0},
   {...raw,'id':'skill:unknown'},{...raw,'effect':'physical'},
   {...cleanse.toJson(),'lifeCost':29},{...cleanse.toJson(),'id':heal.id},
  ]){
   expect(()=>ActiveSkillSpec.fromJson(bad),throwsFormatException);
  }
  final s=SkillState(),empty=WorldState(cleared:{'p03_main'});
  catalog.learn(empty,s,heal.id);catalog.equip(empty,s,heal.id);
  final w=world(heal);
  catalog.validateBattle(w,s);
  final altered=WorldState.fromJson({...w.toJson(),'battle':{...w.battle!.toJson(),'activeSkills':[{...raw,'cooldown':6}]}});
  expect(()=>catalog.validateBattle(altered,s),throwsFormatException);
 });
 test('実ファイル：修復・寿命・熟練度・CDの保存失敗と再試行、再起動',() async{
  final dir=await Directory.systemTemp.createTemp('repair-skill-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.add('p03_main');
  c.state.world.lifespan=BigInt.from(7);
  c.state.world.hp=50;
  await store.save(c.state);
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(heal.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(heal.id,expectedGeneration:gen,expectedRevision:1);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  expect(c.state.world.hp,50);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.useBattleActiveSkill(heal.id,id,1,expectedGeneration:gen),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.fail=false;
  await c.useBattleActiveSkill(heal.id,id,1,expectedGeneration:gen);
  expect(jsonEncode(c.state.toJson()),attempted);
  expect(c.state.world.hp,58);
  expect(c.state.world.lifespan,BigInt.zero);
  expect(c.state.skills.learned[heal.id],1);
  expect(c.state.world.battle!.skillCooldowns[heal.id],5);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.toJson(),c.state.world.battle!.toJson());
  expect(restored.state.world.hp,58);
  expect(restored.state.world.lifespan,BigInt.zero);
  expect(restored.state.skills.learned[heal.id],1);
  await expectLater(restored.useBattleActiveSkill(heal.id,id,1,expectedGeneration:restored.restoreGeneration),throwsStateError);
 });
}
