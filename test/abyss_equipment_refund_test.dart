import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_dismantle.dart';

void main(){
 final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:ring',name:'test',slot:EquipmentSlot.ring,rarity:EquipmentRarity.r)]);
 final policy=DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.r,materialId:'item:iron',quantity:2,magicCrystals:3)]);
 test('実消費を素材別に集計・復元・通常報酬併給・二重分解拒否',(){
  final s=AppStateData.initial();
  final item=s.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.r);
  s.inventory.addStack('item:iron',18);
  s.inventory.addStack('item:wood',19);
  s.inventory.enhanceWithMaterial(item.id,0,'item:iron',9);
  s.inventory.enhanceWithMaterial(item.id,1,'item:iron',9);
  s.inventory.enhanceWithMaterial(item.id,2,'item:wood',19);
  s.inventory.setFavorite(item.id,true);
  s.inventory.setFavorite(item.id,false);
  final restored=AppStateData.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String,dynamic>);
  final inv=restored.inventory;
  expect(inv.enhancementRefund(inv.equipment[item.id]!),{'item:iron':1,'item:wood':1});
  final reward=policy.dismantle(world:restored.world,inventory:inv,catalog:catalog,id:item.id,expectedLevel:3);
  expect(reward.refundedMaterials,{'item:iron':1,'item:wood':1});
  expect(inv.stacks,{'item:iron':3,'item:wood':1});
  expect(restored.world.magicCrystals,s.world.magicCrystals+3);
  expect(inv.equipment,isEmpty);
  expect(inv.toJson().containsKey('enhancementCosts'),false);
  expect(()=>policy.dismantle(world:restored.world,inventory:inv,catalog:catalog,id:item.id,expectedLevel:3),throwsStateError);
 });
 test('履歴欠落・合算上限・保護時は資産不変',(){
  final s=AppStateData.initial();
  final item=s.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.r);
  s.inventory.addStack('item:iron',10);
  s.inventory.enhanceWithMaterial(item.id,0,'item:iron',10);
  s.inventory.addStack('item:iron',0x7ffffffffffffffd);
  void reject(){
   final before=jsonEncode(s.toJson());
   expect(()=>policy.dismantle(world:s.world,inventory:s.inventory,catalog:catalog,id:item.id,expectedLevel:1),throwsStateError);
   expect(jsonEncode(s.toJson()),before);
  }
  reject();
  s.inventory.removeStack('item:iron',0x7ffffffffffffffd);
  s.inventory.equip(item.id);reject();s.inventory.unequip(item.slot);
  s.inventory.setFavorite(item.id,true);reject();s.inventory.setFavorite(item.id,false);
  final legacy=AbyssInventory.fromJson(s.inventory.toJson()..remove('enhancementCosts'));
  expect(()=>legacy.requireDismantleable(item.id,1),throwsStateError);
 });
 test('不正履歴を拒否',(){
  final inv=AbyssInventory();
  final item=inv.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.r);
  inv.addStack('item:iron',10);
  inv.enhanceWithMaterial(item.id,0,'item:iron',10);
  final raw=inv.toJson();
  final history=raw['enhancementCosts'] as Map;
  history['version']=2;
  expect(()=>AbyssInventory.fromJson(raw),throwsFormatException);
 });
}
