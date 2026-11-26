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
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Store extends LocalStore {
 _Store(Directory dir):super(directory:dir);
 bool fail=false;
 @override Future<void> save(AppStateData state) async {
  if(fail)throw StateError('Injected save failure');
  await super.save(state);
 }
}
void main(){
 const start=1700000000000,tick=WorldEngine.hpInterval;
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:armor',name:'test',slot:EquipmentSlot.body,rarity:EquipmentRarity.r)]);
 final master=EquipmentSkillMaster(const [EquipmentSkillMasterEntry(id:'equipment_skill:hp',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.defense,effect:EquipmentEffect.hpPercent,perLevel:30000)]);
 final policy=EnhancementPolicy(const [EnhancementRecipe(rarity:EquipmentRarity.r,materialId:'item:iron',quantity:1,gold:1)]);
 AppController controller(LocalStore store,int Function() clock)=>AppController(store,equipmentCatalog:catalog,equipmentSkillMaster:master,enhancementPolicy:policy,equipmentSkillSeedRandom:Random(7),clockMs:clock);
 test('RV-201: 満タン/不足・交換・解除・保存失敗・再起動で旧HP上限の経過分を精算',() async {
  final dir=await Directory.systemTemp.createTemp('hp-boundary-');
  addTearDown(()=>dir.delete(recursive:true));
  var now=start;
  final store=_Store(dir);
  final c=controller(store,()=>now);addTearDown(c.dispose);await c.initialize();
  final inv=c.state.inventory;
  inv.activateEquipmentSkills(7);inv.addStack('item:iron',5);
  final armor=inv.addEquipment('equipment:armor',EquipmentSlot.body,EquipmentRarity.r);
  final plain=inv.addEquipment('equipment:armor',EquipmentSlot.body,EquipmentRarity.r);
  for(var i=0;i<5;i++){
   inv.enhanceWithMaterial(armor.id,i,'item:iron',1,skillGrant:i==4?const StoredEquipmentSkill(milestone:5,skillId:'equipment_skill:hp',level:1):null);
  }
  final base=c.worldStats.hp;
  c.state.world.hp=base;c.state.world.hpAt=now;
  await store.save(c.state);
  now+=4*tick+tick~/2;
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.equipWorldItem(armor.id),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  store.fail=false;
  await c.equipWorldItem(armor.id);
  expect(c.worldStats.hp,base*4);expect(c.state.world.hp,base);expect(c.state.world.hpAt,now);
  final restarted=controller(LocalStore(directory:dir),()=>now);addTearDown(restarted.dispose);await restarted.initialize();
  expect(restarted.state.world.hp,base);
  await restarted.startWorldBattle('p01_main');
  expect(restarted.state.world.battle!.stats.hp,base*4);expect(restarted.state.world.hp,base);
  final battle=restarted.state.world.battle!;
  await restarted.worldCommand(WorldCommand.retreat,battle.id,battle.turn);
  restarted.state.world.hp=1;
  now+=tick;
  await restarted.equipWorldItem(plain.id);
  expect(restarted.worldStats.hp,base);
  expect(restarted.state.world.hp,1+base*4~/20);
  restarted.state.world.hp=1;
  now+=tick;
  await restarted.equipWorldItem(armor.id);
  expect(restarted.state.world.hp,1+base~/20);
  restarted.state.world.hp=base*4;
  await restarted.unequipWorldItem(EquipmentSlot.body);
  expect(restarted.state.world.hp,base);
  expect(restarted.state.world.hpAt,now);
 });
 test('RV-201: 装着中のHP付与強化は旧上限で精算し直後の戦闘開始で遡及しない',() async {
  final dir=await Directory.systemTemp.createTemp('hp-enhance-boundary-');
  addTearDown(()=>dir.delete(recursive:true));
  var now=start;
  final store=_Store(dir);
  final c=controller(store,()=>now);addTearDown(c.dispose);await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:armor',EquipmentSlot.body,EquipmentRarity.r);
  c.state.inventory.addStack('item:iron',10);c.state.world.gold=10;
  await store.save(c.state);
  await c.equipWorldItem(item.id);
  for(var i=0;i<4;i++){await c.enhanceWorldItem(item.id,i);}
  final base=c.worldStats.hp;
  c.state.world.hp=base;c.state.world.hpAt=now;
  await store.save(c.state);
  now+=4*tick;
  final before=jsonEncode(c.state.toJson());
  store.fail=true;
  await expectLater(c.enhanceWorldItem(item.id,4),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);
  store.fail=false;await c.enhanceWorldItem(item.id,4);
  expect(c.worldStats.hp,base*4);expect(c.state.world.hp,base);expect(c.state.world.hpAt,now);
  await c.startWorldBattle('p01_main');
  expect(c.state.world.battle!.stats.hp,base*4);expect(c.state.world.hp,base);
 });
}
