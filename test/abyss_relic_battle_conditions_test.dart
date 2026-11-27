import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_relic_skill_master.dart';
import 'package:level_me/world/abyss_relic_trigger_runtime.dart';

RelicEffectSnapshot effects(List<RelicEffect> kinds,{int chance=10000,int low=10000,int? uses=1}){
 final master=RelicSkillMaster(rules:[
  for(final e in kinds)RelicEffectRule(effect:e,stacking:RelicStacking.additive,chanceCapBps:10000,magnitudeCap:e.maximumMagnitude,maxUses:e==RelicEffect.lowHpAttack?null:uses,hpThresholdBps:e==RelicEffect.lowHpAttack?3000:null),
 ],skills:[
  for(final e in kinds)RelicSkillDefinition(id:'equipment_relic_skill:${e.name}',name:e.name,rarity:EquipmentSkillRarity.common,effect:e,chanceBpsByLevel:List.filled(10,e==RelicEffect.lowHpAttack?10000:chance),magnitudeByLevel:List.filled(10,e==RelicEffect.lowHpAttack?low:e==RelicEffect.turnEndMagicRecovery?4:0)),
 ]);
 return RelicEffectSnapshot.resolve(master,[for(final e in kinds)RelicSkillContribution(skillId:'equipment_relic_skill:${e.name}',level:1)]);
}
class _ZeroRandom implements Random {
 @override double nextDouble()=>0;
 @override bool nextBool()=>false;
 @override int nextInt(int max)=>0;
}
class _HalfRandom implements Random {
 @override double nextDouble()=>0.5;
 @override bool nextBool()=>false;
 @override int nextInt(int max)=>0;
}
void main(){
 const now=1700000000000;
 const stats=WorldStats(hp:100,physical:7,magic:11,defense:0,physicalMax:100,magicMax:100,crit:0);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 WorldEngine engine()=>WorldEngine(seedRandom:Random(7));
 WorldState world({int hp=30,int magic=80})=>WorldState(hp:hp,physical:100,magic:magic,hpAt:now,energyAt:now);
 WorldState clone(WorldState w)=>WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
 void guard(WorldEngine e,WorldState w)=>e.act(w,WorldCommand.guard,w.battle!.id,w.battle!.turn,now);
 test('窮地覚醒の厳密閾値と物理魔法の装備合算上限、復元',(){
  final e=engine(),w=world();
  e.start(w,stats,'p01_main',now,equipmentEffects:BattleEquipmentEffects(physical:25000,magic:15000),trialRelicEffects:effects([RelicEffect.lowHpAttack]));
  final b=w.battle!;
  expect(b.executionVersion,12);
  expect(b.stats.physical,24);expect(b.stats.magic,27);
  expect(b.attackStat(physical:true,hp:30),28);
  expect(b.attackStat(physical:false,hp:30),38);
  expect(b.attackStat(physical:true,hp:31),24);
  expect(b.attackStat(physical:false,hp:31),27);
  expect(b.relicUses,isEmpty);
  final restored=clone(w);
  expect(restored.toJson(),w.toJson());
  expect(restored.battle!.attackStat(physical:true,hp:30),28);
 });
 test('毒tick後の浄化と魔力循環、独立回数・復元',(){
  final e=engine(),w=world();
  e.start(w,stats,'p01_main',now,trialRelicEffects:effects([RelicEffect.statusCleanse,RelicEffect.turnEndMagicRecovery]));
  expect(e.tryInflictStatus(w,BattleStatus.poison,1,1),true);
  final rng=w.battle!.rngState;
  guard(e,w);
  expect(w.hp,24);expect(w.magic,84);expect(w.battle!.statuses,isEmpty);
  expect(w.battle!.relicUses,{RelicEffect.statusCleanse:1,RelicEffect.turnEndMagicRecovery:1});
  expect(w.battle!.rngState,rng);
  final restored=clone(w);
  e.tryInflictStatus(restored,BattleStatus.poison,1,2);
  guard(e,restored);
  expect(restored.battle!.statuses[BattleStatus.poison],2);
  expect(restored.magic,84);
  expect(restored.battle!.relicUses[RelicEffect.statusCleanse],1);
 });
 test('不滅の魂は致死のみ成功消費・復元後上限で敗北',(){
  final e=engine(),w=world(hp:1);
  e.start(w,stats,'p01_main',now,trialRelicEffects:effects([RelicEffect.lethalSurvival]));
  final rng=w.battle!.rngState;
  guard(e,w);expect(w.hp,1);expect(w.battle!.relicUses,{RelicEffect.lethalSurvival:1});
  expect(w.battle!.rngState,rng);
  final restored=clone(w);
  guard(e,restored);expect(restored.battle,isNull);expect(restored.hp,0);
 });
 test('致死薬優先・非致死は抽選なし、次の致死で魔遺物',(){
  final e=engine(),w=world(hp:1);
  e.start(w,stats,'p01_main',now,trialRelicEffects:effects([RelicEffect.lethalSurvival]));
  final raw=jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>;
  raw['battle']['buffs']['lethalProtection']=1;
  final protected=WorldState.fromJson(raw);
  final rng=protected.battle!.rngState;
  guard(e,protected);expect(protected.hp,1);expect(protected.battle!.relicUses,isEmpty);
  expect(protected.battle!.buffs.containsKey(BattleBuff.lethalProtection),false);
  guard(e,protected);expect(protected.battle!.relicUses[RelicEffect.lethalSurvival],1);expect(protected.battle!.rngState,rng);
  final healthy=world();
  e.start(healthy,stats,'p01_main',now,trialRelicEffects:effects([RelicEffect.lethalSurvival],chance:5000));
  final before=healthy.battle!.rngState;guard(e,healthy);
  expect(healthy.battle!.rngState,before);expect(healthy.battle!.relicUses,isEmpty);
 });
 test('窮地覚醒を実際の物理・魔法攻撃と追加攻撃に適用',(){
  final e=WorldEngine(seedRandom:Random(7),random:_HalfRandom());
  for(final command in [WorldCommand.claw,WorldCommand.magic]){
   for(final hp in [30,31]){
    final w=world(hp:hp);w.cleared.add('p01_main');
    e.start(w,stats,'p01_elite',now,trialRelicEffects:effects([RelicEffect.lowHpAttack]),equipmentEffects:BattleEquipmentEffects(extraAttack:5000));
    final b=w.battle!,before=b.enemyHp;
    e.act(w,command,b.id,b.turn,now);
    final attack=command==WorldCommand.claw?7:11;
    final value=hp==30?attack*2:attack;
    final expected=e.damage(value,b.encounter.defense,command==WorldCommand.claw?1:1.2);
    expect(before-b.enemyHp,expected);
   }
  }
  final extra=WorldEngine(seedRandom:Random(7),random:_ZeroRandom());
  final w=world();w.cleared.add('p01_main');
  extra.start(w,stats,'p01_elite',now,trialRelicEffects:effects([RelicEffect.lowHpAttack]),equipmentEffects:BattleEquipmentEffects(extraAttack:5000));
  final b=w.battle!,before=b.enemyHp;
  extra.act(w,WorldCommand.claw,b.id,b.turn,now);
  expect(before-b.enemyHp,extra.damage(14,b.encounter.defense,1,variance:0.95)+extra.damage(14,b.encounter.defense,0.5,variance:0.95));
  expect(b.log.any((l)=>l.startsWith('追加攻撃')),true);
 });
 test('致死の確率成功/失敗を永続RNGで再現し敗北時に二次効果なし',(){
  final e=engine();
  for(final (seed,success) in [(1,true),(40000,false)]){
   final w=world(hp:1);e.start(w,stats,'p01_main',now,trialRelicEffects:effects([RelicEffect.lethalSurvival,RelicEffect.turnEndMagicRecovery],chance:5000));
   final raw=jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>;
   raw['battle']['rngState']=seed;
   final restored=WorldState.fromJson(raw),again=clone(restored);
   guard(e,restored);guard(engine(),again);
   expect(restored.toJson(),again.toJson());
   expect(restored.hp,success?1:0);
   if(success){expect(restored.battle!.relicUses[RelicEffect.lethalSurvival],1);}
   else{expect(restored.battle,isNull);expect(restored.magic,80);}
  }
 });
 test('版12の最大turn拒否と攻撃補正overflowは変更前に拒否',(){
  final e=engine(),w=world();
  e.start(w,stats,'p01_main',now,trialRelicEffects:effects([RelicEffect.lowHpAttack]));
  final raw=jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>;
  const maxTurn=RelicRecoveryBattleRuntime.maxExpandedTurn;
  raw['battle']['turn']=maxTurn;raw['battle']['relicRecovery']['lastEvent']=2*maxTurn-1;
  final restored=WorldState.fromJson(raw),before=jsonEncode(restored.toJson());
  expect(()=>guard(e,restored),throwsStateError);expect(jsonEncode(restored.toJson()),before);
  final untouched=world(),original=jsonEncode(untouched.toJson());
  const enormous=WorldStats(hp:100,physical:WorldStats.maxStat,magic:1,defense:0,physicalMax:100,magicMax:100,crit:0);
  expect(()=>e.start(untouched,enormous,'p01_main',now,trialRelicEffects:effects([RelicEffect.lowHpAttack])),throwsStateError);
  expect(jsonEncode(untouched.toJson()),original);
 });
 test('版12のイベント・閾値・基礎攻撃・回数・旧版混入拒否',(){
  final e=engine(),w=world();
  e.start(w,stats,'p01_main',now,trialRelicEffects:effects([RelicEffect.lowHpAttack,RelicEffect.lethalSurvival]));
  Map<String,dynamic> raw()=>jsonDecode(jsonEncode(w.battle!.toJson())) as Map<String,dynamic>;
  for(final mutate in <void Function(Map<String,dynamic>)>[
   (j)=>j['executionVersion']=11,
   (j)=>j['relicRecovery']['lastEvent']=2,
   (j)=>j['relicRecovery']['baseAttack']['physical']=8,
   (j)=>j['relicRecovery']['effects']['lowHpAttack']['hpThresholdBps']=10000,
   (j)=>j['relicRecovery']['effects']['lowHpAttack']['uses']=1,
   (j)=>j['relicRecovery']['effects']['lethalSurvival']['uses']=1,
   (j)=>j['relicRecovery']['effects'].clear(),
  ]){final j=raw();mutate(j);expect(()=>WorldBattle.fromJson(j),throwsFormatException);}
 });
}
