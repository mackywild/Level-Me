import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_relic_skill_master.dart';
import 'package:level_me/world/abyss_relic_trigger_runtime.dart';

RelicSkillDefinition skill(String suffix,RelicEffect effect,int chance,int magnitude)=>RelicSkillDefinition(id:'equipment_relic_skill:$suffix',name:suffix,rarity:EquipmentSkillRarity.common,effect:effect,chanceBpsByLevel:List.filled(10,chance),magnitudeByLevel:List.filled(10,magnitude));
RelicSkillContribution slot(RelicSkillDefinition s,{int level=1})=>RelicSkillContribution(skillId:s.id,level:level);
RelicEffectRule rule(RelicEffect e,{RelicStacking stacking=RelicStacking.additive,int chance=10000,int? magnitude,int? uses})=>RelicEffectRule(effect:e,stacking:stacking,chanceCapBps:chance,magnitudeCap:magnitude??e.maximumMagnitude,maxUses:uses,hpThresholdBps:e==RelicEffect.lowHpAttack?3000:null);
RelicEffectSnapshot snapshot(List<RelicEffectRule> rules,List<RelicSkillDefinition> skills,List<RelicSkillContribution> slots)=>RelicEffectSnapshot.resolve(RelicSkillMaster(rules:rules,skills:skills),slots);

