import 'abyss_inventory.dart';
import 'abyss_equipment_skill_pool.dart';

/// Q96–101: finite effect vocabulary. There is no arbitrary effect script,
/// active command, or protagonist time authority in this master.
enum RelicEffect {
 battleStartHeal, turnEndMagicRecovery, lowHpAttack,
 statusCleanse, lethalSurvival, victoryLifeReward,
}
enum RelicTrigger { battleStart, turnEnd, lowHp, incomingLethal, victory }
enum RelicStacking { additive, highestOnly }
enum RelicMagnitudeUnit { maxHpBps, magicEnergy, attackBps, none, lifeDays }

extension RelicEffectMetadata on RelicEffect {
 RelicTrigger get trigger=>switch(this){
  RelicEffect.battleStartHeal=>RelicTrigger.battleStart,
  RelicEffect.turnEndMagicRecovery||RelicEffect.statusCleanse=>RelicTrigger.turnEnd,
  RelicEffect.lowHpAttack=>RelicTrigger.lowHp,
  RelicEffect.lethalSurvival=>RelicTrigger.incomingLethal,
  RelicEffect.victoryLifeReward=>RelicTrigger.victory,
 };
 RelicMagnitudeUnit get unit=>switch(this){
  RelicEffect.battleStartHeal=>RelicMagnitudeUnit.maxHpBps,
  RelicEffect.turnEndMagicRecovery=>RelicMagnitudeUnit.magicEnergy,
  RelicEffect.lowHpAttack=>RelicMagnitudeUnit.attackBps,
  RelicEffect.statusCleanse||RelicEffect.lethalSurvival=>RelicMagnitudeUnit.none,
  RelicEffect.victoryLifeReward=>RelicMagnitudeUnit.lifeDays,
 };
 // Defensive ceilings, not approved per-effect balance values.
 int get maximumMagnitude=>switch(unit){
  RelicMagnitudeUnit.maxHpBps=>10000,
  RelicMagnitudeUnit.attackBps=>30000,
  RelicMagnitudeUnit.none=>0,
  RelicMagnitudeUnit.magicEnergy||RelicMagnitudeUnit.lifeDays=>1000000,
 };
}

/// One aggregation rule per effect. A successful trigger consumes at most one
/// use of this effect, not one use per contributing random slot (future runtime).
class RelicEffectRule {
 RelicEffectRule({required this.effect,required this.stacking,required this.chanceCapBps,required this.magnitudeCap,this.maxUses,this.hpThresholdBps}){
  if(chanceCapBps<=0||chanceCapBps>10000||magnitudeCap<0||magnitudeCap>effect.maximumMagnitude||
     (effect.unit==RelicMagnitudeUnit.none?magnitudeCap!=0:magnitudeCap==0)||
     (maxUses!=null&&(maxUses!<1||maxUses!>1000))){
   throw ArgumentError('Invalid relic effect rule');
  }
  if(effect==RelicEffect.lowHpAttack){
   if(hpThresholdBps==null||hpThresholdBps!<=0||hpThresholdBps!>=10000||chanceCapBps!=10000||maxUses!=null){
    throw ArgumentError('Invalid continuous relic condition');
   }
  }else if(hpThresholdBps!=null){
   throw ArgumentError('Unexpected relic HP condition');
  }
  if((effect==RelicEffect.battleStartHeal||effect==RelicEffect.victoryLifeReward)&&maxUses!=1){
   throw ArgumentError('Single-event relic rule requires one use');
  }
 }
 final RelicEffect effect;
 final RelicStacking stacking;
 final int chanceCapBps,magnitudeCap;
 final int? maxUses,hpThresholdBps;
}

