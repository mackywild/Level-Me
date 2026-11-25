import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_awakening_candidate.dart';
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
 const def=AwakeningSkillCandidate.definition;
 final spec=def.execution!;
 const attack=ActiveSkillSpec(id:'skill:test',name:'試験攻撃',powerPercent:100,physicalCost:4,cooldown:0);
 const stats=WorldStats(hp:100,physical:10,magic:10,defense:10,physicalMax:27,magicMax:38,crit:0);
 late SkillCatalog catalog;
 setUpAll((){
  loadExtendedWorldCatalog(12);
  catalog=SkillCatalog(const [def]);
 });
 WorldState world({bool unlocked=true,int life=30,int hp=100,Map<BattleBuff,int>? buffs})=>WorldState(
  hp:hp,lifespan:BigInt.from(life),cleared:{if(unlocked)'p12_main'},sequence:1,hpAt:now,energyAt:now,
  battle:WorldBattle(id:1,encounterId:'p01_elite',stats:stats,enemyHp:75,rngState:1,activeSkills:[spec,attack],buffs:buffs,acceleratedClaws:0,stopCooldown:3),
 );
 test('設計候補の物攻30%・3ターン・寿命30日、本番無効',(){
  expect((WorldBattle.awakeningPercent,WorldBattle.awakeningDuration,spec.lifeCost),(30,3,30));
  expect((def.acquisition.clearedStage,spec.cooldown),(12,5));
  try{
   WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync());
   expect(()=>SkillCatalog(const [def]),throwsFormatException);
  }finally{loadExtendedWorldCatalog(12);}
  final raw=File(AbyssMaster.assetPath).readAsStringSync();
  final rows=(jsonDecode(raw) as Map<String,dynamic>)['skills'] as List;
  expect(rows.singleWhere((r)=>r['id']==def.id)['name'],def.name);
  expect(AbyssMaster.fromJson(raw).skills.definitions,isEmpty);
 });
 test('発動は攻撃せず寿命だけ消費・通常反撃、次の3成立行動で満了',(){
  final engine=WorldEngine(),w=world(buffs:{BattleBuff.energyDiscount:2}),b=w.battle!;
  engine.actActiveSkill(w,spec.id,1,1,now);
  expect(w.hp,91);
  expect(w.physical,27);
  expect(w.magic,38);
  expect(w.lifespan,BigInt.zero);
  expect(b.enemyHp,75);
  expect(b.rngState,1);
  expect(b.awakeningTurns,3);
  expect(b.skillCooldowns[spec.id],5);
  expect(b.stopCooldown,2);
  expect(b.buffs[BattleBuff.energyDiscount],1);
  for(var i=0;i<5;i++){
   engine.act(w,WorldCommand.guard,1,b.turn,now);
   expect(b.awakeningTurns,i<3?2-i:0);
   expect(b.skillCooldowns[spec.id],i<4?4-i:null);
  }
  expect(engine.activeSkillUnavailable(w,spec.id),'寿命不足');
 });
 test('通常物理と能動物理のみ強化、魔法は強化しない、攻撃薬と非加算',(){
  final engine=WorldEngine();
  for(final kind in ['claw','active','magic','item-claw','item-magic']){
   final w=world(buffs:kind.startsWith('item')?{BattleBuff.attack:3}:null),b=w.battle!;
   engine.actActiveSkill(w,spec.id,1,1,now);
   if(kind=='active'){
    engine.actActiveSkill(w,attack.id,1,2,now);
   }else{
    engine.act(w,kind.endsWith('magic')?WorldCommand.magic:WorldCommand.claw,1,2,now);
   }
   final expected=kind=='magic'?10:kind=='item-magic'?13:11;
   expect(b.enemyHp,75-expected,reason:kind);
   expect(b.awakeningTurns,2);
  }
 });
 test('未解放・寿命不足・旧turn・CDの拒否、敗北時寿命返還なし',(){
  final engine=WorldEngine();
  for(final w in [world(unlocked:false),world(life:29)]){
   final before=jsonEncode(w.toJson());
   expect(()=>engine.actActiveSkill(w,spec.id,1,1,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
  final w=world(life:60),first=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,spec.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),first);
  engine.actActiveSkill(w,spec.id,1,1,now);
  final before=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,spec.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
  final weak=world(hp:1);
  engine.actActiveSkill(weak,spec.id,1,1,now);
  expect(weak.battle,isNull);
  expect(weak.lifespan,BigInt.zero);
 });
 test('残りターン・CD・装着・解放条件の不正保存と旧形式互換',(){
  final engine=WorldEngine(),w=world(),b=w.battle!;
  engine.actActiveSkill(w,spec.id,1,1,now);
  final raw=b.toJson();
  expect(WorldBattle.fromJson(raw).awakeningTurns,3);
  for(final bad in [null,-1,4,3.0,'3',0,2]){
   expect(()=>WorldBattle.fromJson({...raw,'awakeningTurns':bad}),throwsFormatException);
  }
  expect(()=>WorldBattle.fromJson({...raw}..remove('awakeningTurns')),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...raw,'skillCooldowns':{spec.id:4}}),throwsFormatException);
  expect(()=>WorldState.fromJson({...w.toJson(),'cleared':<String>[]}),throwsFormatException);
  final old=WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:10,rngState:1);
  expect(old.toJson().containsKey('awakeningTurns'),false);
  expect(WorldBattle.fromJson(old.toJson()).awakeningTurns,0);
  expect(()=>WorldBattle.fromJson({...old.toJson(),'awakeningTurns':0}),throwsFormatException);
  for(final invalid in [
   {...spec.toJson(),'lifeCost':29},{...spec.toJson(),'cooldown':4},
   {...spec.toJson(),'physicalCost':1},{...spec.toJson(),'powerPercent':30},
   {...spec.toJson(),'id':'skill:unknown'},
  ]){
   expect(()=>ActiveSkillSpec.fromJson(invalid),throwsFormatException);
  }
 });
 test('実ファイル：発動保存失敗・再起動再試行・熟練度・戦闘終了時破棄',() async{
  final dir=await Directory.systemTemp.createTemp('awakening-skill-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.add('p12_main');
  c.state.world.lifespan=BigInt.from(30);
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
  expect(restored.state.world.hp,98);
  expect(restored.state.world.lifespan,BigInt.zero);
  expect(restored.state.skills.learned[spec.id],1);
  expect(restored.state.world.battle!.awakeningTurns,3);
  expect(restored.state.world.battle!.skillCooldowns[spec.id],5);
  await expectLater(restored.useBattleActiveSkill(spec.id,id,1,expectedGeneration:rg),throwsStateError);
  await restored.worldCommand(WorldCommand.claw,id,2,expectedGeneration:rg);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.world.lifespan,BigInt.zero);
  await restored.startWorldBattle('p01_hunt');
  expect(restored.state.world.battle!.awakeningTurns,0);
 });
}
