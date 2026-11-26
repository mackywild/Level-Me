import 'abyss_inventory.dart';
import 'abyss_equipment.dart';
import 'world_engine.dart';

class EnhancementRecipe {
 const EnhancementRecipe({required this.rarity,required this.materialId,required this.quantity,required this.gold});
 final EquipmentRarity rarity;
 final String materialId;
 final int quantity,gold;
}

/// 承認済みの増加方針。具体的な20段階の必要数はマスターから注入する。
/// 既存の試験用固定レシピとは明示的に区別する。
class EnhancementMaterialSchedule {
 EnhancementMaterialSchedule(Iterable<int> quantities):quantities=List.unmodifiable(quantities){
  if(this.quantities.length!=20)throw const FormatException('Expected 20 enhancement quantities');
  var previous=0;
  for(final quantity in this.quantities){
   if(quantity<=previous||quantity>1000000)throw const FormatException('Invalid increasing enhancement quantities');
   previous=quantity;
  }
 }
 final List<int> quantities;
 int quantityFor(int currentLevel){
  if(currentLevel<0||currentLevel>=20)throw RangeError.range(currentLevel,0,19,'currentLevel');
  return quantities[currentLevel];
 }
}

class EnhancementPolicy {
 EnhancementPolicy(Iterable<EnhancementRecipe> recipes,{Map<EquipmentRarity,EnhancementMaterialSchedule> schedules=const {}}):_schedules=Map.unmodifiable(schedules){
  for(final recipe in recipes){
   if(!recipe.materialId.startsWith('item:')||recipe.materialId.length<=5||recipe.quantity<=0||recipe.quantity>1000000||recipe.gold<=0||recipe.gold>1000000||_recipes.containsKey(recipe.rarity)){
    throw const FormatException('Invalid enhancement recipe');
   }
   _recipes[recipe.rarity]=recipe;
  }
  for(final entry in _schedules.entries){
   if(_recipes[entry.key]?.quantity!=entry.value.quantities.first)throw const FormatException('Enhancement schedule requires matching base recipe');
  }
 }
 final Map<EquipmentRarity,EnhancementMaterialSchedule> _schedules;
 final _recipes=<EquipmentRarity,EnhancementRecipe>{};
 // 費用・素材の正式承認までは本番の強化を無効にする。
 static final production=EnhancementPolicy(const []);
 EnhancementRecipe? recipe(EquipmentRarity rarity)=>_recipes[rarity];
 EnhancementRecipe? recipeFor(EquipmentRarity rarity,int currentLevel){
  if(currentLevel<0||currentLevel>=20)throw RangeError.range(currentLevel,0,19,'currentLevel');
  final base=recipe(rarity);
  if(base==null)return null;
  final schedule=_schedules[rarity];
  if(schedule==null)return base;
  return EnhancementRecipe(rarity:rarity,materialId:base.materialId,quantity:schedule.quantityFor(currentLevel),gold:base.gold);
 }

 void validateMaterials(bool Function(EnhancementRecipe) valid){
  if(_recipes.values.any((recipe)=>!valid(recipe)))throw const FormatException('Invalid enhancement material master');
 }

 EnhancementRecipe validate({required WorldState world,required AbyssInventory inventory,required EquipmentCatalog catalog,required String id,required int expectedLevel}){
  if(world.battle!=null)throw StateError('Enhancement unavailable in battle');
  final item=inventory.equipment[id];
  if(item==null)throw StateError('Equipment not owned');
  catalog.require(item);
  if(item.enhancement!=expectedLevel)throw StateError('Stale enhancement request');
  if(item.enhancement>=20)throw StateError('Enhancement limit reached');
  if(!inventory.hasCompleteEnhancementHistory(item))throw StateError('Enhancement history missing');
  final cost=recipeFor(item.rarity,item.enhancement);
  if(cost==null)throw StateError('Enhancement recipe unavailable');
  if(world.gold<cost.gold)throw StateError('Insufficient gold');
  if((inventory.stacks[cost.materialId]??0)<cost.quantity)throw StateError('Insufficient materials');
  return cost;
 }

 EquipmentInstance enhance({required WorldState world,required AbyssInventory inventory,required EquipmentCatalog catalog,required String id,required int expectedLevel}){
  final cost=validate(world:world,inventory:inventory,catalog:catalog,id:id,expectedLevel:expectedLevel);
  final result=inventory.enhanceWithMaterial(id,expectedLevel,cost.materialId,cost.quantity);
  world.gold-=cost.gold;
  return result;
 }
}
