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
import 'package:level_me/world/abyss_dismantle.dart';
import 'package:level_me/world/abyss_equipment_skill_master.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/abyss_relic_skill_master.dart';
import 'package:level_me/world/abyss_relic_enhancement_draw.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _FailStore extends LocalStore {
 _FailStore(Directory dir):super(directory:dir);
 bool fail=false;
 @override Future<void> save(AppStateData state) async{
  if(fail)throw StateError('Injected save failure');
  await super.save(state);
 }
}
RelicSkillMaster relicMaster({int days=7})=>RelicSkillMaster(rules:[
 RelicEffectRule(effect:RelicEffect.victoryLifeReward,stacking:RelicStacking.highestOnly,chanceCapBps:10000,magnitudeCap:100,maxUses:1),
],skills:[
 RelicSkillDefinition(id:'equipment_relic_skill:trial',name:'試験収奪',rarity:EquipmentSkillRarity.common,effect:RelicEffect.victoryLifeReward,chanceBpsByLevel:List.filled(10,10000),magnitudeByLevel:List.filled(10,days)),
]);

void main(){
 const now=1700000000000,relicId='equipment:relic_trial',swordId='equipment:sword_trial',iron='item:iron';
 final relic=relicMaster();
 final normal=EquipmentSkillMaster(const [EquipmentSkillMasterEntry(id:'equipment_skill:attack',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.physicalPercent,perLevel:100)]);
 final catalog=EquipmentCatalog(const [
  EquipmentDefinition(id:relicId,name:'試験魔遺物',slot:EquipmentSlot.relic,rarity:EquipmentRarity.r),
  EquipmentDefinition(id:swordId,name:'試験剣',slot:EquipmentSlot.hands,rarity:EquipmentRarity.r),
 ]);
 final enhance=EnhancementPolicy(const [EnhancementRecipe(rarity:EquipmentRarity.r,materialId:iron,quantity:10,gold:2)]);
 final dismantle=DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.r,materialId:iron,quantity:1,magicCrystals:1)]);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 AppController make(LocalStore store,{RelicSkillMaster? master,bool enabled=true})=>AppController(store,equipmentCatalog:catalog,equipmentSkillMaster:normal,relicSkillMaster:enabled?(master??relic):null,enhancementPolicy:enhance,dismantlePolicy:dismantle,equipmentSkillSeedRandom:Random(7),clockMs:()=>now);
 AbyssInventory copy(AbyssInventory inv)=>AbyssInventory.fromJson(jsonDecode(jsonEncode(inv.toJson())) as Map<String,dynamic>);
 test('決定的抽選・旧枠非遡及・版6・通常マスター拒否・分解後版2',(){
  final inv=AbyssInventory();
  final legacy=inv.addEquipment(relicId,EquipmentSlot.relic,EquipmentRarity.r);
  inv.addStack(iron,100);
  for(var n=0;n<5;n++){inv.enhanceWithMaterial(legacy.id,n,iron,10);}
  inv.activateEquipmentSkills(7);
  expect(inv.equipmentSkillHistories[legacy.id]!.startEnhancement,5);
  expect(inv.equipmentSkillHistories[legacy.id]!.grants,isEmpty);
  expect(inv.toJson()['version'],2);
  final item=inv.addEquipment(relicId,EquipmentSlot.relic,EquipmentRarity.r);
  for(var n=0;n<4;n++){inv.enhanceWithMaterial(item.id,n,iron,10);}
  final a=RelicEnhancementDraw.prepare(inv,inv.equipment[item.id]!,relic)!;
  final clone=copy(inv),b=RelicEnhancementDraw.prepare(clone,clone.equipment[item.id]!,relic)!;
  expect(a.toJson(),b.toJson());
  inv.enhanceWithMaterial(item.id,4,iron,10,skillGrant:a,relicFingerprint:RelicEnhancementDraw.fingerprint(relic));
  expect(inv.toJson()['version'],6);expect(copy(inv).toJson(),inv.toJson());
  RelicEnhancementDraw.validateInventory(inv,relic);
  expect(()=>normal.validateInventory(inv),throwsFormatException);
  expect(()=>RelicEnhancementDraw.validateInventory(inv,relicMaster(days:8)),throwsFormatException);
  Map<String,dynamic> raw()=>jsonDecode(jsonEncode(inv.toJson())) as Map<String,dynamic>;
  final old=raw();old['version']=2;expect(()=>AbyssInventory.fromJson(old),throwsFormatException);
  final missing=raw();missing['equipmentSkills']['items'][item.id].remove('relicFingerprint');expect(()=>AbyssInventory.fromJson(missing),throwsFormatException);
  final forged=raw();forged['equipmentSkills']['items'][item.id]['grants'][0]['level']=a.level==10?9:a.level+1;
  expect(()=>RelicEnhancementDraw.validateInventory(AbyssInventory.fromJson(forged),relic),throwsFormatException);
  inv.removeEquipment(item.id,5);expect(inv.toJson()['version'],2);
 });
 test('実ファイルの強化/保存失敗/再試行/通常装備混在/所有照合/勝利報酬/分解',() async{
  final dir=await Directory.systemTemp.createTemp('relic-integrated-');addTearDown(()=>dir.delete(recursive:true));
  final store=_FailStore(dir),c=make(store);addTearDown(c.dispose);await c.initialize();
  final item=c.state.inventory.addEquipment(relicId,EquipmentSlot.relic,EquipmentRarity.r);
  final sword=c.state.inventory.addEquipment(swordId,EquipmentSlot.hands,EquipmentRarity.r);
  c.state.inventory.addStack(iron,200);c.state.world.gold=100;
  await store.save(c.state);
  for(var n=0;n<4;n++){await c.enhanceWorldItem(item.id,n,expectedGeneration:c.restoreGeneration);}
  final expected=RelicEnhancementDraw.prepare(c.state.inventory,c.state.inventory.equipment[item.id]!,relic)!;
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.enhanceWorldItem(item.id,4,expectedGeneration:c.restoreGeneration),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  final reopened=make(LocalStore(directory:dir));addTearDown(reopened.dispose);await reopened.initialize();
  await reopened.enhanceWorldItem(item.id,4,expectedGeneration:reopened.restoreGeneration);
  expect(reopened.state.inventory.equipmentSkillHistories[item.id]!.grants.single.toJson(),expected.toJson());
  for(var n=0;n<5;n++){await reopened.enhanceWorldItem(sword.id,n);}
  await reopened.equipWorldItem(sword.id);
  await reopened.equipWorldItem(item.id,expectedGeneration:reopened.restoreGeneration);
  expect(reopened.state.inventory.toJson()['version'],6);
  expect(reopened.state.world.gold,80);expect(reopened.state.inventory.stacks[iron],100);
  await reopened.startWorldBattle('p01_main');
  final b=reopened.state.world.battle!;expect(b.executionVersion,13);
  final fileBefore=await primary.readAsString(),raw=jsonDecode(fileBefore) as Map<String,dynamic>;
  raw['world']['battle']['relicRecovery']['effects']['victoryLifeReward']['magnitude']=8;
  await File('${primary.path}.bak').writeAsString(jsonEncode(raw));
  await expectLater(reopened.restoreBackup(),throwsFormatException);
  expect(await primary.readAsString(),fileBefore);
  final disabled=make(LocalStore(directory:dir),enabled:false);addTearDown(disabled.dispose);
  await expectLater(disabled.initialize(),throwsFormatException);expect(await primary.readAsString(),fileBefore);
  final changed=make(LocalStore(directory:dir),master:relicMaster(days:8));addTearDown(changed.dispose);
  await expectLater(changed.initialize(),throwsFormatException);expect(await primary.readAsString(),fileBefore);
  final combatStore=_FailStore(dir),combat=make(combatStore);addTearDown(combat.dispose);await combat.initialize();
  final resumed=combat.state.world.battle!,life=combat.state.world.lifespan;
  final snapshot=jsonEncode(combat.state.toJson()),original=await primary.readAsString();
  combatStore.fail=true;
  await expectLater(combat.worldCommand(WorldCommand.claw,resumed.id,resumed.turn,expectedGeneration:combat.restoreGeneration),throwsStateError);
  expect(jsonEncode(combat.state.toJson()),snapshot);expect(await primary.readAsString(),original);
  combatStore.fail=false;
  await combat.worldCommand(WorldCommand.claw,resumed.id,resumed.turn,expectedGeneration:combat.restoreGeneration);
  expect(combat.state.world.battle,isNull);expect(combat.state.world.lifespan,life+BigInt.from(7));
  final saved=await primary.readAsString();
  await expectLater(combat.worldCommand(WorldCommand.claw,resumed.id,resumed.turn,expectedGeneration:combat.restoreGeneration),throwsStateError);
  expect(await primary.readAsString(),saved);
  await combat.unequipWorldItem(EquipmentSlot.relic,expectedGeneration:combat.restoreGeneration);
  final refund=await combat.dismantleWorldItem(item.id,5,expectedGeneration:combat.restoreGeneration);
  expect(refund.refundedMaterials,{iron:5});expect(combat.state.inventory.toJson()['version'],2);
 });
}
