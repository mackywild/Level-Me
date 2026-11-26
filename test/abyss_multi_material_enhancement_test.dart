import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_enhancement.dart';
import 'package:level_me/world/abyss_dismantle.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/world_engine.dart';

void main(){
 const iron='item:iron',special='item:ex_test';
 const master='equipment:test';
 AbyssInventory inventory(){
  final inv=AbyssInventory();
  inv.addStack(iron,100);inv.addStack(special,100);
  inv.addEquipment(master,EquipmentSlot.hands,EquipmentRarity.r);
  return inv;
 }
 test('2素材を段階単位で消費、単素材履歴と混在、復元後10%素材別還元',(){
  final inv=inventory();
  inv.enhanceWithMaterial('eq_1',0,iron,7);
  expect((inv.toJson()['enhancementCosts'] as Map)['version'],1);
  inv.enhanceWithMaterials('eq_1',1,{iron:8,special:19});
  inv.enhanceWithMaterials('eq_1',2,{iron:9,special:12});
  expect(inv.stacks,{iron:76,special:69});
  final raw=jsonDecode(jsonEncode(inv.toJson())) as Map<String,dynamic>;
  expect(raw['enhancementCosts']['version'],2);
  final restored=AbyssInventory.fromJson(raw);
  expect(restored.toJson(),raw);
  expect(restored.enhancementRefund(restored.equipment['eq_1']!),{iron:2,special:3});
  final catalog=EquipmentCatalog(const [EquipmentDefinition(id:master,name:'test',slot:EquipmentSlot.hands,rarity:EquipmentRarity.r)]);
  final policy=DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.r,materialId:iron,quantity:1,magicCrystals:2)]);
  final w=WorldState();
  restored.equip('eq_1');
  expect(()=>policy.dismantle(world:w,inventory:restored,catalog:catalog,id:'eq_1',expectedLevel:3),throwsStateError);
  restored.unequip(EquipmentSlot.hands);
  restored.setFavorite('eq_1',true);
  expect(()=>policy.dismantle(world:w,inventory:restored,catalog:catalog,id:'eq_1',expectedLevel:3),throwsStateError);
  restored.setFavorite('eq_1',false);
  policy.dismantle(world:w,inventory:restored,catalog:catalog,id:'eq_1',expectedLevel:3);
  expect(restored.stacks,{iron:79,special:72});expect(w.magicCrystals,2);
  expect(restored.equipment,isEmpty);expect(restored.toJson().containsKey('enhancementCosts'),false);
 });
 test('素材不足・不正費用・不正付与では一切変更しない',(){
  final inv=inventory();inv.activateEquipmentSkills(7);
  final before=jsonEncode(inv.toJson());
  expect(()=>inv.enhanceWithMaterials('eq_1',0,{iron:1,special:101}),throwsStateError);
  for(final costs in <Map<String,int>>[{}, {iron:0,special:1},{iron:1,special:1000001},{'bad':1},{iron:1,special:1,'item:third':1}]){
   expect(()=>inv.enhanceWithMaterials('eq_1',0,costs),throwsArgumentError);
  }
  expect(()=>inv.enhanceWithMaterials('eq_1',0,{iron:1,special:1},skillGrant:const StoredEquipmentSkill(milestone:1,skillId:'equipment_skill:test',level:1)),throwsFormatException);
  expect(jsonEncode(inv.toJson()),before);
 });
 test('版2不正履歴・旧版への混入・素材未発見・段階欠落を拒否',(){
  final inv=inventory();inv.enhanceWithMaterials('eq_1',0,{iron:1,special:2});
  Map<String,dynamic> raw()=>jsonDecode(jsonEncode(inv.toJson())) as Map<String,dynamic>;
  for(final bad in <Object>[{}, {iron:0,special:2},{iron:1,special:2.0},{iron:1,'item:unknown':2},{iron:1,special:2,'item:third':1}]){
   final j=raw();j['enhancementCosts']['items']['eq_1'][0]['materials']=bad;
   expect(()=>AbyssInventory.fromJson(j),throwsFormatException);
  }
  final wrong=raw();wrong['enhancementCosts']['version']=1;
  expect(()=>AbyssInventory.fromJson(wrong),throwsFormatException);
  final missing=raw();missing['enhancementCosts']['items']['eq_1']=[];
  expect(()=>AbyssInventory.fromJson(missing),throwsFormatException);
 });
 test('EX個別2素材スケジュールは20段階、別ID、不変',(){
  final schedule=EnhancementMaterialSchedule(List.generate(20,(i)=>i+1));
  final other=EnhancementMaterialSchedule(List.generate(20,(i)=>(i+1)*2));
  final plan=ExEnhancementMaterialPlan(normalMaterialId:iron,exMaterialId:special,normalSchedule:schedule,exSchedule:other);
  for(var i=0;i<20;i++){expect(plan.materialsFor(i),{iron:i+1,special:(i+1)*2});}
  expect(()=>plan.materialsFor(20),throwsRangeError);
  expect(()=>plan.materialsFor(0).clear(),throwsUnsupportedError);
  expect(()=>ExEnhancementMaterialPlan(normalMaterialId:iron,exMaterialId:iron,normalSchedule:schedule,exSchedule:other),throwsFormatException);
 });
}
