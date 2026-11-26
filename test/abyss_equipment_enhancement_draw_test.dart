import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_enhancement.dart';
import 'package:level_me/world/abyss_equipment_skill_master.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_equipment_enhancement_draw.dart';
import 'package:level_me/world/world_catalog.dart';

class _FailStore extends LocalStore {
 _FailStore(Directory dir):super(directory:dir);
 bool fail=false;
 @override Future<void> save(AppStateData state) async {
  if(fail)throw StateError('Simulated failure');
  await super.save(state);
 }
}
void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final master=EquipmentSkillMaster(const [
  EquipmentSkillMasterEntry(id:'equipment_skill:a',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.physicalPercent,perLevel:100),
  EquipmentSkillMasterEntry(id:'equipment_skill:b',rarity:EquipmentSkillRarity.rare,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.magicPercent,perLevel:100),
 ]);
 final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:sword',name:'test',slot:EquipmentSlot.hands,rarity:EquipmentRarity.gr)]);
 final policy=EnhancementPolicy(const [EnhancementRecipe(rarity:EquipmentRarity.gr,materialId:'item:iron',quantity:1,gold:2)]);
 test('版2は全履歴を必須とし、新規個体は+0から記録',(){
  final inv=AbyssInventory();inv.activateEquipmentSkills(12);
  final item=inv.addEquipment('equipment:sword',EquipmentSlot.hands,EquipmentRarity.gr);
  expect(inv.equipmentSkillHistories[item.id]!.startEnhancement,0);
  expect(inv.toJson()['version'],2);
  final raw=inv.toJson();(raw['equipmentSkills'] as Map)['items']={};
  expect(()=>AbyssInventory.fromJson(raw),throwsFormatException);
  expect(()=>AbyssInventory.fromJson(inv.toJson()..remove('equipmentSkills')),throwsFormatException);
 });
 test('保存失敗・再起動・再試行で確定値を維持し一度だけ消費',() async {
  final dir=await Directory.systemTemp.createTemp('equipment-draw-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_FailStore(dir);
  AppController controller(LocalStore s)=>AppController(s,equipmentCatalog:catalog,enhancementPolicy:policy,equipmentSkillMaster:master,equipmentSkillSeedRandom:Random(7));
  final c=controller(store);addTearDown(c.dispose);await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:sword',EquipmentSlot.hands,EquipmentRarity.gr);
  c.state.inventory.addStack('item:iron',10);c.state.world.gold=20;
  await store.save(c.state);
  await c.enhanceWorldItem(item.id,0);await c.enhanceWorldItem(item.id,1);
  final expected=EquipmentEnhancementDraw.prepare(c.state.inventory,c.state.inventory.equipment[item.id]!,master)!;
  final before=jsonEncode(c.state.toJson());store.fail=true;
  await expectLater(c.enhanceWorldItem(item.id,2),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);
  final restarted=controller(LocalStore(directory:dir));addTearDown(restarted.dispose);await restarted.initialize();
  final repeated=EquipmentEnhancementDraw.prepare(restarted.state.inventory,restarted.state.inventory.equipment[item.id]!,master)!;
  expect(repeated.toJson(),expected.toJson());
  await restarted.enhanceWorldItem(item.id,2);
  expect(restarted.state.inventory.equipmentSkillHistories[item.id]!.grants.single.toJson(),expected.toJson());
  expect(restarted.state.world.gold,14);expect(restarted.state.inventory.stacks['item:iron'],7);
  await expectLater(restarted.enhanceWorldItem(item.id,2),throwsStateError);
  expect(restarted.state.world.gold,14);
 });
}
