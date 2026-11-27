import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/abyss_equipment_skill_master.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_ex_equipment_skill.dart';
import 'package:level_me/world/abyss_ex_equipment_master.dart';
import 'package:level_me/world/abyss_ex_equipment_transaction.dart';
import 'package:level_me/world/abyss_ex_battle_attack.dart';
import 'package:level_me/world/abyss_enhancement.dart';
import 'package:level_me/world/abyss_dismantle.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Store extends LocalStore {
 _Store(Directory dir):super(directory:dir);
 bool fail=false;
 @override Future<void> save(AppStateData state) async{
  if(fail){fail=false;throw StateError('Injected save failure');}
  await super.save(state);
 }
}
void main(){
 const now=1700000000000,sword='equipment:ex_integration_sword',armor='equipment:ex_integration_armor',iron='item:iron',special='item:ex_integration';
 const swordOffer='ex_offer:sword',armorOffer='ex_offer:armor';
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final catalog=EquipmentCatalog(const [
  EquipmentDefinition(id:sword,name:'試験EX剣',slot:EquipmentSlot.hands,rarity:EquipmentRarity.ex),
  EquipmentDefinition(id:armor,name:'試験EX鎧',slot:EquipmentSlot.body,rarity:EquipmentRarity.ex),
 ]);
 final random=EquipmentSkillMaster(const [
  EquipmentSkillMasterEntry(id:'equipment_skill:attack',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.physicalPercent,perLevel:100),
  EquipmentSkillMasterEntry(id:'equipment_skill:defense',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.defense,effect:EquipmentEffect.defensePercent,perLevel:100),
 ]);
 final attackRule=ExEffectRule.special(id:'equipment_ex_effect:manual_attack',stacking:ExEffectStacking.additive,cap:1000000);
 final healRule=ExEffectRule.special(id:'equipment_ex_effect:manual_heal_hp',stacking:ExEffectStacking.additive,cap:10000);
 final fixedRule=ExEffectRule.normal(effect:EquipmentEffect.physicalPercent,stacking:ExEffectStacking.highestOnly,capScope:ExEffectCapScope.sharedWithNormal,cap:30000);
 final attack=ExFixedSkillDefinition(id:'equipment_ex_skill:integration_attack',name:'attack',activation:ExSkillActivation.manual,manualSpec:ExManualSkillSpec(physicalCost:1,lifeDays:1,cooldown:0,maxUses:2,attackAttribute:ExAttackAttribute.physical),effects:[ExFixedEffect(ruleId:attackRule.id,valuesByLevel:{7:1})]);
 final heal=ExFixedSkillDefinition(id:'equipment_ex_skill:integration_heal',name:'heal',activation:ExSkillActivation.manual,manualSpec:ExManualSkillSpec(magicCost:1,lifeDays:2,cooldown:0,maxUses:1),effects:[ExFixedEffect(ruleId:healRule.id,valuesByLevel:{7:5000})]);
 final fixed=ExFixedSkillDefinition(id:'equipment_ex_skill:integration_fixed',name:'fixed',activation:ExSkillActivation.automatic,effects:[ExFixedEffect(ruleId:fixedRule.id,valuesByLevel:{7:1000})]);
 final master=ExEquipmentMaster(equipment:catalog,randomMaster:random,layouts:[
  ExEquipmentSkillLayout(masterId:sword,slot:EquipmentSlot.hands,fixedSkills:[ExFixedEquipmentSkill(id:fixed.id,level:7),ExFixedEquipmentSkill(id:attack.id,level:7)],randomMilestones:[1,20]),
  ExEquipmentSkillLayout(masterId:armor,slot:EquipmentSlot.body,fixedSkills:[ExFixedEquipmentSkill(id:heal.id,level:7)],randomMilestones:[1,20]),
 ],fixedSkills:[attack,heal,fixed],effectRules:[attackRule,healRule,fixedRule]);
 final plan=ExEnhancementMaterialPlan(normalMaterialId:iron,exMaterialId:special,normalSchedule:EnhancementMaterialSchedule(List.generate(20,(i)=>10+i)),exSchedule:EnhancementMaterialSchedule(List.generate(20,(i)=>20+i)));
 final policy=ExEquipmentTransactionPolicy(master:master,enableAutomaticEffects:true,enableManualPlanning:true,enableManualExecution:true,enableManualRecovery:true,normalMaterials:[iron],exMaterials:[special],recipes:[
  for(final id in [sword,armor])ExEnhancementRecipe(masterId:id,materials:plan,gold:2),
 ],offers:const [ExAcquisitionOffer(id:swordOffer,masterId:sword,magicCrystals:5),ExAcquisitionOffer(id:armorOffer,masterId:armor,magicCrystals:5)]);
 final dismantle=DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.ex,materialId:iron,quantity:1,magicCrystals:1)]);
 AppController make(LocalStore s)=>AppController(s,equipmentCatalog:catalog,exEquipmentPolicy:policy,dismantlePolicy:dismantle,equipmentSkillSeedRandom:Random(7),clockMs:()=>now);
 test('EX混在ライフサイクル、同一turn競合両順、版10復元・分解還元',() async{
  final dir=await Directory.systemTemp.createTemp('ex-full-');addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);final c=make(store);addTearDown(c.dispose);
  await c.initialize();
  c.state.world.magicCrystals=20;c.state.world.gold=100;c.state.world.lifespan=BigInt.from(10);
  c.state.inventory.addStack(iron,100);c.state.inventory.addStack(special,100);
  final a=await c.acquireExWorldItem(swordOffer,0,expectedGeneration:c.restoreGeneration);
  final b=await c.acquireExWorldItem(armorOffer,1,expectedGeneration:c.restoreGeneration);
  for(final item in [a,b]){
   await c.enhanceWorldItem(item.id,0,expectedGeneration:c.restoreGeneration);
   expect(c.state.inventory.equipmentSkillHistories[item.id]!.grants.single.milestone,1);
   await c.equipWorldItem(item.id,expectedGeneration:c.restoreGeneration);
  }
  expect(c.state.world.gold,96);expect(c.state.inventory.stacks,{iron:80,special:60});
  expect(c.state.inventory.toJson()['version'],4);
  await c.setExManualSkillSlot(0,instanceId:a.id,skillId:attack.id,expectedGeneration:c.restoreGeneration);
  await c.setExManualSkillSlot(1,instanceId:b.id,skillId:heal.id,expectedGeneration:c.restoreGeneration);
  expect(c.state.inventory.toJson()['version'],5);
  c.state.world.hp=c.worldStats.hp~/2;c.state.world.hpAt=now;
  await c.startWorldBattle('p01_main');
  final initial=c.state.world.battle!;
  expect(initial.executionVersion,10);
  expect(initial.exAttacks.map((a)=>a.attribute),[ExAttackAttribute.physical,ExAttackAttribute.hpRecovery]);
  // EX first: queued ordinary command with the same expected turn must fail.
  final exFirst=c.useBattleExSkill(0,initial.id,initial.turn,expectedGeneration:c.restoreGeneration);
  final normalSecond=expectLater(c.worldCommand(WorldCommand.guard,initial.id,initial.turn,expectedGeneration:c.restoreGeneration),throwsStateError);
  await exFirst;await normalSecond;
  final next=c.state.world.battle!;
  expect(next.turn,initial.turn+1);expect(next.exAttacks.first.uses,1);
  // Ordinary first: queued EX command with the old turn must fail.
  final normalFirst=c.worldCommand(WorldCommand.guard,next.id,next.turn,expectedGeneration:c.restoreGeneration);
  final exSecond=expectLater(c.useBattleExSkill(1,next.id,next.turn,expectedGeneration:c.restoreGeneration),throwsStateError);
  await normalFirst;await exSecond;
  final active=c.state.world.battle!;
  expect(active.turn,next.turn+1);expect(active.exAttacks[1].uses,0);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.useBattleExSkill(1,active.id,active.turn,expectedGeneration:c.restoreGeneration),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  final restored=make(LocalStore(directory:dir));addTearDown(restored.dispose);await restored.initialize();
  final resumed=restored.state.world.battle!,magic=restored.state.world.magic;
  await restored.useBattleExSkill(1,resumed.id,resumed.turn,expectedGeneration:restored.restoreGeneration);
  final healed=restored.state.world.battle!;
  expect(healed.enemyHp,resumed.enemyHp);expect(healed.exAttacks.map((a)=>a.uses),[1,1]);
  expect(restored.state.world.magic,magic-1);expect(restored.state.world.lifespan,BigInt.from(7));
  final saved=await primary.readAsString(),raw=jsonDecode(saved) as Map<String,dynamic>;
  raw['world']['battle']['exAttacks'][1]['powerBps']=5001;
  await File('${primary.path}.bak').writeAsString(jsonEncode(raw));
  final published=jsonEncode(restored.state.toJson());
  await expectLater(restored.restoreBackup(),throwsFormatException);
  expect(await primary.readAsString(),saved);expect(jsonEncode(restored.state.toJson()),published);
  await restored.worldCommand(WorldCommand.retreat,healed.id,healed.turn,expectedGeneration:restored.restoreGeneration);
  for(final item in [a,b]){
   await restored.unequipWorldItem(item.slot,expectedGeneration:restored.restoreGeneration);
   final result=await restored.dismantleWorldItem(item.id,1,expectedGeneration:restored.restoreGeneration);
   expect(result.refundedMaterials,{iron:1,special:2});
  }
  expect(restored.state.inventory.exManualSlots,isEmpty);expect(restored.state.inventory.equipment,isEmpty);
  expect(restored.state.inventory.toJson()['version'],2);
  expect(restored.state.inventory.stacks,{iron:84,special:64});
  expect(restored.state.world.magicCrystals,12);
  final last=make(LocalStore(directory:dir));addTearDown(last.dispose);await last.initialize();
  expect(last.state.inventory.toJson(),restored.state.inventory.toJson());
 });
 test('同一世代の古い枠選択を拒否、保存失敗時も変更前選択を維持',() async{
  final dir=await Directory.systemTemp.createTemp('ex-selection-');addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);final c=make(store);addTearDown(c.dispose);await c.initialize();
  c.state.world.magicCrystals=20;
  final a=await c.acquireExWorldItem(swordOffer,0,expectedGeneration:c.restoreGeneration);
  await c.equipWorldItem(a.id,expectedGeneration:c.restoreGeneration);
  final gen=c.restoreGeneration;
  await c.setExManualSkillSlot(0,instanceId:a.id,skillId:attack.id,expectedGeneration:gen,checkExpectedSelection:true);
  final primary=File('${dir.path}/${LocalStore.fileName}'),before=jsonEncode(c.state.toJson());
  final bytes=await primary.readAsString();
  await expectLater(c.setExManualSkillSlot(0,expectedGeneration:gen,checkExpectedSelection:true),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  final expected=c.state.inventory.exManualSlots[0];
  store.fail=true;
  await expectLater(c.setExManualSkillSlot(0,expectedGeneration:gen,checkExpectedSelection:true,expectedSelection:expected),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  await c.setExManualSkillSlot(0,expectedGeneration:gen,checkExpectedSelection:true,expectedSelection:expected);
  expect(c.state.inventory.exManualSlots,isEmpty);
 });
}
