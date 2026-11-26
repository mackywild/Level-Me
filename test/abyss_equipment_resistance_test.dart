import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/world_catalog.dart';

class _Rolls implements Random {
 _Rolls(this.values);
 final List<double> values;
 int calls=0;
 @override double nextDouble()=>values[calls++];
 @override bool nextBool()=>false;
 @override int nextInt(int max)=>0;
}
void main(){
 const now=1700000000000;
 const stats=WorldStats(hp:100,physical:1,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 const enemy=WorldEncounter('p01_main',1,'test','test',1000,10,10,0,main:true);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 WorldState state({int resistance=8000,int? poison})=>WorldState(hp:100,sequence:1,hpAt:now,energyAt:now,battle:WorldBattle(id:1,encounterId:enemy.id,stats:stats,enemyHp:enemy.hp,encounterSnapshot:enemy,executionVersion:7,equipmentEffects:BattleEquipmentEffects(resistance:resistance,cooldown:5000),lifeRewardPercent:100,statuses:poison==null?{}:{BattleStatus.poison:poison}));
 test('耐性80%境界・既存毒保持・耐性0乱数非消費',(){
  final rolls=_Rolls([0.799999,0.8]);
  final engine=WorldEngine(random:rolls);
  final w=state(poison:1);
  expect(engine.tryInflictStatus(w,BattleStatus.poison,1,1),false);
  expect(w.battle!.statuses[BattleStatus.poison],1);
  expect(w.battle!.log.last,contains('無効化'));
  expect(engine.tryInflictStatus(w,BattleStatus.poison,1,1),true);
  expect(w.battle!.statuses[BattleStatus.poison],3);
  expect(rolls.calls,2);
  final zero=state(resistance:0);
  expect(engine.tryInflictStatus(zero,BattleStatus.poison,1,1),true);
  expect(rolls.calls,2);
  final before=jsonEncode(zero.toJson());
  expect(()=>engine.tryInflictStatus(zero,BattleStatus.poison,1,2),throwsStateError);
  expect(jsonEncode(zero.toJson()),before);
 });
 test('毒ダメージ・持続は耐性で変化せず、版7復元後も同一乱数結果',(){
  final w=state(poison:3);
  final raw=jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>;
  final first=WorldState.fromJson(raw),second=WorldState.fromJson(raw);
  final engine=WorldEngine();
  expect(first.battle!.equipmentEffects!.resistance,8000);
  expect(first.battle!.equipmentEffects!.cooldown,5000);
  expect(engine.tryInflictStatus(first,BattleStatus.poison,1,1),engine.tryInflictStatus(second,BattleStatus.poison,1,1));
  expect(first.toJson(),second.toJson());
  engine.act(first,WorldCommand.guard,1,1,now);
  expect(first.hp,91); // 反撃4、毒5。耐性は既存毒に適用しない。
  expect(first.battle!.statuses[BattleStatus.poison],2);
 });
 test('版7開始・不正耐性・版6混入を拒否',(){
  final engine=WorldEngine(seedRandom:Random(7));
  final w=WorldState();
  engine.start(w,stats,'p01_main',now,equipmentEffects:BattleEquipmentEffects(resistance:8000));
  final b=w.battle!;
  expect(b.executionVersion,7);
  expect(b.equipmentEffects!.toJson(statusResistance:true).length,12);
  expect(()=>WorldBattle.fromJson(b.toJson()..['executionVersion']=6),throwsFormatException);
  final invalid=b.toJson();(invalid['equipmentEffects'] as Map)['resistance']=8001;
  expect(()=>WorldBattle.fromJson(invalid),throwsFormatException);
  final missing=b.toJson();(missing['equipmentEffects'] as Map).remove('resistance');
  expect(()=>WorldBattle.fromJson(missing),throwsFormatException);
 });
}
