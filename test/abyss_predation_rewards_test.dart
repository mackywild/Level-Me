import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_predation_candidates.dart';
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
 const defs=PredationSkillCandidates.definitions;
 const a=LifeRewardBonus.timeAbsorption,b=LifeRewardBonus.predatorInstinct;
 late SkillCatalog catalog;
 const stats=WorldStats(hp:100,physical:40,magic:45,defense:10,physicalMax:27,magicMax:38,crit:0);
 setUpAll((){
  WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync());
  catalog=SkillCatalog(defs);
 });
 WorldState world({int hp=100})=>WorldState(hp:hp,cleared:{'p01_main','p02_main','p03_main'},hpAt:now,energyAt:now,lifespan:BigInt.from(100));
 test('設計候補値・習得条件・本番無効と装着順非依存',(){
  final raw=File(AbyssMaster.assetPath).readAsStringSync();
  final rows=(jsonDecode(raw) as Map<String,dynamic>)['skills'] as List;
  final locked=WorldState(),state=SkillState(),w=world();
  expect((a.percent,b.percent),(10,20));
  for(final d in defs){
   expect(rows.singleWhere((r)=>r['id']==d.id)['name'],d.name);
   expect(d.kind,SkillKind.passive);
   expect(d.acquisition.clearedStage,3);
   expect(()=>catalog.learn(locked,state,d.id),throwsStateError);
   catalog.learn(w,state,d.id);
  }
  expect(catalog.rewardSnapshot(state),isEmpty);
  catalog.equip(w,state,defs.last.id);
  expect(catalog.rewardSnapshot(state),[b]);
  catalog.equip(w,state,defs.first.id);
  expect(catalog.rewardSnapshot(state),[a,b]);
  expect(()=>catalog.rewardSnapshot(state).clear(),throwsUnsupportedError);
  expect(catalog.applyPassive(stats,state).toJson(),stats.toJson());
  catalog.unequip(w,state,defs.last.id);
  expect(catalog.rewardSnapshot(state),[a]);
  expect(AbyssMaster.fromJson(raw).skills.definitions,isEmpty);
 });
 test('加算後一度だけ切り捨て、ゼロ報酬と巨大整数を扱う',(){
  for(final entry in [
   (const <LifeRewardBonus>[],365),(const [a],401),(const [b],438),(const [a,b],474),(const [b,a],474),
  ]){
   expect(LifeRewardBonus.reward(365,entry.$1),BigInt.from(entry.$2));
  }
  expect(LifeRewardBonus.reward(0,[a,b]),BigInt.zero);
  expect(LifeRewardBonus.reward(9,[a,b]),BigInt.from(11));
  expect(LifeRewardBonus.reward(0x7fffffffffffffff,[a,b]),BigInt.parse('11990383647911208549'));
  expect(()=>LifeRewardBonus.reward(-1,[a]),throwsFormatException);
  expect(()=>LifeRewardBonus.reward(30,[a,a]),throwsFormatException);
 });
 test('勝利時だけ補正、初回券は一度、再戦の寿命・Gのみ獲得',(){
  final engine=WorldEngine(),w=world();
  for(var i=0;i<2;i++){
   engine.start(w,stats,'p03_hunt',now,lifeRewardBonuses:[a,b]);
   final battle=w.battle!;
   expect(battle.lifeRewardBonuses,[a,b]);
   expect(()=>battle.lifeRewardBonuses.clear(),throwsUnsupportedError);
   engine.act(w,WorldCommand.claw,battle.id,1,now);
   expect(w.battle,isNull);
   expect(w.lifespan,BigInt.from(100+39*(i+1)));
   expect(w.gold,25*(i+1));
   expect(w.supplyTickets,1);
   expect(w.summonTickets,0);
   expect(w.lastResult,contains('寿命 +39日'));
   final before=jsonEncode(w.toJson());
   expect(()=>engine.act(w,WorldCommand.claw,battle.id,1,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
 });
 test('非致死行動・撤退・敗北・ゼロ寿命戦では追加寿命なし',(){
  final engine=WorldEngine(),w=world();
  engine.start(w,stats,'p03_elite',now,lifeRewardBonuses:[a,b]);
  final first=w.battle!;
  engine.act(w,WorldCommand.guard,first.id,1,now);
  expect(w.lifespan,BigInt.from(100));
  engine.act(w,WorldCommand.retreat,first.id,2,now);
  expect(w.lifespan,BigInt.from(100));
  expect(w.gold,0);
  final weak=world(hp:1);
  engine.start(weak,stats,'p03_elite',now,lifeRewardBonuses:[a,b]);
  engine.act(weak,WorldCommand.guard,weak.battle!.id,1,now);
  expect(weak.battle,isNull);
  expect(weak.lifespan,BigInt.from(100));
  expect(weak.gold,0);
  engine.start(w,stats,'p01_hunt',now,lifeRewardBonuses:[a,b]);
  engine.act(w,WorldCommand.claw,w.battle!.id,1,now);
  expect(w.battle,isNull);
  expect(w.lifespan,BigInt.from(100));
 });
 test('snapshotの不正型・重複・改変・欠落・未解放を拒否、旧戦闘互換',(){
  final engine=WorldEngine(),w=world(),state=SkillState();
  for(final d in defs){catalog.learn(w,state,d.id);catalog.equip(w,state,d.id);}
  engine.start(w,stats,'p03_hunt',now,lifeRewardBonuses:catalog.rewardSnapshot(state));
  final raw=w.battle!.toJson();
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  catalog.validateBattle(restored,state);
  for(final bad in [null,[],{},['unknown'],[a.name,a.name],[10],[a.name,b.name,'unknown']]){
   expect(()=>WorldBattle.fromJson({...raw,'lifeRewardBonuses':bad}),throwsFormatException);
  }
  for(final altered in [{...raw}..remove('lifeRewardBonuses'),{...raw,'lifeRewardBonuses':[a.name]}]){
   expect(()=>WorldState.fromJson({...w.toJson(),'battle':altered}),throwsFormatException);
  }
  final changed=WorldState.fromJson({...w.toJson(),'battle':{...raw,'lifeRewardBonuses':[b.name,a.name]}});
  expect(()=>catalog.validateBattle(changed,state),throwsFormatException);
  expect(()=>WorldState.fromJson({...w.toJson(),'cleared':['p01_main','p02_main']}),throwsFormatException);
  final old=world();
  engine.start(old,stats,'p03_hunt',now);
  final oldRaw=old.battle!.toJson()..remove('activeRuleSnapshots')..remove('encounterSnapshot')..remove('executionVersion')..remove('lifeRewardPercent')..remove('lifeRewardBonuses');
  catalog.validateBattle(WorldState.fromJson({...old.toJson(),'battle':oldRaw}),SkillState());
  final locked=WorldState();
  final before=jsonEncode(locked.toJson());
  expect(()=>engine.start(locked,stats,'p01_main',now,lifeRewardBonuses:[a]),throwsStateError);
  expect(jsonEncode(locked.toJson()),before);
  expect(()=>SkillCatalog(const [SkillDefinition(id:'skill:bad',name:'不正',kind:SkillKind.passive,lifeRewardBonus:a)]),throwsFormatException);
  expect(()=>SkillCatalog(const [SkillDefinition(id:'skill:time_absorption',name:'不正',kind:SkillKind.active,acquisition:SkillAcquisition(clearedStage:3),lifeRewardBonus:a)]),throwsFormatException);
 });
 test('実ファイル：勝利保存失敗・再起動再試行・報酬一括保存・解除後の再戦',() async{
  final dir=await Directory.systemTemp.createTemp('predation-skill-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.addAll(['p01_main','p02_main','p03_main']);
  c.state.world.lifespan=BigInt.from(100);
  await store.save(c.state);
  final gen=c.restoreGeneration;
  for(final d in defs){
   await c.learnWorldSkill(d.id,expectedGeneration:gen,expectedRevision:c.state.skills.revision);
   await c.equipWorldSkill(d.id,expectedGeneration:gen,expectedRevision:c.state.skills.revision);
  }
  await c.startWorldBattle('p03_hunt');
  final id=c.state.world.battle!.id;
  expect(c.state.world.battle!.lifeRewardBonuses,[a,b]);
  await expectLater(c.unequipWorldSkill(defs.first.id,expectedGeneration:gen,expectedRevision:c.state.skills.revision),throwsStateError);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.worldCommand(WorldCommand.claw,id,1,expectedGeneration:gen),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.lifeRewardBonuses,[a,b]);
  final rg=restored.restoreGeneration;
  await restored.worldCommand(WorldCommand.claw,id,1,expectedGeneration:rg);
  expect(jsonEncode(restored.state.toJson()),attempted);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.world.lifespan,BigInt.from(139));
  expect(restored.state.world.gold,25);
  expect(restored.state.world.supplyTickets,1);
  expect(restored.state.skills.learned.values.every((v)=>v==0),true);
  await expectLater(restored.worldCommand(WorldCommand.claw,id,1,expectedGeneration:rg),throwsStateError);
  for(final d in defs){
   await restored.unequipWorldSkill(d.id,expectedGeneration:rg,expectedRevision:restored.state.skills.revision);
  }
  await restored.startWorldBattle('p03_hunt');
  final next=restored.state.world.battle!;
  expect(next.lifeRewardBonuses,isEmpty);
  await restored.worldCommand(WorldCommand.claw,next.id,1,expectedGeneration:rg);
  expect(restored.state.world.lifespan,BigInt.from(169));
  expect(restored.state.world.gold,50);
  expect(restored.state.world.supplyTickets,1);
 });
}