void main(){
 final magic=skill('magic',RelicEffect.turnEndMagicRecovery,3000,4),cleanse=skill('cleanse',RelicEffect.statusCleanse,5000,0);
 final start=skill('start',RelicEffect.battleStartHeal,10000,1000),victory=skill('victory',RelicEffect.victoryLifeReward,2000,3);
 final low=skill('low',RelicEffect.lowHpAttack,10000,10000);
 test('効果別加算・最高値・上限、同じIDの別枠、順序不変',(){
  final other=skill('magic_other',RelicEffect.turnEndMagicRecovery,1000,8);
  for(final stacking in RelicStacking.values){
   final rules=[rule(magic.effect,stacking:stacking,chance:5000,magnitude:10)];
   final slots=[slot(magic),slot(magic),slot(other)];
   final a=snapshot(rules,[magic,other],slots),b=snapshot(rules,[other,magic],slots.reversed.toList());
   final effect=a.effects[magic.effect]!;
   expect(effect.chanceBps,stacking==RelicStacking.additive?5000:3000);
   expect(effect.magnitude,stacking==RelicStacking.additive?10:8);
   expect(b.effects[magic.effect]!.chanceBps,effect.chanceBps);
   expect(b.effects[magic.effect]!.magnitude,effect.magnitude);
   expect(()=>a.effects.clear(),throwsUnsupportedError);
  }
 });
 test('未知ID/Lv/6枠上限、空枠を検証',(){
  final master=RelicSkillMaster(rules:[rule(magic.effect)],skills:[magic]);
  expect(RelicEffectSnapshot.resolve(master,[]).effects,isEmpty);
  expect(()=>RelicEffectSnapshot.resolve(master,List.filled(7,slot(magic))),throwsArgumentError);
  expect(()=>RelicEffectSnapshot.resolve(master,[slot(magic,level:11)]),throwsRangeError);
  expect(()=>RelicEffectSnapshot.resolve(master,[const RelicSkillContribution(skillId:'unknown',level:1)]),throwsStateError);
 });
 test('低HP境界と通常/EX合算後の物理魔法最終上限、整数境界',(){
  final a=snapshot([rule(low.effect)],[low],[slot(low),slot(low)]);
  expect(a.lowHpAttackBonus(30,100),20000);
  expect(a.lowHpAttackBonus(31,100),0);
  expect(a.lowHpAttackBonus(0,100),0);
  expect(a.lowHpAttackBonus(30,101),20000);
  expect(a.lowHpAttackBonus(31,101),0);
  expect(a.lowHpAttackBonus(2700000000000000000,9000000000000000000),20000);
  for(final effect in [EquipmentEffect.physicalPercent,EquipmentEffect.magicPercent]){
   expect(a.attackBonus(effect,20000,30,100),30000);
   expect(a.attackBonus(effect,20000,31,100),20000);
  }
  expect(()=>a.lowHpAttackBonus(1,0),throwsArgumentError);
  expect(()=>a.attackBonus(EquipmentEffect.defensePercent,0,30,100),throwsArgumentError);
 });
 test('独立抽選・適用可能時のみ・成功回数のみ消費・順序固定',(){
  final a=RelicTriggerRuntime(snapshot([rule(magic.effect,uses:1),rule(cleanse.effect,uses:2)],[magic,cleanse],[slot(cleanse),slot(magic)]));
  final eligible={cleanse.effect,magic.effect},rolls=[2999,5000],bounds=<int>[];
  final first=a.resolveEvent(eventId:1,trigger:RelicTrigger.turnEnd,eligible:eligible,nextInt:(bound){bounds.add(bound);return rolls.removeAt(0);});
  expect(bounds,[10000,10000]);expect(first.map((o)=>o.effect),[magic.effect]);expect(first.single.magnitude,4);expect(a.uses,{magic.effect:1});
  final second=a.resolveEvent(eventId:2,trigger:RelicTrigger.turnEnd,eligible:eligible,nextInt:(_)=>4999);
  expect(second.map((o)=>o.effect),[cleanse.effect]);expect(a.uses,{magic.effect:1,cleanse.effect:1});
  expect(a.resolveEvent(eventId:3,trigger:RelicTrigger.turnEnd,eligible:{magic.effect},nextInt:(_)=>throw StateError('unexpected roll')),isEmpty);
  expect(a.resolveEvent(eventId:4,trigger:RelicTrigger.turnEnd,eligible:{},nextInt:(_)=>throw StateError('unexpected roll')),isEmpty);
  a.resolveEvent(eventId:5,trigger:RelicTrigger.turnEnd,eligible:{cleanse.effect},nextInt:(_)=>0);
  expect(a.resolveEvent(eventId:6,trigger:RelicTrigger.turnEnd,eligible:eligible,nextInt:(_)=>throw StateError('unexpected roll')),isEmpty);
  expect(a.uses,{magic.effect:1,cleanse.effect:2});expect(()=>a.uses.clear(),throwsUnsupportedError);
 });
 test('開始/勝利イベントは失敗でも再試行不可、確定発動は乱数不要',(){
  final a=RelicTriggerRuntime(snapshot([rule(start.effect,uses:1),rule(victory.effect,uses:1)],[start,victory],[slot(start),slot(victory)]));
  expect(a.resolveEvent(eventId:1,trigger:RelicTrigger.battleStart,eligible:{start.effect},nextInt:(_)=>throw StateError('unexpected roll')).single.magnitude,1000);
  expect(()=>a.resolveEvent(eventId:2,trigger:RelicTrigger.battleStart,eligible:{},nextInt:(_)=>0),throwsStateError);
  expect(a.resolveEvent(eventId:2,trigger:RelicTrigger.victory,eligible:{victory.effect},nextInt:(_)=>9999),isEmpty);
  expect(a.uses,{start.effect:1});
  expect(()=>a.resolveEvent(eventId:3,trigger:RelicTrigger.victory,eligible:{victory.effect},nextInt:(_)=>0),throwsStateError);
  final b=RelicTriggerRuntime(a.snapshot);
  expect(b.resolveEvent(eventId:1,trigger:RelicTrigger.battleStart,eligible:{},nextInt:(_)=>0),isEmpty);
  expect(()=>b.resolveEvent(eventId:2,trigger:RelicTrigger.battleStart,eligible:{start.effect},nextInt:(_)=>0),throwsStateError);
 });
 test('イベント重複・異種契機・再入・不正乱数で結果を部分確定しない',(){
  final a=RelicTriggerRuntime(snapshot([rule(magic.effect),rule(cleanse.effect)],[magic,cleanse],[slot(magic),slot(cleanse)]));
  List<RelicTriggerOutcome> fire(int Function(int) roll)=>a.resolveEvent(eventId:1,trigger:RelicTrigger.turnEnd,eligible:{magic.effect,cleanse.effect},nextInt:roll);
  var n=0;
  expect(()=>fire((_)=>(n++==0)?0:10000),throwsRangeError);
  expect(a.uses,isEmpty);expect(a.lastEvent,0);
  expect(()=>fire((_){fire((_)=>0);return 0;}),throwsStateError);
  expect(a.uses,isEmpty);expect(a.lastEvent,0);
  expect(()=>a.resolveEvent(eventId:1,trigger:RelicTrigger.turnEnd,eligible:{low.effect},nextInt:(_)=>0),throwsArgumentError);
  expect(()=>a.resolveEvent(eventId:1,trigger:RelicTrigger.lowHp,eligible:{low.effect},nextInt:(_)=>0),throwsStateError);
  final eligible={magic.effect,cleanse.effect};
  final result=a.resolveEvent(eventId:1,trigger:RelicTrigger.turnEnd,eligible:eligible,nextInt:(_){eligible.clear();return 0;});
  expect(result.map((o)=>o.effect),[magic.effect,cleanse.effect]);
  expect(()=>result.clear(),throwsUnsupportedError);
  expect(()=>fire((_)=>0),throwsStateError);expect(a.uses,{magic.effect:1,cleanse.effect:1});
 });
}
