import 'abyss_inventory.dart';
import 'abyss_equipment.dart';
import 'world_engine.dart';

class EnhancementRecipe {
 const EnhancementRecipe({required this.rarity,required this.materialId,required this.quantity,required this.gold});
 final EquipmentRarity rarity;
 final String materialId;
 final int quantity,gold;
}

class EnhancementPolicy {
 EnhancementPolicy(Iterable<EnhancementRecipe> recipes){
  for(final recipe in recipes){
   if(!recipe.materialId.startsWith('item:')||recipe.materialId.length<=5||recipe.quantity<=0||recipe.gold<=0||_recipes.containsKey(recipe.rarity)){
    throw const FormatException('Invalid enhancement recipe');
   }
   _recipes[recipe.rarity]=recipe;
  }
 }
 final _recipes=<EquipmentRarity,EnhancementRecipe>{};
 // 費用・素材の正式承認までは本番の強化を無効にする。
 static final production=EnhancementPolicy(const []);
 EnhancementRecipe? recipe(EquipmentRarity rarity)=>_recipes[rarity];

 EquipmentInstance enhance({required WorldState world,required AbyssInventory inventory,required EquipmentCatalog catalog,required String id,required int expectedLevel}){
  if(world.battle!=null)throw StateError('Enhancement unavailable in battle');
  final item=inventory.equipment[id];
  if(item==null)throw StateError('Equipment not owned');
  catalog.require(item);
  if(item.enhancement!=expectedLevel)throw StateError('Stale enhancement request');
  if(item.enhancement>=20)throw StateError('Enhancement limit reached');
  final cost=recipe(item.rarity);
  if(cost==null)throw StateError('Enhancement recipe unavailable');
  if(world.gold<cost.gold)throw StateError('Insufficient gold');
  if((inventory.stacks[cost.materialId]??0)<cost.quantity)throw StateError('Insufficient materials');
  inventory.removeStack(cost.materialId,cost.quantity);
  world.gold-=cost.gold;
  return inventory.enhance(id,expectedLevel);
 }
}
