import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:level_me/world/abyss_consumable.dart';
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
 const start=1700000000000,h=WorldEngine.hpInterval,e=WorldEngine.energyInterval;
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final catalog=EquipmentCatalog(const [
  EquipmentDefinition(id:'equipment:ring',name:'ring',slot:EquipmentSlot.ring,rarity:EquipmentRarity.r),
  EquipmentDefinition(id:'equipment:reward',name:'reward',slot:EquipmentSlot.necklace,rarity:EquipmentRarity.r),
 ]);
 final recovery=EquipmentSkillMaster(const [EquipmentSkillMasterEntry(id:'equipment_skill:recovery',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.special,effect:EquipmentEffect.naturalRecovery,perLevel:30000)]);
 final rewardMaster=EquipmentSkillMaster(const [EquipmentSkillMasterEntry(id:'equipment_skill:reward',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.special,effect:EquipmentEffect.rewardPercent,perLevel:10000)]);
 final policy=EnhancementPolicy(const [EnhancementRecipe(rarity:EquipmentRarity.r,materialId:'item:iron',quantity:1,gold:1)]);
 final consumables=ConsumableCatalog(const [RecoveryItem(id:'item:test_hp',name:'test',target:RecoveryTarget.hp,percent:10)]);
 AppController controller(LocalStore store,int Function() clock,{EquipmentSkillMaster? master})=>AppController(store,equipmentCatalog:catalog,equipmentSkillMaster:master??recovery,enhancementPolicy:policy,consumableCatalog:consumables,equipmentSkillSeedRandom:Random(7),clockMs:clock);
 void reset(AppController c,int now){
  c.state.world.hp=1;c.state.world.physical=0;c.state.world.magic=0;
  c.state.world.hpAt=now;c.state.world.energyAt=now;
 }
 void assertResources(AppController c,int hp,int energy,int now){
  expect(c.state.world.hp,hp);expect(c.state.world.physical,energy);expect(c.state.world.magic,energy);
  expect(c.state.world.hpAt,now);expect(c.state.world.energyAt,now);
 }
 test('RV-206: 装着・交換・解除で旧倍率精算、端数破棄、保存失敗と再起動',() async {
  final dir=await Directory.systemTemp.createTemp('recovery-boundary-');addTearDown(()=>dir.delete(recursive:true));
  var now=start;final store=_Store(dir);
  final c=controller(store,()=>now);addTearDown(c.dispose);await c.initialize();
  final inv=c.state.inventory;inv.activateEquipmentSkills(7);inv.addStack('item:iron',5);
  final ring=inv.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.r);
  final plain=inv.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.r);
  for(var i=0;i<5;i++){inv.enhanceWithMaterial(ring.id,i,'item:iron',1,skillGrant:i==4?const StoredEquipmentSkill(milestone:5,skillId:'equipment_skill:recovery',level:1):null);}
  final heal=max(1,c.worldStats.hp~/20);
  reset(c,now);await store.save(c.state);
  now+=h+e~/2;
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;await expectLater(c.equipWorldItem(ring.id),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  store.fail=false;await c.equipWorldItem(ring.id);
  assertResources(c,1+heal,3,now);
  final restarted=controller(LocalStore(directory:dir),()=>now);addTearDown(restarted.dispose);await restarted.initialize();
  assertResources(restarted,1+heal,3,now);
  await restarted.startWorldBattle('p01_main');
  final b=restarted.state.world.battle!;
  expect(b.executionVersion,8);expect(b.equipmentEffects!.naturalRecovery,30000);
  assertResources(restarted,1+heal,3,now);
  now+=h;
  await restarted.worldCommand(WorldCommand.retreat,b.id,b.turn);
  assertResources(restarted,1+heal,3,now);
  reset(restarted,now);now+=h+e~/2;
  await restarted.equipWorldItem(plain.id);
  assertResources(restarted,1+heal*4,12,now);
  reset(restarted,now);now+=h+e~/2;
  await restarted.equipWorldItem(ring.id);
  assertResources(restarted,1+heal,3,now);
  reset(restarted,now);now+=h+e~/2;
  await restarted.unequipWorldItem(EquipmentSlot.ring);
  assertResources(restarted,1+heal*4,12,now);
 });
 test('RV-206: 装着中付与強化の境界と薬・努力報酬への非適用',() async {
  final dir=await Directory.systemTemp.createTemp('recovery-enhance-');addTearDown(()=>dir.delete(recursive:true));
  var now=start;final store=_Store(dir);
  final c=controller(store,()=>now);addTearDown(c.dispose);await c.initialize();
  final ring=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.r);
  c.state.inventory.addStack('item:iron',10);c.state.inventory.addStack('item:test_hp',1);c.state.world.gold=10;
  await store.save(c.state);await c.equipWorldItem(ring.id);
  for(var i=0;i<4;i++){await c.enhanceWorldItem(ring.id,i);}
  final heal=max(1,c.worldStats.hp~/20);
  reset(c,now);await store.save(c.state);now+=h+e~/2;
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${LocalStore.fileName}');final bytes=await primary.readAsString();
  store.fail=true;await expectLater(c.enhanceWorldItem(ring.id,4),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  store.fail=false;await c.enhanceWorldItem(ring.id,4);
  assertResources(c,1+heal,3,now);
  final hp=c.state.world.hp;
  final expected=WorldEngine.recoveryAmount(hp,c.worldStats.hp,10);
  expect(await c.useWorldRecoveryItem('item:test_hp',c.state.world.itemUseSequence,expectedGeneration:c.restoreGeneration),expected);
  expect(c.state.world.hp,hp+expected);
  final copy=WorldState.fromJson(c.state.world.toJson());
  WorldEngine().rewardEffort(copy,c.worldStats,now,physical:2,magic:3,levelUp:false,naturalRecovery:30000);
  expect(copy.physical,5);expect(copy.magic,6);expect(copy.hp,hp+expected);
  await c.startWorldBattle('p01_main');
  expect(c.state.world.hp,hp+expected);expect(c.state.world.physical,3);expect(c.state.world.magic,3);
 });
 test('RV-206: 版8勝利報酬の実ファイル再起動・保存失敗・再試行',() async {
  final dir=await Directory.systemTemp.createTemp('reward-v8-');addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);final c=controller(store,()=>start,master:rewardMaster);addTearDown(c.dispose);await c.initialize();
  final inv=c.state.inventory;inv.activateEquipmentSkills(7);inv.addStack('item:iron',5);
  final ring=inv.addEquipment('equipment:reward',EquipmentSlot.necklace,EquipmentRarity.r);
  for(var i=0;i<5;i++){inv.enhanceWithMaterial(ring.id,i,'item:iron',1,skillGrant:i==4?const StoredEquipmentSkill(milestone:5,skillId:'equipment_skill:reward',level:1):null);}
  await c.equipWorldItem(ring.id);await c.startWorldBattle('p01_main');
  final b=c.state.world.battle!;expect(b.executionVersion,8);expect(b.equipmentEffects!.reward,10000);
  b.enemyHp=1;await store.save(c.state);
  final restoredStore=_Store(dir);final restored=controller(restoredStore,()=>start,master:rewardMaster);addTearDown(restored.dispose);await restored.initialize();
  final encounter=WorldCatalog.byId('p01_main');
  final gold=restored.state.world.gold,life=restored.state.world.lifespan,tickets=restored.state.world.summonTickets;
  final before=jsonEncode(restored.state.toJson());final primary=File('${dir.path}/${LocalStore.fileName}');final bytes=await primary.readAsString();
  restoredStore.fail=true;await expectLater(restored.worldCommand(WorldCommand.claw,b.id,b.turn),throwsStateError);
  expect(jsonEncode(restored.state.toJson()),before);expect(await primary.readAsString(),bytes);
  restoredStore.fail=false;await restored.worldCommand(WorldCommand.claw,b.id,b.turn);
  expect(restored.state.world.battle,isNull);expect(restored.state.world.gold,gold+encounter.gold*2);
  expect(restored.state.world.lifespan,life+BigInt.from(encounter.lifeDays));expect(restored.state.world.summonTickets,tickets+3);
  await expectLater(restored.worldCommand(WorldCommand.claw,b.id,b.turn),throwsStateError);
  final finalState=await LocalStore(directory:dir).load();
  expect(finalState.world.toJson(),restored.state.world.toJson());
 });
}