/// Explicit immutable Lv1..10 curves allow proportional, flat and per-level
/// values without hardcoding any production skill strength.
class RelicSkillDefinition {
 RelicSkillDefinition({required this.id,required this.name,required this.rarity,required this.effect,required Iterable<int> chanceBpsByLevel,required Iterable<int> magnitudeByLevel}):
  chanceBpsByLevel=List.unmodifiable(chanceBpsByLevel),magnitudeByLevel=List.unmodifiable(magnitudeByLevel){
  if(!id.startsWith('equipment_relic_skill:')||id.length<='equipment_relic_skill:'.length||id.trim()!=id||RegExp(r'\s').hasMatch(id)||name.trim().isEmpty||
     this.chanceBpsByLevel.length!=10||this.magnitudeByLevel.length!=10||
     this.chanceBpsByLevel.any((v)=>v<=0||v>10000)||
     this.magnitudeByLevel.any((v)=>v<0||v>effect.maximumMagnitude||(effect.unit!=RelicMagnitudeUnit.none&&v==0))){
   throw ArgumentError('Invalid relic skill definition');
  }
  if(effect==RelicEffect.lowHpAttack&&this.chanceBpsByLevel.any((v)=>v!=10000)){
   throw ArgumentError('Continuous relic effect must be deterministic');
  }
 }
 final String id,name;
 final EquipmentSkillRarity rarity;
 final RelicEffect effect;
 final List<int> chanceBpsByLevel,magnitudeByLevel;
 ({int chanceBps,int magnitude}) valueAt(int level){
  if(level<1||level>10)throw RangeError.range(level,1,10,'level');
  return (chanceBps:chanceBpsByLevel[level-1],magnitude:magnitudeByLevel[level-1]);
 }
}

/// Separate from ordinary EquipmentSkillMaster and EX definitions.
/// No save writes, battle execution, controller injection or production IDs.
class RelicSkillMaster {
 RelicSkillMaster({required Iterable<RelicEffectRule> rules,required Iterable<RelicSkillDefinition> skills}){
  for(final rule in rules){
   if(_rules.containsKey(rule.effect))throw ArgumentError('Duplicate relic effect rule');
   _rules[rule.effect]=rule;
  }
  for(final skill in skills){
   final rule=_rules[skill.effect];
   if(rule==null||_skills.containsKey(skill.id)||skill.chanceBpsByLevel.any((v)=>v>rule.chanceCapBps)||skill.magnitudeByLevel.any((v)=>v>rule.magnitudeCap)){
    throw ArgumentError('Invalid relic skill registration');
   }
   _skills[skill.id]=skill;
  }
  final sorted=_skills.values.toList()..sort((a,b)=>a.id.compareTo(b.id));
  _odds=EquipmentSkillPoolOdds(sorted.map((s)=>EquipmentSkillCandidate(id:s.id,pool:EquipmentSkillPool.relic,rarity:s.rarity)));
 }
 static const version=1;
 final _rules=<RelicEffect,RelicEffectRule>{};
 final _skills=<String,RelicSkillDefinition>{};
 late final EquipmentSkillPoolOdds _odds;
 Map<RelicEffect,RelicEffectRule> get rules=>Map.unmodifiable(_rules);
 Map<String,RelicSkillDefinition> get skills=>Map.unmodifiable(_skills);
 bool get hasCandidates=>_odds.totalWeight(EquipmentSkillPool.relic)>0;
 RelicSkillDefinition require(String id){
  final skill=_skills[id];
  if(skill==null)throw StateError('Unknown relic skill');
  return skill;
 }
 /// Existing rarity and level-band rules, with a separate roll for the
 /// candidate and the level. EX relics require a separately approved layout.
 ({RelicSkillDefinition skill,int level}) draw(EquipmentInstance item,int Function(int) nextInt){
  if(item.slot!=EquipmentSlot.relic||item.rarity==EquipmentRarity.ex)throw StateError('Ordinary relic required');
  final result=_odds.drawWithLevelBand(item.slot,item.rarity,nextInt);
  final width=result.band.maximum-result.band.minimum+1;
  final offset=width==1?0:nextInt(width);
  if(offset<0||offset>=width)throw RangeError.range(offset,0,width-1,'level roll');
  return (skill:require(result.skill.id),level:result.band.minimum+offset);
 }
}
