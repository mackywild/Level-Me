import 'dart:math';
import 'abyss_equipment_effects.dart';
import 'abyss_equipment_skill_master.dart';
import 'abyss_relic_skill_master.dart';

/// Trial input only: ownership, milestone, seed and history authentication
/// must be supplied by the future inventory integration.
class RelicSkillContribution {
 const RelicSkillContribution({required this.skillId,required this.level});
 final String skillId;
 final int level;
}

class RelicResolvedEffect {
 const RelicResolvedEffect._(this.rule,this.chanceBps,this.magnitude);
 final RelicEffectRule rule;
 final int chanceBps,magnitude;
 RelicEffect get effect=>rule.effect;
}

/// Immutable aggregation of a single ordinary relic's (at most six) slots.
/// The input is not a verified equipped item or a persisted battle snapshot.
class RelicEffectSnapshot {
 RelicEffectSnapshot._(Map<RelicEffect,RelicResolvedEffect> effects):effects=Map.unmodifiable(effects);
 final Map<RelicEffect,RelicResolvedEffect> effects;

 factory RelicEffectSnapshot.resolve(RelicSkillMaster master,Iterable<RelicSkillContribution> contributions){
  final slots=contributions.take(7).toList();
  if(slots.length>6)throw ArgumentError('Too many ordinary relic skill slots');
  final rules=master.rules;
  final totals=<RelicEffect,RelicResolvedEffect>{};
  for(final slot in slots){
   final definition=master.require(slot.skillId);
   final rule=rules[definition.effect]!;
   final value=definition.valueAt(slot.level),old=totals[definition.effect];
   int merge(int a,int b,int cap)=>min(cap,rule.stacking==RelicStacking.additive?a+b:max(a,b));
   totals[definition.effect]=RelicResolvedEffect._(rule,
    merge(old?.chanceBps??0,value.chanceBps,rule.chanceCapBps),
    merge(old?.magnitude??0,value.magnitude,rule.magnitudeCap));
  }
  return RelicEffectSnapshot._(totals);
 }

 /// Continuous low-HP effect is deterministic, uses no random roll or count.
 /// Exact integer ratio avoids rounding and overflow at the threshold.
 int lowHpAttackBonus(int hp,int maxHp){
  if(maxHp<=0||hp<0||hp>maxHp)throw ArgumentError('Invalid relic HP condition');
  final resolved=effects[RelicEffect.lowHpAttack];
  if(resolved==null||hp==0)return 0;
  return BigInt.from(hp)*BigInt.from(10000)<=BigInt.from(maxHp)*BigInt.from(resolved.rule.hpThresholdBps!)?resolved.magnitude:0;
 }

 /// Q103: merge with the already aggregated ordinary/EX equipment attack
 /// bonus. Other battle modifiers are not modeled here.
 int attackBonus(EquipmentEffect effect,int existingBps,int hp,int maxHp){
  if(effect!=EquipmentEffect.physicalPercent&&effect!=EquipmentEffect.magicPercent)throw ArgumentError('Not an attack bonus');
  final cap=EquipmentSkillMaster.approvedCaps[effect]!;
  if(existingBps<0||existingBps>cap)throw ArgumentError('Invalid existing attack bonus');
  return min(cap,existingBps+lowHpAttackBonus(hp,maxHp));
 }
}

class RelicTriggerOutcome {
 const RelicTriggerOutcome._(this.effect,this.magnitude);
 final RelicEffect effect;
 final int magnitude;
}

/// In-memory trial resolver, not a save format or a battle command.
/// Caller supplies a monotonically increasing event serial and a frozen set
/// of effects applicable BEFORE the event. Results are a single batch, never
/// fed back into this resolver by it. Apply the entire batch on a future
/// battle working copy; caller must not create events from relic outcomes.
class RelicTriggerRuntime {
 RelicTriggerRuntime(this.snapshot);
 final RelicEffectSnapshot snapshot;
 final _uses=<RelicEffect,int>{};
 int _lastEvent=0;
 bool _started=false,_finished=false,_resolving=false;
 Map<RelicEffect,int> get uses=>Map.unmodifiable(_uses);
 int get lastEvent=>_lastEvent;

