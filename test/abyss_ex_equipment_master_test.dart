import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/abyss_equipment_skill_master.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_ex_equipment_skill.dart';
import 'package:level_me/world/abyss_ex_equipment_master.dart';
import 'package:level_me/world/abyss_inventory.dart';

void main(){
 final equipment=EquipmentCatalog(const [
  EquipmentDefinition(id:'equipment:ex_a',name:'test A',slot:EquipmentSlot.hands,rarity:EquipmentRarity.ex),
  EquipmentDefinition(id:'equipment:ex_b',name:'test B',slot:EquipmentSlot.body,rarity:EquipmentRarity.ex),
  EquipmentDefinition(id:'equipment:gr',name:'test GR',slot:EquipmentSlot.hands,rarity:EquipmentRarity.gr),
 ]);
 final random=EquipmentSkillMaster(const [
  EquipmentSkillMasterEntry(id:'equipment_skill:attack',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.physicalPercent,perLevel:100),
  EquipmentSkillMasterEntry(id:'equipment_skill:defense',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.defense,effect:EquipmentEffect.defensePercent,perLevel:100),
 ]);
 final normal=ExEffectRule.normal(effect:EquipmentEffect.physicalPercent,stacking:ExEffectStacking.additive,capScope:ExEffectCapScope.sharedWithNormal,cap:30000);
 final special=ExEffectRule.special(id:'equipment_ex_effect:test',stacking:ExEffectStacking.highestOnly,cap:100);
 final cost=ExEffectRule.special(id:'equipment_ex_effect:cost',stacking:ExEffectStacking.additive,cap:100);
 final values={1:1000,7:7000};
 final auto=ExFixedSkillDefinition(id:'equipment_ex_skill:auto',name:'auto',activation:ExSkillActivation.automatic,effects:[ExFixedEffect(ruleId:normal.id,valuesByLevel:values)]);
 final manual=ExFixedSkillDefinition(id:'equipment_ex_skill:manual',name:'manual',activation:ExSkillActivation.manual,effects:[ExFixedEffect(ruleId:special.id,valuesByLevel:{3:10}),ExFixedEffect(ruleId:cost.id,valuesByLevel:{3:5},drawback:true)]);
 ExEquipmentSkillLayout layout(String id,EquipmentSlot slot,List<ExFixedEquipmentSkill> skills,List<int> milestones)=>ExEquipmentSkillLayout(masterId:id,slot:slot,fixedSkills:skills,randomMilestones:milestones);
 final a=layout('equipment:ex_a',EquipmentSlot.hands,[ExFixedEquipmentSkill(id:auto.id,level:7),ExFixedEquipmentSkill(id:manual.id,level:3)],[3,8,13,20]);
 final b=layout('equipment:ex_b',EquipmentSlot.body,[ExFixedEquipmentSkill(id:auto.id,level:1)],[5,10,20]);
 ExEquipmentMaster make({List<ExEquipmentSkillLayout>? layouts,List<ExFixedSkillDefinition>? skills,List<ExEffectRule>? rules})=>ExEquipmentMaster(equipment:equipment,randomMaster:random,layouts:layouts??[a,b],fixedSkills:skills??[auto,manual],effectRules:rules??[normal,special,cost]);
 test('個別枠・固定Lv・自動/任意発動・代償の定義、複数個体の固定性能',(){
  final master=make();
  expect(master.layouts[a.masterId]!.randomMilestones,[3,8,13,20]);
  expect(master.layouts[b.masterId]!.randomMilestones,[5,10,20]);
  for(var level=0;level<=20;level++){
   for(final id in ['eq_1','eq_2']){
    final item=EquipmentInstance(id:id,masterId:a.masterId,slot:a.slot,rarity:EquipmentRarity.ex,enhancement:level);
    final fixed=master.resolveFixedSkills(item);
    expect(fixed.map((f)=>f.level),[7,3]);
    expect(fixed.first.skill.effects.single.valuesByLevel[fixed.first.level],7000);
    expect(fixed.last.skill.activation,ExSkillActivation.manual);
    expect(fixed.last.skill.effects.last.drawback,true);
    expect(master.requireLayout(item).reachedRandomMilestones(item),[3,8,13,20].where((n)=>n<=level).toList());
   }
  }
  final other=EquipmentInstance(id:'eq_3',masterId:b.masterId,slot:b.slot,rarity:EquipmentRarity.ex);
  expect(master.resolveFixedSkills(other).single.level,1);
  expect(random.entries.map((e)=>e.id),isNot(contains(auto.id)));
  expect(()=>master.resolveFixedSkills(EquipmentInstance(id:'eq_4',masterId:a.masterId,slot:a.slot,rarity:EquipmentRarity.gr)),throwsStateError);
 });
 test('登録時に未知・重複・部位/希少度不一致・未定義Lv・効果欠落を拒否',(){
  expect(()=>make(layouts:[a,a]),throwsArgumentError);
  expect(()=>make(skills:[auto,auto,manual]),throwsArgumentError);
  expect(()=>make(rules:[normal,normal,special,cost]),throwsArgumentError);
  expect(()=>make(skills:[auto]),throwsArgumentError);
  expect(()=>make(rules:[normal,special]),throwsArgumentError);
  for(final bad in [
   layout('equipment:missing',a.slot,a.fixedSkills,[5]),
   layout('equipment:gr',a.slot,a.fixedSkills,[5]),
   layout(a.masterId,EquipmentSlot.body,a.fixedSkills,[5]),
   layout(a.masterId,a.slot,[ExFixedEquipmentSkill(id:auto.id,level:2)],[5]),
  ]){expect(()=>make(layouts:[bad]),throwsArgumentError);}
  for(final id in ['skill:time_stop','equipment_skill:attack','equipment_ex_skill:','equipment_ex_skill: bad']){
   expect(()=>ExFixedSkillDefinition(id:id,name:'invalid',activation:ExSkillActivation.manual,effects:auto.effects),throwsArgumentError);
  }
 });
 test('効果別上限/重複規則と不変値、未承認の通常上限上書きを拒否',(){
  final master=make();values[7]=1;
  expect(master.fixedSkills[auto.id]!.effects.single.valuesByLevel[7],7000);
  expect(()=>master.layouts.clear(),throwsUnsupportedError);
  expect(()=>auto.effects.clear(),throwsUnsupportedError);
  expect(()=>auto.effects.single.valuesByLevel.clear(),throwsUnsupportedError);
  expect(master.effectRules[normal.id]!.stacking,ExEffectStacking.additive);
  expect(master.effectRules[special.id]!.stacking,ExEffectStacking.highestOnly);
  expect(()=>ExEffectRule.normal(effect:EquipmentEffect.physicalPercent,stacking:ExEffectStacking.additive,capScope:ExEffectCapScope.sharedWithNormal,cap:30001),throwsArgumentError);
  expect(()=>ExEffectRule.normal(effect:EquipmentEffect.physicalPercent,stacking:ExEffectStacking.additive,capScope:ExEffectCapScope.sharedWithNormal,cap:100),throwsArgumentError);
  final independent=ExEffectRule.normal(effect:EquipmentEffect.physicalPercent,stacking:ExEffectStacking.highestOnly,capScope:ExEffectCapScope.independent,cap:10000);
  expect(independent.cap,10000);
  final invalid=ExFixedSkillDefinition(id:auto.id,name:'invalid',activation:ExSkillActivation.automatic,effects:[ExFixedEffect(ruleId:normal.id,valuesByLevel:{7:30001})]);
  expect(()=>make(skills:[invalid,manual]),throwsArgumentError);
 });
}
