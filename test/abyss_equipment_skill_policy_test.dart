import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_equipment_skill_policy.dart';
import 'package:level_me/world/abyss_inventory.dart';

void main(){
 const expected=<EquipmentRarity,List<int>>{
  EquipmentRarity.n:[],
  EquipmentRarity.r:[5],
  EquipmentRarity.sr:[5,10],
  EquipmentRarity.ssr:[5,10,15],
  EquipmentRarity.ur:[5,10,15,20],
  EquipmentRarity.lr:[4,8,12,16,20],
  EquipmentRarity.gr:[3,6,9,12,16,20],
 };
 test('承認済みの全希少度の枠数と付与段階が一致する',(){
  expect(expected.keys.toSet(),EquipmentRarity.values.where((r)=>r!=EquipmentRarity.ex).toSet());
  for(final entry in expected.entries){
   final steps=EquipmentSkillPolicy.milestones(entry.key);
   expect(steps,entry.value);
   expect(EquipmentSkillPolicy.slotCount(entry.key),entry.value.length);
   expect(EquipmentSkillPolicy.reachedMilestones(entry.key,20),entry.value);
   expect(EquipmentSkillPolicy.reachedMilestones(entry.key,0),isEmpty);
  }
 });
 test('全希少度の0〜20の各強化段階に対し新規付与は一度だけ成立する',(){
  for(final entry in expected.entries){
   final grants=<int>[];
   for(var level=1;level<=20;level++){
    final grant=EquipmentSkillPolicy.nextGrant(entry.key,level-1,level);
    expect(grant,entry.value.contains(level)?level:null);
    if(grant!=null)grants.add(grant);
    expect(EquipmentSkillPolicy.reachedMilestones(entry.key,level),grants);
   }
   expect(grants,entry.value);
  }
 });
 test('付与段階一覧は外部から変更できない',(){
  expect(()=>EquipmentSkillPolicy.milestones(EquipmentRarity.gr)[0]=1,throwsUnsupportedError);
  expect(()=>EquipmentSkillPolicy.reachedMilestones(EquipmentRarity.gr,9).clear(),throwsUnsupportedError);
 });
 test('負値・上限超過・飛び級・再強化・巻き戻しを拒否する',(){
  for(final rarity in expected.keys){
   for(final invalid in [-1,21]){
    expect(()=>EquipmentSkillPolicy.reachedMilestones(rarity,invalid),throwsRangeError);
    expect(()=>EquipmentSkillPolicy.nextGrant(rarity,invalid,1),throwsRangeError);
    expect(()=>EquipmentSkillPolicy.nextGrant(rarity,0,invalid),throwsRangeError);
   }
   for(final pair in [(0,0),(4,6),(5,5),(5,4),(20,20),(20,0)]){
    expect(()=>EquipmentSkillPolicy.nextGrant(rarity,pair.$1,pair.$2),throwsStateError);
   }
   expect(()=>EquipmentSkillPolicy.nextGrant(rarity,20,21),throwsRangeError);
  }
 });
 test('EXは空枠扱いせず未決のため拒否する',(){
  expect(()=>EquipmentSkillPolicy.milestones(EquipmentRarity.ex),throwsUnsupportedError);
  expect(()=>EquipmentSkillPolicy.slotCount(EquipmentRarity.ex),throwsUnsupportedError);
  expect(()=>EquipmentSkillPolicy.reachedMilestones(EquipmentRarity.ex,0),throwsUnsupportedError);
  expect(()=>EquipmentSkillPolicy.nextGrant(EquipmentRarity.ex,0,1),throwsUnsupportedError);
 });
 test('抽選Lvの境界は1〜10、強化値とは独立する',(){
  for(var level=-1;level<=21;level++){
   expect(EquipmentSkillPolicy.validSkillLevel(level),level>=1&&level<=10);
  }
 });
}
