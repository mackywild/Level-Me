import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_relic_skill_master.dart';
import 'package:level_me/world/abyss_relic_trigger_runtime.dart';

RelicEffectSnapshot reward({int chance=10000,int days=7,bool all=false}){
 final kinds=[if(all)...RelicEffect.values.where((e)=>e!=RelicEffect.victoryLifeReward),RelicEffect.victoryLifeReward];
 final master=RelicSkillMaster(rules:[
  for(final e in kinds)RelicEffectRule(effect:e,stacking:RelicStacking.additive,chanceCapBps:10000,magnitudeCap:e.maximumMagnitude,maxUses:e==RelicEffect.lowHpAttack?null:1,hpThresholdBps:e==RelicEffect.lowHpAttack?3000:null),
 ],skills:[
  for(final e in kinds)RelicSkillDefinition(id:'equipment_relic_skill:${e.name}',name:e.name,rarity:EquipmentSkillRarity.common,effect:e,chanceBpsByLevel:List.filled(10,e==RelicEffect.victoryLifeReward?chance:10000),magnitudeByLevel:List.filled(10,switch(e){RelicEffect.victoryLifeReward=>days,RelicEffect.battleStartHeal=>1000,RelicEffect.lowHpAttack=>10000,RelicEffect.turnEndMagicRecovery=>4,_=>0})),
 ]);
 return RelicEffectSnapshot.resolve(master,[for(final e in kinds)RelicSkillContribution(skillId:'equipment_relic_skill:${e.name}',level:1)]);
}
class _HalfRandom implements Random{
 @override double nextDouble()=>0.5;
 @override bool nextBool()=>false;
 @override int nextInt(int max)=>0;
}
void main(){
 const now=1700000000000;
 const stats=WorldStats(hp:100,physical:100,magic:100,defense:0,physicalMax:100,magicMax:100,crit:0);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 WorldEngine engine()=>WorldEngine(seedRandom:Random(7),random:_HalfRandom());
 WorldState world({int hp=100})=>WorldState(hp:hp,physical:100,magic:80,hpAt:now,energyAt:now,lifespan:BigInt.from(10));
 WorldState clone(WorldState w)=>WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
 void act(WorldEngine e,WorldState w,WorldCommand command)=>e.act(w,command,w.battle!.id,w.battle!.turn,now);
 test('既存寿命130%切捨て後に固定日数加算、G/券と表示、同一撃破再要求拒否',(){
  final e=engine(),w=world();
  w.cleared.addAll(['p01_main','p02_main','p03_main']);
  e.start(w,stats,'p03_hunt',now,trialRelicEffects:reward(),lifeRewardBonuses:LifeRewardBonus.values,equipmentEffects:BattleEquipmentEffects(reward:10000));
  final b=w.battle!,id=b.id,turn=b.turn,rng=b.rngState;
  expect(b.executionVersion,13);expect(clone(w).toJson(),w.toJson());
  act(e,w,WorldCommand.claw);
  expect(w.battle,isNull);expect(w.lifespan,BigInt.from(56)); // 10+39+7
  expect(w.gold,50);expect(w.supplyTickets,1);expect(b.rngState,rng);
  expect(w.lastResult,contains('寿命 +39日 / 魂の収奪 +7日'));
  expect(b.relicUses,{RelicEffect.victoryLifeReward:1});
  final before=jsonEncode(w.toJson());
  expect(()=>e.act(w,WorldCommand.claw,id,turn,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);expect(clone(w).toJson(),w.toJson());
 });
 test('基礎寿命0・再戦の勝利でも追加、初回券だけは一度',(){
  final e=engine(),w=world();w.cleared.add('p01_main');
  for(var i=1;i<=2;i++){
   e.start(w,stats,'p01_hunt',now,trialRelicEffects:reward(days:3));
   act(e,w,WorldCommand.claw);
   expect(w.lifespan,BigInt.from(10+3*i));expect(w.supplyTickets,1);
  }
 });
 test('永続RNGの確率成功/失敗と途中JSON復元再現、全6効果混在で終端回復なし',(){
  for(final (seed,success) in [(1,true),(40000,false)]){
   final e=engine(),w=world();
   e.start(w,stats,'p01_main',now,trialRelicEffects:reward(chance:5000,all:true));
   final raw=jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>;
   raw['battle']['rngState']=seed;
   final restored=WorldState.fromJson(raw),again=clone(restored),b=restored.battle!;
   act(e,restored,WorldCommand.claw);act(engine(),again,WorldCommand.claw);
   expect(restored.toJson(),again.toJson());expect(restored.battle,isNull);
   expect(restored.lifespan,BigInt.from(success?17:10));expect(restored.magic,80);
   expect(b.rngState,(seed*48271)%BattleRandom.modulus);
   expect(b.relicUses[RelicEffect.victoryLifeReward],success?1:null);
   expect(b.relicUses[RelicEffect.turnEndMagicRecovery],isNull);
  }
 });
 test('非撃破・敗北・撤退・報酬上限拒否で魂の収奪を判定しない',(){
  final e=engine(),w=world();
  e.start(w,stats,'p01_main',now,trialRelicEffects:reward(chance:5000));
  final b=w.battle!,rng=b.rngState;act(e,w,WorldCommand.guard);
  expect(b.rngState,rng);expect(b.relicUses,isEmpty);expect(w.lifespan,BigInt.from(10));
  w.gold=WorldEngine.maxRewardResource;
  final before=jsonEncode(w.toJson());expect(()=>act(e,w,WorldCommand.claw),throwsStateError);expect(jsonEncode(w.toJson()),before);
  act(e,w,WorldCommand.retreat);expect(w.lifespan,BigInt.from(10));expect(b.rngState,rng);
  final lose=world(hp:1);e.start(lose,stats,'p01_main',now,trialRelicEffects:reward(chance:5000));
  final lost=lose.battle!,old=lost.rngState;act(e,lose,WorldCommand.guard);
  expect(lose.battle,isNull);expect(lose.hp,0);expect(lose.lifespan,BigInt.from(10));expect(lost.rngState,old);
 });
 test('v13不正保存: 旧版混入、効果欠落、既勝利回数、上限、契機ずれ',(){
  final e=engine(),w=world();e.start(w,stats,'p01_main',now,trialRelicEffects:reward(all:true));
  Map<String,dynamic> raw()=>jsonDecode(jsonEncode(w.battle!.toJson())) as Map<String,dynamic>;
  for(final mutate in <void Function(Map<String,dynamic>)>[
   (j)=>j['executionVersion']=12,
   (j)=>j['relicRecovery']['version']=2,
   (j)=>j['relicRecovery']['lastEvent']=2,
   (j)=>j['relicRecovery']['effects'].remove('victoryLifeReward'),
   (j)=>j['relicRecovery']['effects']['victoryLifeReward']['uses']=1,
   (j)=>j['relicRecovery']['effects']['victoryLifeReward']['maxUses']=2,
   (j)=>j['relicRecovery']['effects']['victoryLifeReward']['magnitude']=1000001,
  ]){final j=raw();mutate(j);expect(()=>WorldBattle.fromJson(j),throwsFormatException);}
  act(e,w,WorldCommand.guard);
  final j=raw();j['relicRecovery']['effects']['victoryLifeReward']['uses']=1;
  expect(()=>WorldBattle.fromJson(j),throwsFormatException);
 });
 test('勝利event成功/失敗とも二重実行を拒否、終端後のターンも拒否',(){
  for(final roll in [0,9999]){
   final runtime=RelicRecoveryBattleRuntime(reward(chance:5000),baseAttack:(physical:100,magic:100));
   runtime.start(missingHp:false,nextInt:(_)=>throw StateError('unexpected RNG'));
   expect(runtime.victoryLife(1,(_)=>roll),roll==0?7:0);
   expect(()=>runtime.victoryLife(1,(_)=>0),throwsStateError);
   expect(()=>runtime.endTurn(1,missingMagic:true,nextInt:(_)=>0),throwsStateError);
  }
 });
}