 /// Counts represent successful probability checks for caller-declared
 /// applicable effects. Ineligible/capped effects use no RNG. Guaranteed
 /// effects use no RNG; stochastic effects each get an independent roll.
 /// A failed RNG call commits neither event nor counts (external RNG rollback
 /// is the caller's responsibility).
 List<RelicTriggerOutcome> resolveEvent({required int eventId,required RelicTrigger trigger,required Set<RelicEffect> eligible,required int Function(int) nextInt}){
  if(_resolving)throw StateError('Recursive relic trigger');
  if(eventId<=_lastEvent||_finished||trigger==RelicTrigger.lowHp||(trigger==RelicTrigger.battleStart&&(_started||_lastEvent!=0))){
   throw StateError('Invalid relic event');
  }
  _resolving=true;
  try{
   final applicable=Set<RelicEffect>.of(eligible);
   if(applicable.any((e)=>e.trigger!=trigger))throw ArgumentError('Relic trigger mismatch');
   final nextUses=Map<RelicEffect,int>.of(_uses),outcomes=<RelicTriggerOutcome>[];
   // Canonical order independent of input order.
   for(final effect in RelicEffect.values){
    final resolved=snapshot.effects[effect];
    if(resolved==null||effect.trigger!=trigger||!applicable.contains(effect))continue;
    final used=nextUses[effect]??0,maxUses=resolved.rule.maxUses;
    if(maxUses!=null&&used>=maxUses)continue;
    if(resolved.chanceBps<10000){
     final roll=nextInt(10000);
     if(roll<0||roll>=10000)throw RangeError.range(roll,0,9999,'relic roll');
     if(roll>=resolved.chanceBps)continue;
    }
    if(used==0x7fffffffffffffff)throw StateError('Relic use count overflow');
    nextUses[effect]=used+1;
    outcomes.add(RelicTriggerOutcome._(effect,resolved.magnitude));
   }
   _uses..clear()..addAll(nextUses);
   _lastEvent=eventId;
   if(trigger==RelicTrigger.battleStart)_started=true;
   if(trigger==RelicTrigger.victory)_finished=true;
   return List.unmodifiable(outcomes);
  }finally{
   _resolving=false;
  }
 }
}


