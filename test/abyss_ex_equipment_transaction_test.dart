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
import 'package:level_me/world/abyss_equipment_enhancement_draw.dart';
import 'package:level_me/world/abyss_enhancement.dart';
import 'package:level_me/world/abyss_dismantle.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Store extends LocalStore {
 _Store(Directory dir):super(directory:dir);
 int? failOn;
 int calls=0;
 @override Future<void> save(AppStateData state) async{
  calls++;
  if(calls==failOn)throw StateError('Injected save failure');
  await super.save(state);
 }
}
void main(){
 const now=1700000000000,id='equipment:ex_test',iron='item:iron',special='item:ex_test',offer='ex_offer:test';
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final equipment=EquipmentCatalog(const [EquipmentDefinition(id:id,name:'EX test',slot:EquipmentSlot.hands,rarity:EquipmentRarity.ex)]);
 final random=EquipmentSkillMaster(const [EquipmentSkillMasterEntry(id:'equipment_skill:attack',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.physicalPercent,perLevel:100)]);
 final rule=ExEffectRule.normal(effect:EquipmentEffect.physicalPercent,stacking:ExEffectStacking.additive,capScope:ExEffectCapScope.sharedWithNormal,cap:30000);
 final fixed=ExFixedSkillDefinition(id:'equipment_ex_skill:test',name:'test',activation:ExSkillActivation.automatic,effects:[ExFixedEffect(ruleId:rule.id,valuesByLevel:{7:1000})]);
 final master=ExEquipmentMaster(equipment:equipment,randomMaster:random,layouts:[ExEquipmentSkillLayout(masterId:id,slot:EquipmentSlot.hands,fixedSkills:[ExFixedEquipmentSkill(id:fixed.id,level:7)],randomMilestones:[1,20])],fixedSkills:[fixed],effectRules:[rule]);
 final plan=ExEnhancementMaterialPlan(normalMaterialId:iron,exMaterialId:special,normalSchedule:EnhancementMaterialSchedule(List.generate(20,(i)=>i+1)),exSchedule:EnhancementMaterialSchedule(List.generate(20,(i)=>(i+1)*2)));
 ExEquipmentTransactionPolicy policy({List<String> normal=const [iron],List<String> ex=const [special],bool automatic=false})=>ExEquipmentTransactionPolicy(master:master,enableAutomaticEffects:automatic,normalMaterials:normal,exMaterials:ex,recipes:[ExEnhancementRecipe(masterId:id,materials:plan,gold:2)],offers:const [ExAcquisitionOffer(id:offer,masterId:id,magicCrystals:5)]);
 final dismantle=DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.ex,materialId:iron,quantity:1,magicCrystals:1)]);
 AppController controller(LocalStore store,{bool automatic=false})=>AppController(store,equipmentCatalog:equipment,exEquipmentPolicy:policy(automatic:automatic),dismantlePolicy:dismantle,equipmentSkillSeedRandom:Random(7),clockMs:()=>now);
 test('初回seedと取得保存失敗、再試行、取得番号・復元世代拒否',() async{
  final dir=await Directory.systemTemp.createTemp('ex-acquire-');addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);final c=controller(store);addTearDown(c.dispose);await c.initialize();
  c.state.world.magicCrystals=20;await store.save(c.state);
  final before=jsonEncode(c.state.toJson());final primary=File('${dir.path}/${LocalStore.fileName}');final bytes=await primary.readAsString();
  store.failOn=store.calls+1;
  await expectLater(c.acquireExWorldItem(offer,0,expectedGeneration:c.restoreGeneration),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  store.failOn=store.calls+2;
  await expectLater(c.acquireExWorldItem(offer,0,expectedGeneration:c.restoreGeneration),throwsStateError);
  expect(c.state.inventory.equipmentSkillSeed,isNotNull);expect(c.state.inventory.equipment,isEmpty);expect(c.state.world.magicCrystals,20);
  final restored=controller(LocalStore(directory:dir));addTearDown(restored.dispose);await restored.initialize();
  final item=await restored.acquireExWorldItem(offer,0,expectedGeneration:restored.restoreGeneration);
  expect(restored.state.world.magicCrystals,15);expect(restored.state.world.shopSequence,1);
  expect(restored.state.inventory.exSkillLayouts.containsKey(item.id),true);
  await expectLater(restored.acquireExWorldItem(offer,0,expectedGeneration:restored.restoreGeneration),throwsStateError);
  await expectLater(restored.acquireExWorldItem(offer,1,expectedGeneration:restored.restoreGeneration+1),throwsStateError);
  await expectLater(restored.equipWorldItem(item.id),throwsStateError);
 });
 test('2素材/G/付与の一括保存失敗と再試行、+20・分解還元・再起動',() async{
  final dir=await Directory.systemTemp.createTemp('ex-enhance-');addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);final c=controller(store);addTearDown(c.dispose);await c.initialize();
  c.state.world.magicCrystals=10;c.state.world.gold=100;
  c.state.inventory.addStack(iron,210);c.state.inventory.addStack(special,420);await store.save(c.state);
  final item=await c.acquireExWorldItem(offer,0,expectedGeneration:c.restoreGeneration);
  final expected=EquipmentEnhancementDraw.prepare(c.state.inventory,item,random,exMaster:master)!;
  final before=jsonEncode(c.state.toJson());final primary=File('${dir.path}/${LocalStore.fileName}');final bytes=await primary.readAsString();
  store.failOn=store.calls+1;
  await expectLater(c.enhanceWorldItem(item.id,0,expectedGeneration:c.restoreGeneration),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  final restored=controller(LocalStore(directory:dir));addTearDown(restored.dispose);await restored.initialize();
  for(var lv=0;lv<20;lv++){
   await restored.enhanceWorldItem(item.id,lv,expectedGeneration:restored.restoreGeneration);
  }
  final history=restored.state.inventory.equipmentSkillHistories[item.id]!;
  expect(history.grants.first.toJson(),expected.toJson());expect(history.grants.map((g)=>g.milestone),[1,20]);
  expect(restored.state.world.gold,60);expect(restored.state.inventory.stacks,isEmpty);
  await expectLater(restored.enhanceWorldItem(item.id,20,expectedGeneration:restored.restoreGeneration),throwsStateError);
  final raw=jsonDecode(await primary.readAsString()) as Map<String,dynamic>;
  final grant=raw['inventory']['equipmentSkills']['items'][item.id]['grants'][0];
  grant['level']=grant['level']==10?9:10;
  await File('${primary.path}.bak').writeAsString(jsonEncode(raw));
  final original=await primary.readAsString();
  await expectLater(restored.restoreBackup(),throwsFormatException);
  expect(await primary.readAsString(),original);
  final result=await restored.dismantleWorldItem(item.id,20,expectedGeneration:restored.restoreGeneration);
  expect(result.refundedMaterials,{iron:21,special:42});
  expect(restored.state.inventory.stacks,{iron:22,special:42});
  expect(restored.state.inventory.toJson()['version'],2);
 });
 test('RV-218: 復元で同一IDを再取得したEXは旧世代・世代省略の分解を拒否',() async{
  final dir=await Directory.systemTemp.createTemp('ex-dismantle-generation-');addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);final c=controller(store);addTearDown(c.dispose);await c.initialize();
  c.state.world.magicCrystals=20;await store.save(c.state);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final beforeAcquisition=await primary.readAsString();
  final oldGeneration=c.restoreGeneration;
  final old=await c.acquireExWorldItem(offer,0,expectedGeneration:oldGeneration);
  await File('${primary.path}.bak').writeAsString(beforeAcquisition);
  await c.restoreBackup();
  expect(c.restoreGeneration,isNot(oldGeneration));
  expect(c.state.inventory.equipment,isEmpty);
  final replacement=await c.acquireExWorldItem(offer,0,expectedGeneration:c.restoreGeneration);
  expect(replacement.id,old.id);expect(replacement.enhancement,old.enhancement);
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  final crystals=c.state.world.magicCrystals;
  await expectLater(c.dismantleWorldItem(old.id,old.enhancement),throwsStateError);
  await expectLater(c.dismantleWorldItem(old.id,old.enhancement,expectedGeneration:oldGeneration,expectedItem:old),throwsStateError);
  await expectLater(c.dismantleWorldItem(old.id,old.enhancement,expectedItem:old),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  expect(c.state.inventory.equipment.containsKey(replacement.id),true);
  expect(c.state.world.magicCrystals,crystals);
  final result=await c.dismantleWorldItem(replacement.id,replacement.enhancement,expectedGeneration:c.restoreGeneration,expectedItem:replacement);
  expect(result.magicCrystals,1);
  expect(c.state.world.magicCrystals,crystals+1);
  expect(c.state.inventory.stacks,{iron:1});
  expect(c.state.inventory.equipment,isEmpty);
  expect((await store.load()).inventory.equipment,isEmpty);
 });
 test('EX自動通常効果の装着・強化・戦闘snapshot・再起動・解除',() async{
  final dir=await Directory.systemTemp.createTemp('ex-auto-');addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);final c=controller(store,automatic:true);addTearDown(c.dispose);await c.initialize();
  c.state.world.magicCrystals=10;c.state.world.gold=100;
  c.state.inventory.addStack(iron,10);c.state.inventory.addStack(special,10);await store.save(c.state);
  final item=await c.acquireExWorldItem(offer,0,expectedGeneration:c.restoreGeneration);
  expect(policy(automatic:true).snapshot(c.state.inventory).value(EquipmentEffect.physicalPercent),0);
  final before=jsonEncode(c.state.toJson());final primary=File('${dir.path}/${LocalStore.fileName}');final bytes=await primary.readAsString();
  await expectLater(c.equipWorldItem(item.id),throwsStateError);
  store.failOn=store.calls+1;
  await expectLater(c.equipWorldItem(item.id,expectedGeneration:c.restoreGeneration),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);expect(await primary.readAsString(),bytes);
  store.failOn=null;
  await c.equipWorldItem(item.id,expectedGeneration:c.restoreGeneration);
  expect(c.state.inventory.toJson()['version'],4);
  expect(policy(automatic:true).snapshot(c.state.inventory).value(EquipmentEffect.physicalPercent),1000);
  await c.enhanceWorldItem(item.id,0,expectedGeneration:c.restoreGeneration);
  final grant=c.state.inventory.equipmentSkillHistories[item.id]!.grants.single;
  final total=1000+grant.level*100;
  expect(policy(automatic:true).snapshot(c.state.inventory).value(EquipmentEffect.physicalPercent),total);
  await c.startWorldBattle('p01_main');
  final b=c.state.world.battle!;
  expect(b.equipmentEffects!.physical,total);
  expect(b.stats.physical,c.worldStats.physical*(10000+total)~/10000);
  final restored=controller(LocalStore(directory:dir),automatic:true);addTearDown(restored.dispose);await restored.initialize();
  expect(restored.state.world.battle!.equipmentEffects!.physical,total);
  await expectLater(restored.unequipWorldItem(EquipmentSlot.hands,expectedGeneration:restored.restoreGeneration),throwsStateError);
  await restored.worldCommand(WorldCommand.retreat,b.id,b.turn);
  await expectLater(restored.unequipWorldItem(EquipmentSlot.hands),throwsStateError);
  await restored.unequipWorldItem(EquipmentSlot.hands,expectedGeneration:restored.restoreGeneration);
  expect(restored.state.inventory.toJson()['version'],3);
  expect(policy(automatic:true).snapshot(restored.state.inventory).value(EquipmentEffect.physicalPercent),0);
 });
 test('固定効果加算・最高値・上限と未接続定義の拒否',(){
  ExEquipmentTransactionPolicy custom(ExEffectStacking stacking,{bool independent=false,bool manual=false,bool cross=false}){
   final effect=cross?EquipmentEffect.hpPercent:EquipmentEffect.physicalPercent;
   final rule=ExEffectRule.normal(effect:effect,stacking:stacking,capScope:independent?ExEffectCapScope.independent:ExEffectCapScope.sharedWithNormal,cap:30000);
   final skills=[for(final i in [1,2])ExFixedSkillDefinition(id:'equipment_ex_skill:test_$i',name:'test',activation:manual?ExSkillActivation.manual:ExSkillActivation.automatic,effects:[ExFixedEffect(ruleId:rule.id,valuesByLevel:{7:20000})])];
   final ex=ExEquipmentMaster(equipment:equipment,randomMaster:random,layouts:[ExEquipmentSkillLayout(masterId:id,slot:EquipmentSlot.hands,fixedSkills:[for(final s in skills)ExFixedEquipmentSkill(id:s.id,level:7)],randomMilestones:[1,20])],fixedSkills:skills,effectRules:[rule]);
   return ExEquipmentTransactionPolicy(master:ex,enableAutomaticEffects:true,normalMaterials:[iron],exMaterials:[special],recipes:[ExEnhancementRecipe(masterId:id,materials:plan,gold:2)],offers:const []);
  }
  for(final stacking in ExEffectStacking.values){
   final p=custom(stacking),inv=AbyssInventory();inv.activateEquipmentSkills(7);
   final item=p.master.acquire(inv,id);
   p.requireEquippable(inv,item);inv.equip(item.id,allowRegisteredEx:true);
   expect(p.snapshot(inv).value(EquipmentEffect.physicalPercent),stacking==ExEffectStacking.additive?30000:20000);
  }
  for(final p in [custom(ExEffectStacking.additive,independent:true),custom(ExEffectStacking.additive,manual:true),custom(ExEffectStacking.additive,cross:true)]){
   final inv=AbyssInventory();inv.activateEquipmentSkills(7);final item=p.master.acquire(inv,id);
   expect(()=>p.requireEquippable(inv,item),throwsStateError);
  }
 });
 test('通常/EX素材種別不一致を登録時拒否',(){
  expect(()=>policy(normal:[special],ex:[iron]),throwsFormatException);
  expect(()=>policy(normal:[iron],ex:[iron,special]),throwsFormatException);
 });
}
