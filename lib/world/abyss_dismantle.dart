import 'abyss_inventory.dart';
import 'abyss_equipment.dart';
import 'world_engine.dart';

class DismantleRecipe {
 const DismantleRecipe({required this.rarity,required this.materialId,required this.quantity});
 final EquipmentRarity rarity;
 final String materialId;
 final int quantity;
}

class DismantlePolicy {
 DismantlePolicy(Iterable<DismantleRecipe> recipes){
  for(final recipe in recipes){
   if(!recipe.materialId.startsWith('item:')||recipe.materialId.length<=5||recipe.quantity<=0||recipe.quantity>1000000||_recipes.containsKey(recipe.rarity))throw const FormatException('Invalid dismantle recipe');
   _recipes[recipe.rarity]=recipe;
  }
 }
 final _recipes=<EquipmentRarity,DismantleRecipe>{};
 // 報酬の承認までは本番分解を無効化する。
 static final production=DismantlePolicy(const []);
 void validateMaterials(bool Function(DismantleRecipe) valid){
  if(_recipes.values.any((recipe)=>!valid(recipe)))throw const FormatException('Invalid dismantle material master');
 }
 DismantleRecipe? recipe(EquipmentRarity rarity)=>_recipes[rarity];
 DismantleRecipe validate({required WorldState world,required AbyssInventory inventory,required EquipmentCatalog catalog,required String id,required int expectedLevel}){
  if(world.battle!=null)throw StateError('Dismantle unavailable in battle');
  final item=inventory.requireDismantleable(id,expectedLevel);
  catalog.require(item);
  final reward=recipe(item.rarity);
  if(reward==null)throw StateError('Dismantle recipe unavailable');
  final current=inventory.stacks[reward.materialId]??0;
  final next=current+reward.quantity;
  if(next<=current)throw StateError('Stack overflow');
  return reward;
 }
 DismantleRecipe dismantle({required WorldState world,required AbyssInventory inventory,required EquipmentCatalog catalog,required String id,required int expectedLevel}){
  final reward=validate(world:world,inventory:inventory,catalog:catalog,id:id,expectedLevel:expectedLevel);
  inventory.addStack(reward.materialId,reward.quantity);
  inventory.removeEquipment(id,expectedLevel);
  return reward;
 }
}
