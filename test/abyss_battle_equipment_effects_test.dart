import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/world_catalog.dart';

void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const stats=WorldStats(hp:1000,physical:100,magic:100,defense:100,physicalMax:100,magicMax:100,crit:0.1);
 test('装備補正と版4snapshotの往復、版3互換',(){
  final engine=WorldEngine(seedRandom:Random(7));
  final w=WorldState();
  final effects=BattleEquipmentEffects(physical:30000,magic:10000,defense:5000,critical:10000,evasion:5000,reduction:7000,discount:5000);
  engine.start(w,stats,'p01_main',1000000,equipmentEffects:effects);
  final b=w.battle!;
  expect(b.executionVersion,4);
  expect(b.stats.physical,400);expect(b.stats.magic,200);expect(b.stats.defense,150);
  expect(engine.energyCost(w,WorldCommand.heavyClaw),5);
  expect(engine.energyCost(w,WorldCommand.claw),2);
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  expect(restored.battle!.equipmentEffects!.sameAs(effects),true);
  expect(restored.battle!.stats.toJson(),b.stats.toJson());
  expect(engine.energyCost(restored,WorldCommand.heavyClaw),5);
  final legacy=WorldState();engine.start(legacy,stats,'p01_main',1000000);
  expect(legacy.battle!.executionVersion,3);
  expect(engine.energyCost(legacy,WorldCommand.heavyClaw),9);
  expect(WorldState.fromJson(legacy.toJson()).battle!.equipmentEffects,isNull);
 });
 test('版4不正上限・欠落・旧版への混入を拒否',(){
  final engine=WorldEngine(seedRandom:Random(7));
  final w=WorldState();engine.start(w,stats,'p01_main',1000000,equipmentEffects:BattleEquipmentEffects());
  final b=w.battle!;
  expect(()=>WorldBattle.fromJson(b.toJson()..remove('equipmentEffects')),throwsFormatException);
  expect(()=>WorldBattle.fromJson(b.toJson()..['executionVersion']=3),throwsFormatException);
  for(final entry in {'physical':30001,'magic':30001,'defense':30001,'critical':10001,'evasion':5001,'reduction':7001,'discount':5001}.entries){
   final raw=b.toJson();
   (raw['equipmentEffects'] as Map)[entry.key]=entry.value;
   expect(()=>WorldBattle.fromJson(raw),throwsFormatException);
  }
 });
}
