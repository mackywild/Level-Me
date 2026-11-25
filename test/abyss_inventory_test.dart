import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/world/abyss_inventory.dart';

void main(){
 test('stack quantities and discovery survive depletion and reload',(){
  final inventory=AbyssInventory();
  inventory.addStack('test_potion',2);
  inventory.addStack('test_potion',3);
  expect(inventory.stacks['test_potion'],5);
  expect(()=>inventory.removeStack('test_potion',6),throwsStateError);
  expect(inventory.stacks['test_potion'],5);
  expect(()=>inventory.addStack('test_potion',0),throwsArgumentError);
  expect(()=>inventory.removeStack('test_potion',-1),throwsArgumentError);
  inventory.removeStack('test_potion',5);
  final restored=AbyssInventory.fromJson(jsonDecode(jsonEncode(inventory.toJson())) as Map<String,dynamic>);
  expect(restored.stacks,isEmpty);
  expect(restored.discovered,contains('test_potion'));
 });
 test('duplicate equipment master yields distinct persistent instance IDs',(){
  final inventory=AbyssInventory();
  final first=inventory.addEquipment('test_ring',EquipmentSlot.ring,EquipmentRarity.r);
  final second=inventory.addEquipment('test_ring',EquipmentSlot.ring,EquipmentRarity.r);
  expect(first.id,isNot(second.id));
  final restored=AbyssInventory.fromJson(jsonDecode(jsonEncode(inventory.toJson())) as Map<String,dynamic>);
  expect(restored.equipment[first.id]!.slot,EquipmentSlot.ring);
  expect(restored.equipment[second.id]!.rarity,EquipmentRarity.r);
  expect(restored.discovered.length,1);
  final third=restored.addEquipment('test_ring',EquipmentSlot.ring,EquipmentRarity.r);
  expect(third.id,isNot(first.id));
  expect(third.id,isNot(second.id));
  expect(restored.equipment.length,3);
  expect(()=>restored.equipment.clear(),throwsUnsupportedError);
 });
 test('legacy app state preserves existing resources and initializes empty inventory',(){
  final old=AppStateData.initial()..totalExp=500..gachaTickets=4;
  old.world.gold=123;
  old.world.summonTickets=3;
  old.world.supplyTickets=1;
  final restored=AppStateData.fromJson(old.toJson()..remove('inventory'));
  expect(restored.inventory.stacks,isEmpty);
  expect(restored.inventory.equipment,isEmpty);
  expect(restored.totalExp,500);
  expect(restored.gachaTickets,4);
  expect(restored.world.gold,123);
  expect(restored.world.summonTickets,3);
  expect(restored.world.supplyTickets,1);
  restored.inventory.addStack('test_material',2);
  final roundtrip=AppStateData.fromJson(jsonDecode(jsonEncode(restored.toJson())) as Map<String,dynamic>);
  expect(roundtrip.inventory.stacks['test_material'],2);
 });
 test('invalid inventory data is rejected rather than silently reset',(){
  final inventory=AbyssInventory();
  inventory.addStack('test_material',1);
  final badStack=inventory.toJson();
  (badStack['stacks'] as Map)['test_material']=0;
  expect(()=>AbyssInventory.fromJson(badStack),throwsFormatException);
  final missing=inventory.toJson()..['discovered']=[];
  expect(()=>AbyssInventory.fromJson(missing),throwsFormatException);
  inventory.addEquipment('test_ring',EquipmentSlot.ring,EquipmentRarity.r);
  final duplicate=inventory.toJson();
  final entries=duplicate['equipment'] as List;
  entries.add(entries.first);
  expect(()=>AbyssInventory.fromJson(duplicate),throwsFormatException);
  expect(()=>AbyssInventory.fromJson(inventory.toJson()..['version']=2),throwsFormatException);
 });
}
