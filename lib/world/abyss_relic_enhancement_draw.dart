import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'abyss_inventory.dart';
import 'abyss_equipment_skill_policy.dart';
import 'abyss_relic_skill_master.dart';
import 'abyss_relic_trigger_runtime.dart';

/// A distinct deterministic draw domain; no reroll when a save is retried.
class RelicEnhancementDraw {
 const RelicEnhancementDraw._();
 static String fingerprint(RelicSkillMaster master){
  final skills=master.skills.values.toList()..sort((a,b)=>a.id.compareTo(b.id));
  final rules=master.rules.values.toList()..sort((a,b)=>a.effect.name.compareTo(b.effect.name));
  return sha256.convert(utf8.encode(jsonEncode(['relic-master',RelicSkillMaster.version,
   for(final r in rules)[r.effect.name,r.stacking.name,r.chanceCapBps,r.magnitudeCap,r.maxUses,r.hpThresholdBps],
   for(final s in skills)[s.id,s.name,s.rarity.name,s.effect.name,s.chanceBpsByLevel,s.magnitudeByLevel],
  ]))).toString();
 }
 static StoredEquipmentSkill? prepare(AbyssInventory inventory,EquipmentInstance item,RelicSkillMaster master){
  if(item.slot!=EquipmentSlot.relic||item.rarity==EquipmentRarity.ex||inventory.equipmentSkillSeed==null||!identical(inventory.equipment[item.id],item))throw StateError('Invalid relic draw owner');
  final history=inventory.equipmentSkillHistories[item.id];
  if(history==null)throw StateError('Relic history missing');
  validateHistory(inventory,item,master);
  final milestone=EquipmentSkillPolicy.nextGrant(item.rarity,item.enhancement,item.enhancement+1);
  return milestone==null?null:_draw(inventory.equipmentSkillSeed!,item,master,milestone);
 }
 static StoredEquipmentSkill _draw(int seed,EquipmentInstance item,RelicSkillMaster master,int milestone){
  final serial=int.parse(item.id.substring(3));
  const purposes=['rarity','candidate','levelBand','levelWithinBand'];
  var index=0;
  int nextInt(int bound){
   const range=0x100000000;
   if(bound<=0||bound>range||index>=purposes.length)throw StateError('Invalid relic draw bound');
   final purpose=purposes[index++],limit=range-range%bound;
   for(var attempt=0;;attempt++){
    final bytes=sha256.convert(utf8.encode('relic-skill-draw:v1:$seed:$serial:$milestone:$purpose:$attempt')).bytes;
    final value=((bytes[0]*256+bytes[1])*256+bytes[2])*256+bytes[3];
    if(value<limit)return value%bound;
   }
  }
  final result=master.draw(item,nextInt);
  return StoredEquipmentSkill(milestone:milestone,skillId:result.skill.id,level:result.level,ruleVersion:RelicSkillMaster.version);
 }
 static void validateHistory(AbyssInventory inventory,EquipmentInstance item,RelicSkillMaster master){
  final history=inventory.equipmentSkillHistories[item.id];
  if(history==null||history.grants.isEmpty)return;
  final seed=inventory.equipmentSkillSeed;
  if(item.slot!=EquipmentSlot.relic||item.rarity==EquipmentRarity.ex||seed==null||history.relicFingerprint!=fingerprint(master))throw const FormatException('Relic master mismatch');
  for(final grant in history.grants){
   final expected=_draw(seed,item,master,grant.milestone);
   if(expected.skillId!=grant.skillId||expected.level!=grant.level||expected.ruleVersion!=grant.ruleVersion)throw const FormatException('Relic deterministic grant mismatch');
  }
 }
 static void validateInventory(AbyssInventory inventory,RelicSkillMaster master){
  for(final entry in inventory.equipmentSkillHistories.entries){
   if(entry.value.relicFingerprint!=null)validateHistory(inventory,inventory.equipment[entry.key]!,master);
  }
 }
 static RelicEffectSnapshot? equipped(AbyssInventory inventory,RelicSkillMaster master){
  validateInventory(inventory,master);
  final id=inventory.equipped[EquipmentSlot.relic],history=inventory.equipmentSkillHistories[id];
  if(history?.relicFingerprint==null)return null;
  return RelicEffectSnapshot.resolve(master,history!.grants.map((g)=>RelicSkillContribution(skillId:g.skillId,level:g.level)));
 }
}
