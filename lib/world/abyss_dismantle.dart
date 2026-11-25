import 'abyss_inventory.dart';
import 'abyss_equipment.dart';
import 'world_engine.dart';

class DismantleRecipe {
 const DismantleRecipe({required this.rarity,required this.materialId,required this.quantity,this.magicCrystals=0});
 final EquipmentRarity rarity;
 final String materialId;
 final int quantity,magicCrystals;
}

class DismantlePolicy {
 DismantlePolicy(Iterable<DismantleRecipe> recipes){
  for(final recipe in recipes){
   if((recipe.quantity>0?(!recipe.materialId.startsWith('item:')||recipe.materialId.length<=5):recipe.materialId.isNotEmpty)||recipe.quantity<0||recipe.quantity>1000000||recipe.magicCrystals<0||recipe.magicCrystals>1000000||(recipe.quantity==0&&recipe.magicCrystals==0)||_recipes.containsKey(recipe.rarity))throw const FormatException('Invalid dismantle recipe');
   _recipes[recipe.rarity]=recipe;
  }
 }
 final _recipes=<EquipmentRarity,DismantleRecipe>{};
 // 報酬の承認までは本番分解を無効化する。
 static final production=DismantlePolicy(const []);
 void validateMaterials(bool Function(DismantleRecipe) valid){
  if(_recipes.values.any((recipe)=>recipe.quantity>0&&!valid(recipe)))throw const FormatException('Invalid dismantle material master');
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
  if(reward.quantity>0&&next<=current)throw StateError('Stack overflow');
  if(reward.magicCrystals>0&&world.magicCrystals+reward.magicCrystals<=world.magicCrystals)throw StateError('Crystal overflow');
  return reward;
 }
 DismantleRecipe dismantle({required WorldState world,required AbyssInventory inventory,required EquipmentCatalog catalog,required String id,required int expectedLevel}){
  final reward=validate(world:world,inventory:inventory,catalog:catalog,id:id,expectedLevel:expectedLevel);
  if(reward.quantity>0)inventory.addStack(reward.materialId,reward.quantity);
  world.magicCrystals+=reward.magicCrystals;
  inventory.removeEquipment(id,expectedLevel);
  return reward;
 }
}
