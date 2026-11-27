import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/abyss_ex_battle_attack.dart';

class _NoAttackRolls implements Random {
 @override double nextDouble()=>throw StateError('Unexpected attack RNG');
 @override bool nextBool()=>false;
 @override int nextInt(int max)=>0;
}

void main(){
 const now=1700000000000;
 const stats=WorldStats(hp:101,physical:100,magic:100,defense:100,physicalMax:100,magicMax:100,crit:0);
 const enemy=WorldEncounter('p01_main',1,'test','test',100000,101,100,0,main:true);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 ExBattleAttack action({int slot=0,int power=2500,int hpCost=1000,int life=3,int? condition=8000,ExAttackAttribute attribute=ExAttackAttribute.hpRecovery})=>ExBattleAttack(slot:slot,instanceId:'eq_1',skillId:'equipment_ex_skill:test_$slot',level:7,attribute:attribute,powerBps:power,physicalCost:3,magicCost:5,hpCostBps:hpCost,lifeDays:life,cooldown:2,initialCooldown:0,maxUses:1,energyDiscount:true,maxHpBps:condition);
 WorldState battle({int hp=80,int life=3,int physical=100,int magic=100,int gold=0,ExBattleAttack? a}){
  final selected=a??action();
  return WorldState(hp:hp,physical:physical,magic:magic,gold:gold,sequence:1,hpAt:now,energyAt:now,lifespan:BigInt.from(life),
   battle:WorldBattle(id:1,encounterId:enemy.id,stats:stats,enemyHp:enemy.hp,encounterSnapshot:enemy,executionVersion:selected.attribute==ExAttackAttribute.hpRecovery?10:9,equipmentEffects:BattleEquipmentEffects(discount:5000,extraAttack:5000,reduction:7000),exAttacks:[selected]));
 }
 WorldState clone(WorldState w)=>WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
 test('HP回復は代償先払い・切捨て・割引・反撃、攻撃乱数なし',(){
  final engine=WorldEngine(random:_NoAttackRolls()),w=battle();
  final b=w.battle!,rng=b.rngState;
  engine.actExAttack(w,0,1,1,now);
  // 80 - ceil(101*10%) + floor(101*25%) - 15(counter).
  expect(w.hp,79);expect(w.physical,98);expect(w.magic,97);expect(w.lifespan,BigInt.zero);
  expect(b.enemyHp,enemy.hp);expect(b.rngState,rng);expect(b.turn,2);
  expect(b.exAttacks.single.uses,1);expect(b.exAttacks.single.remaining(2),2);
  expect(b.log.any((l)=>l.contains('HP +25')),true);
  expect(clone(w).toJson(),w.toJson());
 });
 test('HP満タン/発動条件/自滅/資源不足を消費前に拒否',(){
  final engine=WorldEngine(random:_NoAttackRolls());
  for(final entry in <(WorldState,String)>[
   (battle(hp:101,a:action(condition:null)),'HPは満タンです'),
   (battle(hp:81),'HP条件未達'),
   (battle(hp:11),'HP不足'),
   (battle(life:2),'寿命不足'),
   (battle(physical:1),'物理エネルギー不足'),
   (battle(magic:2),'魔法エネルギー不足'),
  ]){
   final w=entry.$1,before=jsonEncode(w.toJson());
   expect(engine.exAttackUnavailable(w,0),entry.$2);
   expect(()=>engine.actExAttack(w,0,1,1,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
 });
 test('回復上限・最低1、HP残1を許可、CD後も使用上限',(){
  final engine=WorldEngine(random:_NoAttackRolls());
  final capped=battle(hp:80,a:action(power:10000));
  engine.actExAttack(capped,0,1,1,now);
  expect(capped.hp,86); // 101 - 15
  engine.act(capped,WorldCommand.guard,1,2,now);engine.act(capped,WorldCommand.guard,1,3,now);
  expect(engine.exAttackUnavailable(capped,0),'使用回数上限');
  final one=battle(hp:12,a:action(power:1));
  engine.actExAttack(one,0,1,1,now);
  expect(one.hp,0);expect(one.battle,isNull); // 代償後1、回復1、反撃敗北
 });
 test('版10のみ回復を許可、攻撃のみ版9維持、旧版混入拒否',(){
  final recovery=battle();
  final raw=recovery.battle!.toJson();
  expect(raw['executionVersion'],10);
  expect(()=>WorldBattle.fromJson({...raw,'executionVersion':9}),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...raw}..remove('exAttacks')),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...raw,'exAttacks':[]}),throwsFormatException);
  final attack=battle(a:action(attribute:ExAttackAttribute.physical));
  final old=attack.battle!.toJson();
  expect(WorldBattle.fromJson(old).toJson(),old);
  expect(()=>WorldBattle.fromJson({...old,'executionVersion':10}),throwsFormatException);
  expect(()=>action(power:10001),throwsFormatException);
 });
}
