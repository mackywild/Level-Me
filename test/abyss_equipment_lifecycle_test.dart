import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_enhancement.dart';
import 'package:level_me/world/abyss_dismantle.dart';
import 'package:level_me/world/abyss_shop.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/abyss_equipment_skill_master.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/world_catalog.dart';

class _FaultStore extends LocalStore {
 _FaultStore(Directory dir):super(directory:dir);
 bool fail=false;
 @override Future<void> save(AppStateData state) async {
  if(fail)throw StateError('Injected save failure');
  await super.save(state);
 }
}
void main(){
 const now=1700000000000;
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final equipment=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:sword',name:'統合試験剣',slot:EquipmentSlot.hands,rarity:EquipmentRarity.gr,physical:20)]);
 final skills=EquipmentSkillMaster(const [EquipmentSkillMasterEntry(id:'equipment_skill:attack',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.physicalPercent,perLevel:1000)]);
 final enhancement=EnhancementPolicy(const [EnhancementRecipe(rarity:EquipmentRarity.gr,materialId:'item:iron',quantity:10,gold:2)],schedules:{EquipmentRarity.gr:EnhancementMaterialSchedule(List.generate(20,(i)=>10+i))});
 final dismantle=DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.gr,materialId:'item:iron',quantity:2,magicCrystals:3)]);
 final shop=ShopCatalog(const [ShopOffer.equipment(id:'shop:sword',equipmentId:'equipment:sword',price:5)]);
 AppController controller(LocalStore store)=>AppController(store,equipmentCatalog:equipment,equipmentSkillMaster:skills,equipmentSkillSeedRandom:Random(7),enhancementPolicy:enhancement,dismantlePolicy:dismantle,shopCatalog:shop,enhancementScaling:const EnhancementScaling.approved(),clockMs:()=>now);
 test('取得→強化→抽選→装着→戦闘→再起動→分解の実ファイル統合',() async {
  final dir=await Directory.systemTemp.createTemp('equipment-lifecycle-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_FaultStore(dir);
  final c=controller(store);addTearDown(c.dispose);await c.initialize();
  c.state.world.gold=100;c.state.world.magicCrystals=10;
  c.state.inventory.addStack('item:iron',100);
  await store.save(c.state);
  await c.purchaseWorldOffer('shop:sword',0,expectedGeneration:c.restoreGeneration);
  final id=c.state.inventory.equipment.values.single.id;
  expect(c.state.inventory.equipment[id]!.enhancement,0);
  expect(c.state.world.magicCrystals,5);
  expect(c.state.inventory.equipmentSkillHistories,isEmpty);
  await expectLater(c.purchaseWorldOffer('shop:sword',0),throwsStateError);
  for(var i=0;i<6;i++){await c.enhanceWorldItem(id,i,expectedGeneration:c.restoreGeneration);}
  final inv=c.state.inventory;
  final grants=inv.equipmentSkillHistories[id]!.grants;
  expect(grants.map((g)=>g.milestone),[3,6]);
  expect(grants.every((g)=>g.skillId=='equipment_skill:attack'&&g.level>=1&&g.level<=10),true);
  expect(inv.stacks['item:iron'],25);expect(c.state.world.gold,88);
  final savedGrants=grants.map((g)=>g.toJson()).toList();
  await c.equipWorldItem(id);
  final base=c.worldStats.physical;
  final bonus=min(30000,grants.fold<int>(0,(sum,g)=>sum+1000*g.level));
  await c.startWorldBattle('p01_main');
  final b=c.state.world.battle!;
  expect(b.executionVersion,4);
  expect(b.equipmentEffects!.physical,bonus);
  expect(b.stats.physical,base*(10000+bonus)~/10000);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final snapshot=await primary.readAsString();
  await expectLater(c.dismantleWorldItem(id,6),throwsStateError);
  expect(await primary.readAsString(),snapshot);
  final restarted=controller(LocalStore(directory:dir));addTearDown(restarted.dispose);await restarted.initialize();
  expect(restarted.state.inventory.equipmentSkillHistories[id]!.grants.map((g)=>g.toJson()).toList(),savedGrants);
  expect(restarted.state.world.battle!.toJson(),b.toJson());
  await restarted.worldCommand(WorldCommand.guard,b.id,b.turn,expectedGeneration:restarted.restoreGeneration);
  expect(restarted.state.world.battle!.turn,2);
  await restarted.worldCommand(WorldCommand.retreat,b.id,2,expectedGeneration:restarted.restoreGeneration);
  expect(restarted.state.world.battle,isNull);
  await restarted.unequipWorldItem(EquipmentSlot.hands);
  await restarted.setWorldEquipmentFavorite(id,true);
  await expectLater(restarted.dismantleWorldItem(id,6),throwsStateError);
  await restarted.setWorldEquipmentFavorite(id,false);
  final reward=await restarted.dismantleWorldItem(id,6,expectedGeneration:restarted.restoreGeneration);
  expect(reward.refundedMaterials,{'item:iron':7}); // 75個の累積実消費、10%切捨て。
  expect(restarted.state.inventory.stacks['item:iron'],34);
  expect(restarted.state.world.magicCrystals,8);
  expect(restarted.state.inventory.equipment,isEmpty);
  expect(restarted.state.inventory.equipmentSkillHistories,isEmpty);
  final finalState=await LocalStore(directory:dir).load();
  expect(finalState.inventory.equipment,isEmpty);
  expect(finalState.inventory.equipmentSkillHistories,isEmpty);
  expect(finalState.inventory.equipmentSkillSeed,isNotNull);
  expect(finalState.inventory.stacks['item:iron'],34);
 });
 test('強化保存失敗と分解保存失敗で確定済み資産・履歴を維持',() async {
  final dir=await Directory.systemTemp.createTemp('equipment-lifecycle-fault-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_FaultStore(dir);
  final c=controller(store);addTearDown(c.dispose);await c.initialize();
  c.state.world.gold=100;c.state.world.magicCrystals=10;c.state.inventory.addStack('item:iron',100);
  await store.save(c.state);await c.purchaseWorldOffer('shop:sword',0);
  final id=c.state.inventory.equipment.values.single.id;
  await c.enhanceWorldItem(id,0);await c.enhanceWorldItem(id,1);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.enhanceWorldItem(id,2),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  store.fail=false;await c.enhanceWorldItem(id,2);
  final committed=jsonEncode(c.state.toJson()),committedBytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.dismantleWorldItem(id,3),throwsStateError);
  expect(jsonEncode(c.state.toJson()),committed);expect(await primary.readAsString(),committedBytes);
  expect(c.state.inventory.equipmentSkillHistories[id]!.grants.single.milestone,3);
 });
}