/// v1: recovery only. v2: conditional effects. v3: victory reward. Start=1; optional
/// lethal event=2*t; end=2*t+1. Only completed turns are persisted.
class RelicRecoveryBattleRuntime {
 RelicRecoveryBattleRuntime(RelicEffectSnapshot snapshot,{this.baseAttack}):_runtime=RelicTriggerRuntime(snapshot){
  if(snapshot.effects.isEmpty||expanded!=(baseAttack!=null)||
     (baseAttack!=null&&(baseAttack!.physical<1||baseAttack!.magic<1))){
   throw StateError('Unsupported relic battle effect or base attack');
  }
 }
 static const maxExpandedTurn=0x3fffffffffffffff;
 static bool requiresExpanded(RelicEffectSnapshot snapshot)=>snapshot.effects.keys.any((e)=>e==RelicEffect.lowHpAttack||e==RelicEffect.statusCleanse||e==RelicEffect.lethalSurvival||e==RelicEffect.victoryLifeReward);
 final RelicTriggerRuntime _runtime;
 final ({int physical,int magic})? baseAttack;
 bool get expanded=>requiresExpanded(_runtime.snapshot);
 bool get hasVictoryReward=>_runtime.snapshot.effects.containsKey(RelicEffect.victoryLifeReward);
 int get version=>hasVictoryReward?3:expanded?2:1;
 bool sameDefinition(RelicRecoveryBattleRuntime other){
  final a=_runtime.snapshot.effects,b=other._runtime.snapshot.effects;
  if(version!=other.version||a.length!=b.length)return false;
  return a.entries.every((entry){
   final x=entry.value,y=b[entry.key];
   return y!=null&&x.chanceBps==y.chanceBps&&x.magnitude==y.magnitude&&x.rule.maxUses==y.rule.maxUses&&x.rule.hpThresholdBps==y.rule.hpThresholdBps;
  });
 }
 int get lowHpMagnitude=>_runtime.snapshot.effects[RelicEffect.lowHpAttack]?.magnitude??0;
 int attackBonus(EquipmentEffect effect,int existingBps,int hp,int maxHp)=>_runtime.snapshot.attackBonus(effect,existingBps,hp,maxHp);
 Map<RelicEffect,int> get uses=>_runtime.uses;
 int _boundary(int turn)=>expanded?2*turn-1:turn;
 List<RelicTriggerOutcome> start({required bool missingHp,required int Function(int) nextInt})=>
  _runtime.resolveEvent(eventId:1,trigger:RelicTrigger.battleStart,eligible:{if(missingHp)RelicEffect.battleStartHeal},nextInt:nextInt);
 bool surviveLethal(int turn,int Function(int) nextInt){
  if(!expanded)return false;
  if(turn<1||turn>=maxExpandedTurn||_runtime.lastEvent!=_boundary(turn))throw StateError('Invalid relic lethal event');
  return _runtime.resolveEvent(eventId:2*turn,trigger:RelicTrigger.incomingLethal,eligible:{RelicEffect.lethalSurvival},nextInt:nextInt).isNotEmpty;
 }
 List<RelicTriggerOutcome> endTurn(int turn,{required bool missingMagic,bool poisoned=false,required int Function(int) nextInt}){
  if(turn<1||turn>=(expanded?maxExpandedTurn:0x7fffffffffffffff))throw StateError('Invalid relic turn sequence');
  final previous=_boundary(turn);
  if(_runtime.lastEvent!=previous&&(!expanded||_runtime.lastEvent!=previous+1))throw StateError('Invalid relic turn sequence');
  return _runtime.resolveEvent(eventId:_boundary(turn+1),trigger:RelicTrigger.turnEnd,eligible:{if(missingMagic)RelicEffect.turnEndMagicRecovery,if(poisoned&&expanded)RelicEffect.statusCleanse},nextInt:nextInt);
 }
 /// Victory is terminal and occurs before any incoming hit or turn-end event.
 int victoryLife(int turn,int Function(int) nextInt){
  if(!hasVictoryReward)return 0;
  if(turn<1||turn>=maxExpandedTurn||_runtime.lastEvent!=_boundary(turn))throw StateError('Invalid relic victory event');
  final outcomes=_runtime.resolveEvent(eventId:2*turn,trigger:RelicTrigger.victory,eligible:{RelicEffect.victoryLifeReward},nextInt:nextInt);
  return outcomes.isEmpty?0:outcomes.single.magnitude;
 }
 Map<String,dynamic> toJson()=>{'version':version,'lastEvent':_runtime.lastEvent,if(expanded)'baseAttack':{'physical':baseAttack!.physical,'magic':baseAttack!.magic},'effects':{
  for(final e in RelicEffect.values)
   if(_runtime.snapshot.effects[e] case final r?)
    e.name:{'chanceBps':r.chanceBps,'magnitude':r.magnitude,'maxUses':r.rule.maxUses,'uses':uses[e]??0,if(expanded&&e==RelicEffect.lowHpAttack)'hpThresholdBps':r.rule.hpThresholdBps},
 }};
 factory RelicRecoveryBattleRuntime.fromJson(Object? raw,int turn,{bool expanded=false,bool victoryReward=false}){
  if(victoryReward&&!expanded)throw const FormatException('Invalid relic victory version');
  if(raw is! Map<String,dynamic>||raw.length!=(expanded?4:3)||raw['version'] is! int||raw['version']!=(victoryReward?3:expanded?2:1)||turn<1||(expanded&&turn>maxExpandedTurn)||raw['lastEvent'] is! int||raw['lastEvent']!=(expanded?2*turn-1:turn)||raw['effects'] is! Map<String,dynamic>){
   throw const FormatException('Invalid relic battle state');
  }
  ({int physical,int magic})? base;
  if(expanded){
   final v=raw['baseAttack'];
   if(v is! Map<String,dynamic>||v.length!=2||v['physical'] is! int||v['magic'] is! int||(v['physical'] as int)<1||(v['magic'] as int)<1)throw const FormatException('Invalid relic base attack');
   base=(physical:v['physical'] as int,magic:v['magic'] as int);
  }
  final entries=raw['effects'] as Map<String,dynamic>;
  if(entries.isEmpty||entries.length>(victoryReward?6:expanded?5:2))throw const FormatException('Invalid relic battle effects');
  final effects=<RelicEffect,RelicResolvedEffect>{},uses=<RelicEffect,int>{};
  for(final entry in entries.entries){
   final effect=switch(entry.key){
    'battleStartHeal'=>RelicEffect.battleStartHeal,
    'turnEndMagicRecovery'=>RelicEffect.turnEndMagicRecovery,
    'lowHpAttack' when expanded=>RelicEffect.lowHpAttack,
    'statusCleanse' when expanded=>RelicEffect.statusCleanse,
    'lethalSurvival' when expanded=>RelicEffect.lethalSurvival,
    'victoryLifeReward' when victoryReward=>RelicEffect.victoryLifeReward,
    _=>throw const FormatException('Unsupported relic battle effect'),
   };
   final low=effect==RelicEffect.lowHpAttack,v=entry.value;
   if(v is! Map<String,dynamic>||v.length!=(low?5:4)||v['chanceBps'] is! int||v['magnitude'] is! int||v['uses'] is! int||!v.containsKey('maxUses')||(v['maxUses']!=null&&v['maxUses'] is! int)||(low&&v['hpThresholdBps'] is! int)){
    throw const FormatException('Invalid relic effect fields');
   }
   final chance=v['chanceBps'] as int,amount=v['magnitude'] as int,count=v['uses'] as int,limit=v['maxUses'] as int?;
   if(count<0||count>(low||effect==RelicEffect.victoryLifeReward?0:effect==RelicEffect.battleStartHeal?1:turn-1)||(limit!=null&&count>limit)){
    throw const FormatException('Invalid relic use history');
   }
   try{
    final rule=RelicEffectRule(effect:effect,stacking:RelicStacking.highestOnly,chanceCapBps:chance,magnitudeCap:amount,maxUses:limit,hpThresholdBps:low?v['hpThresholdBps'] as int:null);
    effects[effect]=RelicResolvedEffect._(rule,chance,amount);
   }on ArgumentError{
    throw const FormatException('Invalid relic battle definition');
   }
   if(count>0)uses[effect]=count;
  }
  final snapshot=RelicEffectSnapshot._(effects);
  if(requiresExpanded(snapshot)!=expanded||effects.containsKey(RelicEffect.victoryLifeReward)!=victoryReward)throw const FormatException('Relic effect version mismatch');
  final result=RelicRecoveryBattleRuntime(snapshot,baseAttack:base);
  result._runtime._uses.addAll(uses);
  result._runtime._lastEvent=expanded?2*turn-1:turn;
  result._runtime._started=true;
  return result;
 }
}
