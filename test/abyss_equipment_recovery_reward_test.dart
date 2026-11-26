import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/world_catalog.dart';

void main(){
 const now=1700000000000;
 const stats=WorldStats(hp:100,physical:100,magic:100,defense:10,physicalMax:27,magicMax:38,crit:0);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 test('自然回復+300%は非戦闘tickのHP・物理・魔法のみ',(){
  final engine=WorldEngine(seedRandom:Random(7));
  final w=WorldState(hp:1,physical:0,magic:0,hpAt:now-WorldEngine.hpInterval,energyAt:now-WorldEngine.energyInterval);
  engine.refresh(w,stats,now,naturalRecovery:30000);
  expect(w.hp,21);expect(w.physical,4);expect(w.magic,4);
  final t=now+WorldEngine.hpInterval;
  engine.start(w,stats,'p01_main',now,equipmentEffects:BattleEquipmentEffects(naturalRecovery:30000));
  final before=jsonEncode(w.toJson());
  expect(engine.refresh(w,stats,t,naturalRecovery:30000),false);
  expect(jsonEncode(w.toJson()),before);
  expect(w.battle!.executionVersion,8);
  expect(WorldState.fromJson(jsonDecode(before) as Map<String,dynamic>).battle!.equipmentEffects!.naturalRecovery,30000);
 });
 test('勝利Gのみ増加・寿命と初回券維持、復元後同一報酬',(){
  final engine=WorldEngine(seedRandom:Random(7));
  final w=WorldState(hpAt:now,energyAt:now);
  engine.start(w,stats,'p01_main',now,equipmentEffects:BattleEquipmentEffects(reward:10000));
  final b=w.battle!;b.enemyHp=1;
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  engine.act(restored,WorldCommand.claw,b.id,b.turn,now);
  final e=WorldCatalog.byId('p01_main');
  expect(restored.battle,isNull);expect(restored.gold,e.gold*2);
  expect(restored.lifespan,BigInt.from(e.lifeDays));expect(restored.summonTickets,3);
  expect(WorldEngine.equipmentRewardAmount(3,5000),4);
  final invalid=b.toJson();(invalid['equipmentEffects'] as Map)['reward']=10001;
  expect(()=>WorldBattle.fromJson(invalid),throwsFormatException);
  expect(()=>WorldBattle.fromJson(b.toJson()..['executionVersion']=7),throwsFormatException);
 });
 test('補正後G上限超過は開始前に拒否',(){
  final e=WorldCatalog.byId('p01_main');
  final w=WorldState(gold:WorldEngine.maxRewardResource-e.gold);
  final before=jsonEncode(w.toJson());
  expect(()=>WorldEngine().start(w,stats,e.id,now,equipmentEffects:BattleEquipmentEffects(reward:10000)),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
 });
}
