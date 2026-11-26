import 'abyss_equipment.dart';
import 'abyss_equipment_effects.dart';
import 'abyss_equipment_skill_master.dart';
import 'abyss_equipment_enhancement_draw.dart';
import 'abyss_enhancement.dart';
import 'abyss_ex_equipment_master.dart';
import 'abyss_inventory.dart';
import 'world_engine.dart';

class ExAcquisitionOffer {
 const ExAcquisitionOffer({required this.id,required this.masterId,required this.magicCrystals});
 final String id,masterId;
 final int magicCrystals;
}
class ExEnhancementRecipe {
 const ExEnhancementRecipe({required this.masterId,required this.materials,required this.gold});
 final String masterId;
 final ExEnhancementMaterialPlan materials;
 final int gold;
}

/// Explicit injection only. No production offers or recipes.
class ExEquipmentTransactionPolicy {
 ExEquipmentTransactionPolicy({required this.master,this.enableAutomaticEffects=false,required Iterable<String> normalMaterials,required Iterable<String> exMaterials,required Iterable<ExEnhancementRecipe> recipes,required Iterable<ExAcquisitionOffer> offers}){
  final normal=normalMaterials.toSet(),special=exMaterials.toSet();
  bool valid(String id)=>id.startsWith('item:')&&id.length>5&&id.trim()==id;
  if(normal.intersection(special).isNotEmpty||[...normal,...special].any((id)=>!valid(id)))throw const FormatException('Invalid EX material classification');
  for(final recipe in recipes){
   if(!master.layouts.containsKey(recipe.masterId)||_recipes.containsKey(recipe.masterId)||recipe.gold<=0||recipe.gold>1000000||!normal.contains(recipe.materials.normalMaterialId)||!special.contains(recipe.materials.exMaterialId))throw const FormatException('Invalid EX recipe');
   _recipes[recipe.masterId]=recipe;
  }
  for(final offer in offers){
   if(!offer.id.startsWith('ex_offer:')||offer.id.length<=9||offer.id.trim()!=offer.id||_offers.containsKey(offer.id)||!_recipes.containsKey(offer.masterId)||offer.magicCrystals<=0||offer.magicCrystals>1000000)throw const FormatException('Invalid EX acquisition offer');
   _offers[offer.id]=offer;
  }
 }
 final ExEquipmentMaster master;
 final bool enableAutomaticEffects;
 final _recipes=<String,ExEnhancementRecipe>{};
 final _offers=<String,ExAcquisitionOffer>{};
 ExEnhancementRecipe? recipe(String masterId)=>_recipes[masterId];
 void validateInventory(AbyssInventory inventory,EquipmentCatalog catalog){
  master.randomMaster.validateNormalInventory(inventory);
  for(final item in inventory.equipment.values.where((e)=>e.rarity==EquipmentRarity.ex)){
   catalog.require(item);
   if(inventory.equipped.containsValue(item.id))requireEquippable(inventory,item);
   EquipmentEnhancementDraw.validateExHistory(inventory,item,master);
   final recipe=_recipes[item.masterId];
   if(recipe==null)throw const FormatException('EX recipe unavailable');
   final costs=inventory.enhancementCostsFor(item.id);
   if(costs.length!=item.enhancement)throw const FormatException('EX costs missing');
   for(var i=0;i<costs.length;i++){
    final expected=recipe.materials.materialsFor(i),actual=costs[i];
    if(actual.length!=expected.length||expected.entries.any((e)=>actual[e.key]!=e.value))throw const FormatException('EX cost history mismatch');
   }
  }
 }
 /// Only explicitly enabled, same-pool automatic normal effects with shared caps.
 void requireEquippable(AbyssInventory inventory,EquipmentInstance item){
  if(!enableAutomaticEffects)throw StateError('EX fixed effects not connected');
  final layout=master.validateInstance(inventory,item);
  for(final fixed in master.resolveFixedSkills(item)){
   if(fixed.skill.activation!=ExSkillActivation.automatic)throw StateError('EX manual skill not connected');
   for(final effect in fixed.skill.effects){
    final rule=master.effectRules[effect.ruleId]!;
    final normal=rule.normalEffect;
    if(effect.drawback||normal==null||rule.capScope!=ExEffectCapScope.sharedWithNormal||
       !EquipmentSkillMaster.allowedEffects(layout.randomPool).contains(normal)){
     throw StateError('EX fixed effect not connected');
    }
   }
  }
 }
 EquipmentEffectSnapshot snapshot(AbyssInventory inventory){
  final random=master.randomMaster.effectPolicy.snapshot(inventory,[
   for(final entry in inventory.equipmentSkillHistories.entries)
    if(inventory.equipment[entry.key]!.rarity!=EquipmentRarity.ex||enableAutomaticEffects)
     for(final grant in entry.value.grants)
      EquipmentSkillGrant(instanceId:entry.key,milestone:grant.milestone,skillId:grant.skillId,level:grant.level),
  ],includeRegisteredEx:enableAutomaticEffects);
  final totals=<EquipmentEffect,int>{};
  for(final id in inventory.equipped.values){
   final item=inventory.equipment[id]!;
   if(item.rarity!=EquipmentRarity.ex)continue;
   requireEquippable(inventory,item);
   for(final fixed in master.resolveFixedSkills(item)){
    for(final effect in fixed.skill.effects){
     final rule=master.effectRules[effect.ruleId]!,normal=master.effectRules[effect.ruleId]!.normalEffect!;
     final value=effect.valuesByLevel[fixed.level]!;
     final old=totals[normal]??0;
     final sum=rule.stacking==ExEffectStacking.additive?old+value:(old>value?old:value);
     totals[normal]=sum>rule.cap?rule.cap:sum;
    }
   }
  }
  return master.randomMaster.effectPolicy.mergeSharedFixed(random,totals);
 }
 ExAcquisitionOffer validateAcquisition(WorldState world,EquipmentCatalog catalog,String offerId,int expectedSequence){
  if(world.battle!=null)throw StateError('EX acquisition unavailable in battle');
  if(world.shopSequence!=expectedSequence||world.shopSequence==0x7fffffffffffffff)throw StateError('Stale EX acquisition request');
  final offer=_offers[offerId];
  if(offer==null)throw StateError('EX offer unavailable');
  final layout=master.layouts[offer.masterId]!;
  final definition=catalog.find(offer.masterId);
  if(definition==null||definition.rarity!=EquipmentRarity.ex||definition.slot!=layout.slot)throw StateError('EX equipment master mismatch');
  if(world.magicCrystals<offer.magicCrystals)throw StateError('Insufficient shop currency');
  return offer;
 }
 EquipmentInstance acquire(WorldState world,AbyssInventory inventory,EquipmentCatalog catalog,String offerId,int expectedSequence){
  final offer=validateAcquisition(world,catalog,offerId,expectedSequence);
  final item=master.acquire(inventory,offer.masterId);
  world.magicCrystals-=offer.magicCrystals;
  world.shopSequence++;
  return item;
 }
 ExEnhancementRecipe validateEnhancement(WorldState world,AbyssInventory inventory,EquipmentCatalog catalog,String id,int expectedLevel){
  if(world.battle!=null)throw StateError('Enhancement unavailable in battle');
  final item=inventory.equipment[id];
  if(item==null||item.rarity!=EquipmentRarity.ex||item.enhancement!=expectedLevel)throw StateError('Invalid EX enhancement request');
  if(expectedLevel<0||expectedLevel>=20)throw StateError('Enhancement limit reached');
  validateInventory(inventory,catalog);
  final recipe=_recipes[item.masterId]!;
  if(world.gold<recipe.gold)throw StateError('Insufficient gold');
  if(recipe.materials.materialsFor(expectedLevel).entries.any((e)=>(inventory.stacks[e.key]??0)<e.value))throw StateError('Insufficient materials');
  return recipe;
 }
 EquipmentInstance enhance(WorldState world,AbyssInventory inventory,EquipmentCatalog catalog,String id,int expectedLevel){
  final recipe=validateEnhancement(world,inventory,catalog,id,expectedLevel);
  final item=inventory.equipment[id]!;
  final grant=EquipmentEnhancementDraw.prepare(inventory,item,master.randomMaster,exMaster:master);
  final result=inventory.enhanceWithMaterials(id,expectedLevel,recipe.materials.materialsFor(expectedLevel),skillGrant:grant);
  world.gold-=recipe.gold;
  return result;
 }
}
