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


/// Trial battle adapter for the two connected recovery effects only.
/// Event 1 is start; completed turn t has event t+1. An active save at
/// turn t therefore must have lastEvent=t. Victory/defeat/retreat discard
/// the entire adapter. Definitions are resolved values, not ownership proof.
class RelicRecoveryBattleRuntime {
 RelicRecoveryBattleRuntime(RelicEffectSnapshot snapshot):_runtime=RelicTriggerRuntime(snapshot){
  if(snapshot.effects.isEmpty||snapshot.effects.keys.any((e)=>e!=RelicEffect.battleStartHeal&&e!=RelicEffect.turnEndMagicRecovery)){
   throw StateError('Unsupported relic battle effect');
  }
 }
 final RelicTriggerRuntime _runtime;
 Map<RelicEffect,int> get uses=>_runtime.uses;

 List<RelicTriggerOutcome> start({required bool missingHp,required int Function(int) nextInt})=>
  _runtime.resolveEvent(eventId:1,trigger:RelicTrigger.battleStart,eligible:{if(missingHp)RelicEffect.battleStartHeal},nextInt:nextInt);
 List<RelicTriggerOutcome> endTurn(int turn,{required bool missingMagic,required int Function(int) nextInt}){
  if(turn<1||turn==0x7fffffffffffffff||_runtime.lastEvent!=turn)throw StateError('Invalid relic turn sequence');
  return _runtime.resolveEvent(eventId:turn+1,trigger:RelicTrigger.turnEnd,eligible:{if(missingMagic)RelicEffect.turnEndMagicRecovery},nextInt:nextInt);
 }

 Map<String,dynamic> toJson()=>{'version':1,'lastEvent':_runtime.lastEvent,'effects':{
  for(final e in RelicEffect.values)
   if(_runtime.snapshot.effects[e] case final r?)
    e.name:{'chanceBps':r.chanceBps,'magnitude':r.magnitude,'maxUses':r.rule.maxUses,'uses':uses[e]??0},
 }};
 factory RelicRecoveryBattleRuntime.fromJson(Object? raw,int turn){
  if(raw is! Map<String,dynamic>||raw.length!=3||raw['version'] is! int||raw['version']!=1||raw['lastEvent'] is! int||raw['lastEvent']!=turn||turn<1||raw['effects'] is! Map<String,dynamic>){
   throw const FormatException('Invalid relic battle state');
  }
  final entries=raw['effects'] as Map<String,dynamic>;
  if(entries.isEmpty||entries.length>2)throw const FormatException('Invalid relic recovery effects');
  final effects=<RelicEffect,RelicResolvedEffect>{},uses=<RelicEffect,int>{};
  for(final entry in entries.entries){
   final effect=switch(entry.key){
    'battleStartHeal'=>RelicEffect.battleStartHeal,
    'turnEndMagicRecovery'=>RelicEffect.turnEndMagicRecovery,
    _=>throw const FormatException('Unsupported relic battle effect'),
   };
   final v=entry.value;
   if(v is! Map<String,dynamic>||v.length!=4||v['chanceBps'] is! int||v['magnitude'] is! int||v['uses'] is! int||!v.containsKey('maxUses')||(v['maxUses']!=null&&v['maxUses'] is! int)){
    throw const FormatException('Invalid relic effect fields');
   }
   final chance=v['chanceBps'] as int,amount=v['magnitude'] as int,count=v['uses'] as int,limit=v['maxUses'] as int?;
   if(count<0||count>(effect==RelicEffect.battleStartHeal?1:turn-1)||(limit!=null&&count>limit)){
    throw const FormatException('Invalid relic use history');
   }
   try{
    final rule=RelicEffectRule(effect:effect,stacking:RelicStacking.highestOnly,chanceCapBps:chance,magnitudeCap:amount,maxUses:limit);
    effects[effect]=RelicResolvedEffect._(rule,chance,amount);
   }on ArgumentError{
    throw const FormatException('Invalid relic recovery definition');
   }
   if(count>0)uses[effect]=count;
  }
  final result=RelicRecoveryBattleRuntime(RelicEffectSnapshot._(effects));
  result._runtime._uses.addAll(uses);
  result._runtime._lastEvent=turn;
  result._runtime._started=true;
  return result;
 }
}
