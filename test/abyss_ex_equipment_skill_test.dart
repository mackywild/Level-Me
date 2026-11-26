import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_equipment_skill_odds.dart';
import 'package:level_me/world/abyss_ex_equipment_skill.dart';

void main(){
 const fixed=ExFixedEquipmentSkill(id:'fixed_test',level:7);
 EquipmentInstance item(int level,{EquipmentRarity rarity=EquipmentRarity.ex,EquipmentSlot slot=EquipmentSlot.relic,String masterId='test_ex'})=>
  EquipmentInstance(id:'eq_1',masterId:masterId,slot:slot,rarity:rarity,enhancement:level);
 ExEquipmentSkillLayout layout({List<ExFixedEquipmentSkill> fixedSkills=const [fixed],List<int> milestones=const [4,12,20]})=>
  ExEquipmentSkillLayout(masterId:'test_ex',slot:EquipmentSlot.relic,fixedSkills:fixedSkills,randomMilestones:milestones);

 test('固有スキルは入手時点から固定Lvで解放、ランダム枠とは独立',(){
  final policy=layout();
  expect(policy.randomPool,EquipmentSkillPool.relic);
  for(var level=0;level<=20;level++){
   final skills=policy.unlockedFixedSkills(item(level));
   expect(skills.single.id,'fixed_test');
   expect(skills.single.level,7);
   expect(policy.reachedRandomMilestones(item(level)),[4,12,20].where((n)=>n<=level).toList());
   if(level<20)expect(policy.nextRandomGrant(item(level),level+1),[4,12,20].contains(level+1)?level+1:null);
  }
  expect(()=>policy.nextRandomGrant(item(20),21),throwsRangeError);
  expect(()=>policy.nextRandomGrant(item(0),4),throwsStateError);
 });
 test('個別定義を防御的にコピーし不正定義を拒否',(){
  final skills=[fixed];
  final milestones=[4,12,20];
  final policy=layout(fixedSkills:skills,milestones:milestones);
  skills.clear();milestones.clear();
  expect(policy.fixedSkills.single,fixed);
  expect(policy.randomMilestones,[4,12,20]);
  expect(()=>policy.fixedSkills.clear(),throwsUnsupportedError);
  expect(()=>policy.randomMilestones.clear(),throwsUnsupportedError);
  expect(()=>policy.reachedRandomMilestones(item(20)).clear(),throwsUnsupportedError);
  for(final invalid in <List<int>>[[],[0],[21],[4,4],[12,4],[-1]]){
   expect(()=>layout(milestones:invalid),throwsArgumentError);
  }
  for(final invalid in <List<ExFixedEquipmentSkill>>[[],[fixed,fixed],[const ExFixedEquipmentSkill(id:' ',level:1)],[const ExFixedEquipmentSkill(id:'bad',level:0)],[const ExFixedEquipmentSkill(id:'bad',level:11)]]){
   expect(()=>layout(fixedSkills:invalid),throwsArgumentError);
  }
 });
 test('別個体定義・非EX・異なる部位・不正強化値を拒否',(){
  final policy=layout();
  for(final invalid in [item(0,rarity:EquipmentRarity.gr),item(0,masterId:'other'),item(0,slot:EquipmentSlot.hands)]){
   expect(()=>policy.unlockedFixedSkills(invalid),throwsStateError);
   expect(()=>policy.reachedRandomMilestones(invalid),throwsStateError);
   expect(()=>policy.nextRandomGrant(invalid,1),throwsStateError);
  }
  expect(()=>policy.unlockedFixedSkills(item(-1)),throwsRangeError);
  expect(()=>policy.reachedRandomMilestones(item(21)),throwsRangeError);
 });
 test('魔遺物は専用候補のみ、希少度重みと既存Lv帯を再利用',(){
  const common=EquipmentSkillCandidate(id:'relic_c',pool:EquipmentSkillPool.relic,rarity:EquipmentSkillRarity.common);
  const ultra=EquipmentSkillCandidate(id:'relic_u',pool:EquipmentSkillPool.relic,rarity:EquipmentSkillRarity.ultraRare);
  final pool=RelicEquipmentSkillPool([common,ultra]);
  for(var roll=0;roll<75;roll++){
   var call=0;
   expect(pool.drawType((bound)=>call++==0?roll:0).id,roll<70?'relic_c':'relic_u');
  }
  final rolls=[70,0,9999].iterator;
  final result=pool.drawWithLevelBand(EquipmentRarity.gr,(bound){rolls.moveNext();return rolls.current;});
  expect(result.skill.id,'relic_u');
  expect(result.band,EquipmentSkillLevelBand.maxLevel);
  expect(()=>pool.drawWithLevelBand(EquipmentRarity.ex,(_)=>throw StateError('must not draw')),throwsUnsupportedError);
  expect(()=>RelicEquipmentSkillPool([const EquipmentSkillCandidate(id:'accessory',pool:EquipmentSkillPool.special,rarity:EquipmentSkillRarity.common)]),throwsArgumentError);
  expect(()=>RelicEquipmentSkillPool([]).drawType((_)=>throw ArgumentError('must not draw')),throwsStateError);
 });
}
