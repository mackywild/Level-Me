import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_equipment_skill_master.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/abyss_relic_skill_master.dart';

RelicEffectRule rule(RelicEffect e)=>RelicEffectRule(effect:e,stacking:RelicStacking.highestOnly,chanceCapBps:10000,magnitudeCap:e.maximumMagnitude,maxUses:e==RelicEffect.lowHpAttack?null:1,hpThresholdBps:e==RelicEffect.lowHpAttack?3000:null);
RelicSkillDefinition skill(RelicEffect e,EquipmentSkillRarity rarity,{String? id,List<int>? chance,List<int>? magnitude})=>RelicSkillDefinition(id:id??'equipment_relic_skill:${e.name}',name:e.name,rarity:rarity,effect:e,chanceBpsByLevel:chance??List.generate(10,(i)=>e==RelicEffect.lowHpAttack?10000:100*(i+1)),magnitudeByLevel:magnitude??List.generate(10,(i)=>e.unit==RelicMagnitudeUnit.none?0:i+1));
EquipmentInstance item(EquipmentRarity rarity,{EquipmentSlot slot=EquipmentSlot.relic})=>EquipmentInstance(id:'eq_1',masterId:'equipment:relic_test',slot:slot,rarity:rarity);

void main(){
 final definitions=[for(var i=0;i<RelicEffect.values.length;i++)skill(RelicEffect.values[i],EquipmentSkillRarity.values[i~/2])];
 final rules=RelicEffect.values.map(rule).toList();
 final master=RelicSkillMaster(rules:rules,skills:definitions);
 test('Q96–101の6効果・型付き発動契機と単位・独立定義',(){
  expect(master.skills.length,6);expect(master.rules.length,6);
  expect(RelicEffect.battleStartHeal.trigger,RelicTrigger.battleStart);
  expect(RelicEffect.turnEndMagicRecovery.trigger,RelicTrigger.turnEnd);
  expect(RelicEffect.statusCleanse.trigger,RelicTrigger.turnEnd);
  expect(RelicEffect.lowHpAttack.trigger,RelicTrigger.lowHp);
  expect(RelicEffect.lethalSurvival.trigger,RelicTrigger.incomingLethal);
  expect(RelicEffect.victoryLifeReward.trigger,RelicTrigger.victory);
  expect(RelicEffect.victoryLifeReward.unit,RelicMagnitudeUnit.lifeDays);
  expect(RelicEffect.battleStartHeal.unit,RelicMagnitudeUnit.maxHpBps);
  expect(master.require(definitions.first.id).valueAt(10),(chanceBps:1000,magnitude:10));
  expect(()=>master.require('unknown'),throwsStateError);
 });
 test('効果別Lv曲線と防御上限、元リスト・取得マップからの変更拒否',(){
  final chance=List.filled(10,500),magnitude=List.generate(10,(i)=>i+1);
  final s=skill(RelicEffect.battleStartHeal,EquipmentSkillRarity.common,chance:chance,magnitude:magnitude);
  chance[0]=10000;magnitude[0]=10000;
  expect(s.valueAt(1),(chanceBps:500,magnitude:1));
  expect(()=>s.valueAt(0),throwsRangeError);expect(()=>s.valueAt(11),throwsRangeError);
  expect(()=>s.chanceBpsByLevel[0]=1,throwsUnsupportedError);
  expect(()=>master.skills.clear(),throwsUnsupportedError);
  expect(()=>master.rules.clear(),throwsUnsupportedError);
  expect(()=>skill(RelicEffect.lowHpAttack,EquipmentSkillRarity.common,chance:List.filled(10,1)),throwsArgumentError);
  expect(()=>skill(RelicEffect.lethalSurvival,EquipmentSkillRarity.common,magnitude:List.filled(10,1)),throwsArgumentError);
  expect(()=>skill(RelicEffect.battleStartHeal,EquipmentSkillRarity.common,magnitude:List.filled(10,10001)),throwsArgumentError);
  expect(()=>skill(RelicEffect.battleStartHeal,EquipmentSkillRarity.common,chance:List.filled(9,1)),throwsArgumentError);
  expect(()=>skill(RelicEffect.battleStartHeal,EquipmentSkillRarity.common,chance:List.filled(10,10001)),throwsArgumentError);
 });
 test('ID・重複・規則欠落・効果上限を検証し通常マスターは魔遺物を拒否',(){
  expect(()=>RelicSkillMaster(rules:[],skills:definitions),throwsArgumentError);
  expect(()=>RelicSkillMaster(rules:[rules.first,rules.first],skills:[]),throwsArgumentError);
  expect(()=>RelicSkillMaster(rules:rules,skills:[definitions.first,definitions.first]),throwsArgumentError);
  expect(()=>skill(RelicEffect.battleStartHeal,EquipmentSkillRarity.common,id:'equipment_skill:test'),throwsArgumentError);
  expect(()=>skill(RelicEffect.battleStartHeal,EquipmentSkillRarity.common,id:'equipment_relic_skill:a b'),throwsArgumentError);
  final cap=RelicEffectRule(effect:RelicEffect.battleStartHeal,stacking:RelicStacking.additive,chanceCapBps:500,magnitudeCap:10,maxUses:1);
  expect(()=>RelicSkillMaster(rules:[cap],skills:[definitions.first]),throwsArgumentError);
  expect(()=>RelicEffectRule(effect:RelicEffect.lowHpAttack,stacking:RelicStacking.additive,chanceCapBps:10000,magnitudeCap:30001,hpThresholdBps:3000),throwsArgumentError);
  expect(()=>RelicEffectRule(effect:RelicEffect.victoryLifeReward,stacking:RelicStacking.highestOnly,chanceCapBps:10000,magnitudeCap:10),throwsArgumentError);
  expect(()=>EquipmentSkillMaster(const [EquipmentSkillMasterEntry(id:'equipment_skill:bad_relic',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.relic,effect:EquipmentEffect.hpPercent,perLevel:100)]),throwsArgumentError);
 });
 test('70/25/5境界・帯と個別Lvの独立抽選・定義順不変',(){
  for(final (roll,rarity) in [(0,EquipmentSkillRarity.common),(69,EquipmentSkillRarity.common),(70,EquipmentSkillRarity.rare),(94,EquipmentSkillRarity.rare),(95,EquipmentSkillRarity.ultraRare),(99,EquipmentSkillRarity.ultraRare)]){
   final values=[roll,1,9999],bounds=<int>[];
   final result=master.draw(item(EquipmentRarity.gr),(bound){bounds.add(bound);return values.removeAt(0);});
   expect(result.skill.rarity,rarity);expect(result.level,10);expect(bounds,[100,2,10000]);expect(values,isEmpty);
  }
  final reversed=RelicSkillMaster(rules:rules.reversed,skills:definitions.reversed);
  final values=[0,0,0,2],other=List<int>.of(values),bounds=<int>[];
  final a=master.draw(item(EquipmentRarity.r),(bound){bounds.add(bound);return values.removeAt(0);});
  final b=reversed.draw(item(EquipmentRarity.r),(_)=>other.removeAt(0));
  expect(a.skill.id,b.skill.id);expect(a.level,3);expect(a.level,b.level);expect(bounds,[100,2,10000,3]);
 });
 test('空プール・欠落希少度再正規化・N/EX/非魔遺物・乱数範囲',(){
  final empty=RelicSkillMaster(rules:[],skills:[]);
  expect(empty.hasCandidates,false);
  expect(()=>empty.draw(item(EquipmentRarity.r),(_)=>0),throwsStateError);
  final one=RelicSkillMaster(rules:rules,skills:[definitions.last]);
  final bounds=<int>[];
  expect(one.draw(item(EquipmentRarity.gr),(bound){bounds.add(bound);return 0;}).skill.id,definitions.last.id);
  expect(bounds,[5,1,10000,3]);
  expect(()=>master.draw(item(EquipmentRarity.n),(_)=>0),throwsUnsupportedError);
  expect(()=>master.draw(item(EquipmentRarity.ex),(_)=>0),throwsStateError);
  expect(()=>master.draw(item(EquipmentRarity.r,slot:EquipmentSlot.ring),(_)=>0),throwsStateError);
  expect(()=>master.draw(item(EquipmentRarity.gr),(bound)=>bound),throwsRangeError);
  final values=[0,0,0,3];
  expect(()=>master.draw(item(EquipmentRarity.gr),(_)=>values.removeAt(0)),throwsRangeError);
 });
}
