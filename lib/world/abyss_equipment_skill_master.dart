import 'abyss_inventory.dart';
import 'abyss_equipment_effects.dart';
import 'abyss_equipment_skill_pool.dart';
import 'abyss_ex_equipment_skill.dart';

/// DEC-016: 承認済み分類・比例曲線・上限の統一入口。
/// 具体的なID、希少度、Lv1性能と未承認上限は外部から注入する。
class EquipmentSkillMasterEntry {
 const EquipmentSkillMasterEntry({required this.id,required this.rarity,required this.pool,required this.effect,required this.perLevel});
 final String id;
 final EquipmentSkillRarity rarity;
 final EquipmentSkillPool pool;
 final EquipmentEffect effect;
 final int perLevel;
}

class EquipmentSkillMaster {
 EquipmentSkillMaster(Iterable<EquipmentSkillMasterEntry> entries,{Map<EquipmentEffect,int> additionalCaps=const {}}){
  final caps=Map<EquipmentEffect,int>.of(approvedCaps);
  for(final entry in additionalCaps.entries){
   if(approvedCaps.containsKey(entry.key))throw ArgumentError('Approved cap cannot be overridden');
   caps[entry.key]=entry.value;
  }
  final rules=<String,EquipmentEffectRule>{};
  final candidates=<EquipmentSkillCandidate>[];
  for(final entry in entries){
   if(!entry.id.startsWith('equipment_skill:')||entry.id.length<=16||entry.id.trim()!=entry.id||
      rules.containsKey(entry.id)||!allowedEffects(entry.pool).contains(entry.effect)||
      entry.perLevel<=0||entry.perLevel>100000||!caps.containsKey(entry.effect)){
    throw ArgumentError('Invalid equipment skill master');
   }
   rules[entry.id]=EquipmentEffectRule(effect:entry.effect,pool:entry.pool,
    levelValues:List.generate(10,(i)=>entry.perLevel*(i+1)));
   candidates.add(EquipmentSkillCandidate(id:entry.id,pool:entry.pool,rarity:entry.rarity));
  }
  effectPolicy=EquipmentEffectPolicy(rules:rules,caps:caps);
  candidates.sort((a,b)=>a.id.compareTo(b.id));
  _odds=EquipmentSkillPoolOdds(candidates);
  this.entries=List.unmodifiable(entriesFrom(candidates,rules));
 }
 static const version=1;
 static const approvedCaps=<EquipmentEffect,int>{
  EquipmentEffect.physicalPercent:30000,EquipmentEffect.magicPercent:30000,EquipmentEffect.defensePercent:30000,
  EquipmentEffect.damageReduction:7000,EquipmentEffect.criticalChance:10000,EquipmentEffect.evasionChance:5000,
  EquipmentEffect.energyDiscount:5000,EquipmentEffect.cooldownReduction:5000,EquipmentEffect.extraAttackChance:5000,
  EquipmentEffect.hpPercent:30000,EquipmentEffect.penetration:5000,EquipmentEffect.resistance:8000,EquipmentEffect.naturalRecovery:30000,EquipmentEffect.rewardPercent:10000,
 };
 static Set<EquipmentEffect> allowedEffects(EquipmentSkillPool pool)=>switch(pool){
  EquipmentSkillPool.attack=>const {EquipmentEffect.physicalPercent,EquipmentEffect.magicPercent,EquipmentEffect.criticalChance,EquipmentEffect.extraAttackChance,EquipmentEffect.penetration},
  EquipmentSkillPool.defense=>const {EquipmentEffect.defensePercent,EquipmentEffect.hpPercent,EquipmentEffect.damageReduction,EquipmentEffect.evasionChance,EquipmentEffect.resistance},
  EquipmentSkillPool.special=>const {EquipmentEffect.energyDiscount,EquipmentEffect.cooldownReduction,EquipmentEffect.naturalRecovery,EquipmentEffect.rewardPercent},
  // 魔遺物固有効果は意味・性能未承認。通常効果を流用しない。
  EquipmentSkillPool.relic=>const {},
 };
 late final EquipmentEffectPolicy effectPolicy;
 late final EquipmentSkillPoolOdds _odds;
 late final List<EquipmentSkillMasterEntry> entries;
 static Iterable<EquipmentSkillMasterEntry> entriesFrom(List<EquipmentSkillCandidate> candidates,Map<String,EquipmentEffectRule> rules)=>candidates.map((c)=>EquipmentSkillMasterEntry(id:c.id,rarity:c.rarity,pool:c.pool,effect:rules[c.id]!.effect,perLevel:rules[c.id]!.levelValues.first));

 void validateInventory(AbyssInventory inventory,{bool allowRelicHistory=false}){
  if(inventory.exSkillLayouts.isNotEmpty)throw StateError('EX inventory requires EX-aware controller');
  validateNormalInventory(inventory,allowRelicHistory:allowRelicHistory);
 }
 void validateNormalInventory(AbyssInventory inventory,{bool allowRelicHistory=false}){
  for(final entry in inventory.equipmentSkillHistories.entries){
   final item=inventory.equipment[entry.key]!;
   if(item.rarity==EquipmentRarity.ex)continue;
   if(entry.value.relicFingerprint!=null){
    if(!allowRelicHistory)throw const FormatException('Relic skill master unavailable');
    continue;
   }
   for(final grant in entry.value.grants){
    if(!entries.any((e)=>e.id==grant.skillId&&e.pool==EquipmentSkillPoolOdds.poolForSlot(item.slot))||grant.ruleVersion!=version){
     throw const FormatException('Equipment skill master mismatch');
    }
   }
  }
 }
 bool hasCandidates(EquipmentSlot slot)=>_odds.totalWeight(EquipmentSkillPoolOdds.poolForSlot(slot))>0;

 /// 既存の版1帯確率を維持し、EXは明示的な個別構成に限りGRを使用する。
 /// ここでは確定保存・強化は行わない。
 ({EquipmentSkillCandidate skill,int level}) draw(EquipmentInstance item,int Function(int) nextInt,{ExEquipmentSkillLayout? exLayout}){
  if(item.rarity==EquipmentRarity.ex){
   if(exLayout==null)throw StateError('EX layout required');
   final fixedIds=exLayout.unlockedFixedSkills(item).map((skill)=>skill.id).toSet();
   if(entries.any((entry)=>fixedIds.contains(entry.id)))throw StateError('EX fixed skill conflicts with random candidate');
  }else if(exLayout!=null){
   throw StateError('EX layout on non-EX equipment');
  }
  final result=_odds.drawWithLevelBand(item.slot,item.rarity==EquipmentRarity.ex?EquipmentRarity.gr:item.rarity,nextInt);
  final width=result.band.maximum-result.band.minimum+1;
  final offset=width==1?0:nextInt(width);
  if(offset<0||offset>=width)throw RangeError.range(offset,0,width-1,'level roll');
  return (skill:result.skill,level:result.band.minimum+offset);
 }
}
