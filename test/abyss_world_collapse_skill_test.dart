import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/abyss_ultimate_candidate.dart';
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
 const def=WorldCollapseSkillCandidate.definition,prior=UltimateSkillCandidate.definition;
 final spec=def.execution!,other=prior.execution!;
 late SkillCatalog catalog;
 const stats=WorldStats(hp:100,physical:1,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 setUpAll((){
  loadExtendedWorldCatalog(21);
  catalog=SkillCatalog(const [prior,def]);
 });
 WorldState world({int life=730,bool unlocked=true,int hp=100,int enemyHp=10})=>WorldState(
  hp:hp,physical:0,lifespan:BigInt.from(life),cleared:{'p18_main',if(unlocked)'p21_main'},sequence:1,hpAt:now,energyAt:now,
  battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:enemyHp,rngState:1,activeSkills:[spec,other],
   acceleratedClaws:2,stopCooldown:3,buffs:{BattleBuff.energyDiscount:2}),
 );
 test('800%・730日・ST21・CD10、本番無効、旧奥義の条件維持',(){
  expect((spec.powerPercent,spec.lifeCost,spec.cooldown,spec.hits),(800,730,10,1));
  expect((spec.ultimateUnlockStage,other.ultimateUnlockStage),(21,18));
  expect((def.acquisition.clearedStage,prior.acquisition.clearedStage),(21,18));
  try{
   WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync());
   expect(()=>SkillCatalog(const [def]),throwsFormatException);
  }finally{loadExtendedWorldCatalog(21);}
  final raw=File(AbyssMaster.assetPath).readAsStringSync();
  final rows=(jsonDecode(raw) as Map<String,dynamic>)['skills'] as List;
  expect(rows.singleWhere((r)=>r['id']==def.id)['name'],def.name);
  final s=SkillState(),w=WorldState(cleared:{'p18_main'});
  catalog.learn(w,s,prior.id);
  expect(()=>catalog.learn(w,s,def.id),throwsStateError);
  w.cleared.add('p21_main');
  catalog.learn(w,s,def.id);
  expect(s.learned[def.id],0);
  expect(AbyssMaster.fromJson(raw).skills.definitions,isEmpty);
 });
 test('一般物理500%上限を維持、800%は指定奥義の組合せのみ許可',(){
  const physical=ActiveSkillSpec(id:'skill:test',name:'試験攻撃',powerPercent:500,physicalCost:1,cooldown:0);
  physical.validate();
  final raw=spec.toJson();
  expect(ActiveSkillSpec.fromJson(raw).toJson(),raw);
  expect(()=>ActiveSkillSpec.fromJson({...physical.toJson(),'powerPercent':800}),throwsFormatException);
  expect(()=>ActiveSkillSpec.fromJson({...physical.toJson(),'powerPercent':251,'hits':2}),throwsFormatException);
  for(final invalid in [
   {...raw,'powerPercent':799},{...raw,'powerPercent':801},{...raw,'lifeCost':729},
   {...raw,'cooldown':9},{...raw,'physicalCost':1},{...raw,'hits':2},
   {...raw,'id':'skill:spacetime_break'},{...raw,'id':'skill:time_end'},
   {...raw,'effect':'physical'},{...other.toJson(),'powerPercent':800},
  ]){
   expect(()=>ActiveSkillSpec.fromJson(invalid),throwsFormatException);
  }
  expect(()=>SkillCatalog([SkillDefinition(id:def.id,name:def.name,kind:SkillKind.active,execution:spec,acquisition:const SkillAcquisition(clearedStage:18))]),throwsFormatException);
 });
 test('非致死800%攻撃、通常反撃、独立CD10、停止CDと加速維持',(){
  final engine=WorldEngine(),w=world(),b=w.battle!;
  engine.actActiveSkill(w,spec.id,1,1,now);
  expect(b.enemyHp,3);
  expect(w.hp,98);
  expect(w.lifespan,BigInt.zero);
  expect(w.physical,0);
  expect(w.magic,38);
  expect(b.turn,2);
  expect(b.stopCooldown,2);
  expect(b.acceleratedClaws,2);
  expect(b.skillCooldowns[spec.id],10);
  expect(b.buffs[BattleBuff.energyDiscount],1);
  expect(b.rngState,48271*48271%BattleRandom.modulus);
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  expect(restored.battle!.skillCooldowns[spec.id],10);
  expect(restored.battle!.rngState,b.rngState);
  expect(engine.activeSkillUnavailable(restored,spec.id),'クールダウン中');
 });
 test('解放・寿命・古いturn拒否、CD10満了後再発動',(){
  final engine=WorldEngine();
  for(final w in [world(unlocked:false),world(life:729)]){
   final before=jsonEncode(w.toJson());
   expect(()=>engine.actActiveSkill(w,spec.id,1,1,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
  final w=world(life:1460),b=w.battle!;
  final before=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,spec.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
  engine.actActiveSkill(w,spec.id,1,1,now);
  final active=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,spec.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),active);
  for(var i=0;i<10;i++){engine.act(w,WorldCommand.guard,1,b.turn,now);}
  expect(b.skillCooldowns,isEmpty);
  expect(engine.activeSkillUnavailable(w,spec.id),isNull);
  engine.actActiveSkill(w,spec.id,1,b.turn,now);
  expect(w.battle,isNull);
  expect(w.lifespan,BigInt.zero);
  expect(w.gold,40);
  expect(w.summonTickets,3);
 });
 test('旧奥義と独立CD、勝利・敗北・snapshot不正',(){
  final engine=WorldEngine(),w=world(life:910),b=w.battle!;
  engine.actActiveSkill(w,other.id,1,1,now);
  expect(b.enemyHp,6);
  expect(b.skillCooldowns[other.id],8);
  expect(engine.activeSkillUnavailable(w,spec.id),isNull);
  final raw=b.toJson();
  expect(()=>WorldBattle.fromJson({...raw,'skillCooldowns':{spec.id:11}}),throwsFormatException);
  final state=SkillState(),empty=WorldState(cleared:{'p18_main','p21_main'});
  catalog.learn(empty,state,def.id);catalog.equip(empty,state,def.id);
  catalog.learn(empty,state,prior.id);catalog.equip(empty,state,prior.id);
  catalog.validateBattle(w,state);
  final changed=WorldState.fromJson({...w.toJson(),'battle':{...raw,'activeSkills':[other.toJson()]}});
  expect(()=>catalog.validateBattle(changed,state),throwsFormatException);
  engine.actActiveSkill(w,spec.id,1,2,now);
  expect(w.battle,isNull);
  expect(w.lifespan,BigInt.zero);
  final lose=world(hp:1);
  engine.actActiveSkill(lose,spec.id,1,1,now);
  expect(lose.battle,isNull);
  expect(lose.hp,0);
  expect(lose.lifespan,BigInt.zero);
  expect(lose.gold,0);
 });
 test('実ファイル：勝利保存失敗・再起動再試行・二重報酬防止',() async{
  final dir=await Directory.systemTemp.createTemp('world-collapse-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.add('p21_main');
  c.state.world.lifespan=BigInt.from(730);
  await store.save(c.state);
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(spec.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(spec.id,expectedGeneration:gen,expectedRevision:1);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.useBattleActiveSkill(spec.id,id,1,expectedGeneration:gen),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  final rg=restored.restoreGeneration;
  await restored.useBattleActiveSkill(spec.id,id,1,expectedGeneration:rg);
  expect(jsonEncode(restored.state.toJson()),attempted);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.world.lifespan,BigInt.zero);
  expect(restored.state.world.gold,40);
  expect(restored.state.world.summonTickets,3);
  expect(restored.state.skills.learned[spec.id],1);
  expect(restored.state.world.physical,27);
  final after=jsonEncode(restored.state.toJson());
  await expectLater(restored.useBattleActiveSkill(spec.id,id,1,expectedGeneration:rg),throwsStateError);
  expect(jsonEncode(restored.state.toJson()),after);
 });
}
