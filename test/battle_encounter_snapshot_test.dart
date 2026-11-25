import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

void main(){
 const now=1700000000000;
 const stats=WorldStats(hp:100,physical:40,magic:45,defense:10,physicalMax:27,magicMax:38,crit:0);
 const weak=WorldStats(hp:100,physical:2,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 late String master;
 setUpAll(()=>master=File(WorldCatalog.assetPath).readAsStringSync());
 setUp(()=>WorldCatalog.loadJson(master));
 tearDown(()=>WorldCatalog.loadJson(master));
 void change(String id,Map<String,dynamic> changes){
  final root=jsonDecode(master) as Map<String,dynamic>;
  final row=(root['encounters'] as List).singleWhere((e)=>e['id']==id) as Map<String,dynamic>;
  row.addAll(changes);
  WorldCatalog.loadJson(jsonEncode(root));
 }
 WorldState world()=>WorldState(cleared:{'p01_main','p02_main','p03_main','p12_main'},hpAt:now,energyAt:now,lifespan:BigInt.from(100));
 test('v2は敵定義を完全保存し変更後もHP・名称・反撃・報酬が固定',(){
  final engine=WorldEngine(),w=world();
  engine.start(w,stats,'p03_hunt',now,lifeRewardBonuses:[LifeRewardBonus.timeAbsorption,LifeRewardBonus.predatorInstinct]);
  final raw=jsonEncode(w.toJson());
  final frozen=w.battle!.encounter.toBattleJson();
  change('p03_hunt',{'hp':1,'attack':99,'defense':9999,'gold':999,'lifeDays':999,'enemy':'変更後','rank':'S','timeResistant':true,'regenerationPercent':100});
  expect(w.battle!.encounter.toBattleJson(),frozen);
  final restored=WorldState.fromJson(jsonDecode(raw) as Map<String,dynamic>);
  final b=restored.battle!;
  expect(b.executionVersion,2);
  expect(b.encounter.toBattleJson(),frozen);
  expect(b.enemyHp,35);
  expect(b.encounter.hp,35);
  expect(b.encounter.enemy,'悪党');
  expect(b.encounter.timeResistant,false);
  engine.act(restored,WorldCommand.guard,b.id,1,now);
  expect(restored.hp,98);
  engine.act(restored,WorldCommand.claw,b.id,2,now);
  expect(restored.battle,isNull);
  expect(restored.gold,25);
  expect(restored.lifespan,BigInt.from(139));
  expect(restored.supplyTickets,1);
  engine.start(restored,stats,'p03_hunt',now);
  expect(restored.battle!.encounter.hp,1);
  expect(restored.battle!.encounter.gold,999);
 });
 test('停止耐性・再生と抑制アイテムの判定も固定',(){
  change('p01_elite',{'regenerationPercent':10,'timeResistant':false});
  final engine=WorldEngine(),w=world();
  engine.start(w,weak,'p01_elite',now);
  final raw=w.toJson(),b=w.battle!;
  change('p01_elite',{'regenerationPercent':0,'timeResistant':true});
  final loaded=WorldState.fromJson(raw),saved=loaded.battle!;
  expect(saved.encounter.regenerationPercent,10);
  engine.validateBuff(loaded,BattleBuff.regenerationSuppression,saved.id,1);
  engine.act(loaded,WorldCommand.stopTime,saved.id,1,now);
  expect(loaded.hp,100);
  expect(saved.stopCooldown,5);
  saved.enemyHp=60;
  engine.act(loaded,WorldCommand.guard,saved.id,2,now);
  expect(saved.enemyHp,67);
  expect(loaded.hp,96);
  expect(b.encounter.timeResistant,false);
 });
 test('敵snapshot全項目必須、型・範囲・ID・版の不整合拒否',(){
  final engine=WorldEngine(),w=world();
  engine.start(w,stats,'p03_hunt',now);
  final raw=w.battle!.toJson(),snapshot=raw['encounterSnapshot'] as Map<String,dynamic>;
  for(final key in snapshot.keys){
   expect(()=>WorldBattle.fromJson({...raw,'encounterSnapshot':{...snapshot}..remove(key)}),throwsFormatException,reason:key);
   expect(()=>WorldBattle.fromJson({...raw,'encounterSnapshot':{...snapshot,key:null}}),throwsFormatException,reason:key);
  }
  for(final key in ['stage','hp','attack','defense','gold','lifeDays','regenerationPercent']){
   expect(()=>WorldBattle.fromJson({...raw,'encounterSnapshot':{...snapshot,key:1.0}}),throwsFormatException);
   expect(()=>WorldBattle.fromJson({...raw,'encounterSnapshot':{...snapshot,key:-1}}),throwsFormatException);
  }
  for(final invalid in [
   {...snapshot,'id':'p03_elite'},{...snapshot,'stage':2},{...snapshot,'main':true},
   {...snapshot,'hp':0},{...snapshot,'regenerationPercent':101},{...snapshot,'timeResistant':1},
   {...snapshot,'enemy':''},{...snapshot,'rank':1},
  ]){
   expect(()=>WorldBattle.fromJson({...raw,'encounterSnapshot':invalid}),throwsFormatException);
  }
  expect(()=>WorldBattle.fromJson({...raw}..remove('encounterSnapshot')),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...raw,'encounterSnapshot':null}),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...raw,'executionVersion':1}),throwsFormatException);
  expect(()=>WorldState.fromJson({...w.toJson(),'battle':{...raw,'enemyHp':36}}),throwsFormatException);
 });
 test('v1と版番号なしは従来のmaster参照で継続しv2へ昇格しない',(){
  final engine=WorldEngine(),w=world();
  engine.start(w,stats,'p03_hunt',now);
  final v1=w.battle!.toJson()..remove('encounterSnapshot');
  v1['executionVersion']=1;
  final legacy={...v1}..remove('executionVersion')..remove('lifeRewardPercent')..remove('lifeRewardBonuses');
  change('p03_hunt',{'hp':50,'gold':80,'lifeDays':90});
  for(final raw in [v1,legacy]){
   final old=WorldState.fromJson({...w.toJson(),'battle':raw});
   expect(old.battle!.encounter.hp,50);
   expect(old.battle!.encounter.gold,80);
   expect(old.battle!.executionVersion,raw['executionVersion']);
   expect(old.battle!.toJson().containsKey('encounterSnapshot'),false);
  }
  expect(()=>WorldBattle.fromJson({...v1}..remove('rngState')),throwsFormatException);
 });
 test('実ファイル：master変更後再起動して元の敵・報酬で勝利',() async{
  final dir=await Directory.systemTemp.createTemp('encounter-snapshot-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=LocalStore(directory:dir);
  final c=AppController(store,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.addAll(['p01_main','p02_main','p03_main']);
  await store.save(c.state);
  await c.startWorldBattle('p03_hunt');
  final id=c.state.world.battle!.id;
  change('p03_hunt',{'hp':1,'attack':99,'defense':9999,'gold':999,'lifeDays':999});
  final restored=AppController(LocalStore(directory:dir),clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.encounter.hp,35);
  final rg=restored.restoreGeneration;
  await restored.worldCommand(WorldCommand.claw,id,1,expectedGeneration:rg);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.world.gold,25);
  expect(restored.state.world.lifespan,BigInt.from(30));
  expect(restored.state.world.supplyTickets,1);
 });
}
