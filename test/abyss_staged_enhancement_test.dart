import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/world/abyss_enhancement.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_inventory.dart';

void main(){
 const rarity=EquipmentRarity.r;
 const recipe=EnhancementRecipe(rarity:rarity,materialId:'item:iron',quantity:2,gold:10);
 final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:ring',name:'test',slot:EquipmentSlot.ring,rarity:rarity)]);
 List<int> amounts()=>List.generate(20,(i)=>i+2);
 test('全20段階で必要数増加・旧レシピ互換・不変性',(){
  final source=amounts();
  final schedule=EnhancementMaterialSchedule(source);
  final map={rarity:schedule};
  final policy=EnhancementPolicy([recipe],schedules:map);
  source.clear();map.clear();
  for(var i=0;i<20;i++){
   final cost=policy.recipeFor(rarity,i)!;
   expect(cost.quantity,i+2);
   expect(cost.gold,10);
   expect(cost.materialId,'item:iron');
   expect(EnhancementPolicy([recipe]).recipeFor(rarity,i),same(recipe));
  }
  expect(()=>schedule.quantities.clear(),throwsUnsupportedError);
  expect(()=>policy.recipeFor(rarity,20),throwsRangeError);
  expect(()=>policy.recipeFor(rarity,-1),throwsRangeError);
  expect(policy.recipeFor(EquipmentRarity.gr,0),isNull);
 });
 test('不正な段階表とレシピ不一致を拒否',(){
  for(final invalid in <List<int>>[[],List.filled(20,2),List.generate(20,(i)=>i),List.generate(20,(i)=>1000000+i),List.generate(19,(i)=>i+2)]){
   expect(()=>EnhancementMaterialSchedule(invalid),throwsFormatException);
  }
  final schedule=EnhancementMaterialSchedule(amounts());
  expect(()=>EnhancementPolicy([],schedules:{rarity:schedule}),throwsFormatException);
  expect(()=>EnhancementPolicy([recipe],schedules:{rarity:EnhancementMaterialSchedule(List.generate(20,(i)=>i+3))}),throwsFormatException);
 });
 test('段階別の実消費・不足時の資産維持',(){
  final state=AppStateData.initial();
  final item=state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,rarity);
  state.inventory.addStack('item:iron',4);
  state.world.gold=30;
  final policy=EnhancementPolicy([recipe],schedules:{rarity:EnhancementMaterialSchedule(amounts())});
  void enhance(int level)=>policy.enhance(world:state.world,inventory:state.inventory,catalog:catalog,id:item.id,expectedLevel:level);
  enhance(0);
  expect(state.inventory.stacks['item:iron'],2);
  expect(state.world.gold,20);
  expect(()=>enhance(1),throwsStateError);
  expect(state.inventory.stacks['item:iron'],2);
  expect(state.world.gold,20);
  expect(state.inventory.equipment[item.id]!.enhancement,1);
  state.inventory.addStack('item:iron',1);
  enhance(1);
  expect(state.inventory.stacks.containsKey('item:iron'),false);
  expect(state.world.gold,10);
  expect(state.inventory.equipment[item.id]!.enhancement,2);
 });
 test('基礎性能5%加算、全段階と整数境界',(){
  const scaling=EnhancementScaling.approved();
  for(var i=0;i<=20;i++){
   expect(scaling.apply(100,i),100+5*i);
   expect(scaling.apply(7,i),7*(100+5*i)~/100);
   expect(scaling.apply(0,i),0);
  }
  expect(scaling.apply(100,20),200);
  expect(()=>scaling.apply(-1,0),throwsStateError);
  expect(()=>scaling.apply(100,21),throwsRangeError);
  expect(const EnhancementScaling.proposed().apply(100,20),200);
 });
}
