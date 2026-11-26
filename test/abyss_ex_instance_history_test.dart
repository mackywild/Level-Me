import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/abyss_equipment_skill_master.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_ex_equipment_skill.dart';
import 'package:level_me/world/abyss_ex_equipment_master.dart';
import 'package:level_me/world/abyss_equipment_enhancement_draw.dart';
import 'package:level_me/world/abyss_inventory.dart';

void main(){
 const id='equipment:ex_test',iron='item:iron',special='item:ex_test';
 final catalog=EquipmentCatalog(const [EquipmentDefinition(id:id,name:'test',slot:EquipmentSlot.hands,rarity:EquipmentRarity.ex)]);
 EquipmentSkillMaster random({int perLevel=100})=>EquipmentSkillMaster([
  EquipmentSkillMasterEntry(id:'equipment_skill:attack',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.physicalPercent,perLevel:perLevel),
 ]);
 ExEquipmentMaster master(EquipmentSkillMaster random,{List<int> stages=const [2,7,20],int fixedValue=1000}){
  final rule=ExEffectRule.normal(effect:EquipmentEffect.physicalPercent,stacking:ExEffectStacking.additive,capScope:ExEffectCapScope.sharedWithNormal,cap:30000);
  final fixed=ExFixedSkillDefinition(id:'equipment_ex_skill:test',name:'test',activation:ExSkillActivation.automatic,effects:[ExFixedEffect(ruleId:rule.id,valuesByLevel:{7:fixedValue})]);
  return ExEquipmentMaster(equipment:catalog,randomMaster:random,layouts:[ExEquipmentSkillLayout(masterId:id,slot:EquipmentSlot.hands,fixedSkills:[ExFixedEquipmentSkill(id:fixed.id,level:7)],randomMilestones:stages)],fixedSkills:[fixed],effectRules:[rule]);
 }
 AbyssInventory inventory(){
  final inv=AbyssInventory();inv.addStack(iron,100);inv.addStack(special,100);
  inv.addEquipment('equipment:normal',EquipmentSlot.body,EquipmentRarity.r);inv.activateEquipmentSkills(7);
  return inv;
 }
 AbyssInventory roundTrip(AbyssInventory inv)=>AbyssInventory.fromJson(jsonDecode(jsonEncode(inv.toJson())) as Map<String,dynamic>);
 test('個別段階を+20まで確定、再読込・再試行で抽選一致、固定Lvは不変',(){
  final r=random(),ex=master(r);
  var inv=inventory();
  final a=ex.acquire(inv,id),b=ex.acquire(inv,id);
  expect(a.id,isNot(b.id));expect(inv.toJson()['version'],3);
  for(var level=0;level<20;level++){
   final item=inv.equipment[a.id]!;
   final grant=EquipmentEnhancementDraw.prepare(inv,item,r,exMaster:ex);
   expect(grant?.milestone,[2,7,20].contains(level+1)?level+1:null);
   final restored=roundTrip(inv);
   expect(EquipmentEnhancementDraw.prepare(restored,restored.equipment[a.id]!,r,exMaster:ex)?.toJson(),grant?.toJson());
   final before=jsonEncode(inv.toJson());
   expect(()=>inv.enhanceWithMaterials(a.id,level,{iron:1,special:101},skillGrant:grant),throwsStateError);
   expect(jsonEncode(inv.toJson()),before);
   inv.enhanceWithMaterials(a.id,level,{iron:1,special:2},skillGrant:grant);
   inv=roundTrip(inv);ex.validateInventory(inv);
   expect(ex.resolveFixedSkills(inv.equipment[a.id]!).single.level,7);
  }
  expect(inv.equipmentSkillHistories[a.id]!.grants.map((g)=>g.milestone),[2,7,20]);
  expect(inv.equipmentSkillHistories[b.id]!.grants,isEmpty);
  expect(inv.enhancementRefund(inv.equipment[a.id]!),{iron:2,special:4});
  expect(()=>EquipmentEnhancementDraw.prepare(inv,inv.equipment[a.id]!,r,exMaster:ex),throwsRangeError);
  expect(()=>inv.equip(a.id),throwsStateError);
  expect(()=>r.validateInventory(inv),throwsStateError);
  inv.removeEquipment(a.id,20);expect(inv.exSkillLayouts.containsKey(a.id),false);expect(inv.toJson()['version'],3);
  inv.removeEquipment(b.id,0);expect(roundTrip(inv).toJson()['version'],2);
 });
 test('登録定義の変更・未登録取得・旧API・単素材・誤段階を拒否',(){
  final r=random(),ex=master(r),inv=inventory();
  final item=ex.acquire(inv,id);
  final before=jsonEncode(inv.toJson());
  expect(()=>ex.acquire(inv,'equipment:missing'),throwsStateError);
  expect(()=>inv.addEquipment(id,EquipmentSlot.hands,EquipmentRarity.ex),throwsStateError);
  expect(()=>inv.enhanceWithMaterial(item.id,0,iron,1),throwsStateError);
  expect(()=>inv.enhanceWithMaterials(item.id,0,{iron:1,special:1},skillGrant:const StoredEquipmentSkill(milestone:1,skillId:'equipment_skill:attack',level:1)),throwsFormatException);
  expect(()=>master(r,stages:[3,7,20]).validateInventory(inv),throwsFormatException);
  expect(()=>master(r,fixedValue:2000).validateInventory(inv),throwsFormatException);
  expect(()=>master(random(perLevel:101)).validateInventory(inv),throwsFormatException);
  expect(()=>EquipmentEnhancementDraw.prepare(inv,item,r),throwsStateError);
  expect(jsonEncode(inv.toJson()),before);
 });
 test('版3のEX参照/履歴欠落・旧版混入・装着・素材履歴欠落を拒否',(){
  final r=random(),ex=master(r),inv=inventory(),item=ex.acquire(inv,id);
  inv.enhanceWithMaterials(item.id,0,{iron:1,special:2});
  Map<String,dynamic> raw()=>jsonDecode(jsonEncode(inv.toJson())) as Map<String,dynamic>;
  for(final change in <void Function(Map<String,dynamic>)>[
   (j)=>j.remove('exSkillLayouts'),
   (j)=>j['version']=2,
   (j)=>j['equipmentSkills']['items'].remove(item.id),
   (j)=>j['equipmentSkills']['items'][item.id]['startEnhancement']=1,
   (j)=>j['exSkillLayouts'][item.id]['milestones']=[2,2],
   (j)=>j['equipped']['hands']=item.id,
   (j)=>j.remove('enhancementCosts'),
   (j)=>j['enhancementCosts']['items'][item.id][0]['materials'].remove(special),
  ]){final j=raw();change(j);expect(()=>AbyssInventory.fromJson(j),throwsFormatException);}
  final altered=raw();altered['exSkillLayouts'][item.id]['fingerprint']=List.filled(64,'a').join();
  expect(()=>ex.validateInventory(AbyssInventory.fromJson(altered)),throwsFormatException);
 });
}
