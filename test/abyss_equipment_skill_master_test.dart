import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_equipment_skill_master.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_ex_equipment_skill.dart';
import 'package:level_me/world/abyss_inventory.dart';

void main(){
 const entry=EquipmentSkillMasterEntry(id:'equipment_skill:test',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.physicalPercent,perLevel:1000);
 final master=EquipmentSkillMaster([entry]);
 test('承認上限・分類・比例曲線・装着効果',(){
  expect(EquipmentSkillMaster.approvedCaps,{
   EquipmentEffect.physicalPercent:30000,EquipmentEffect.magicPercent:30000,EquipmentEffect.defensePercent:30000,
   EquipmentEffect.damageReduction:7000,EquipmentEffect.criticalChance:10000,EquipmentEffect.evasionChance:5000,
   EquipmentEffect.energyDiscount:5000,EquipmentEffect.cooldownReduction:5000,EquipmentEffect.extraAttackChance:5000,
  });
  expect(EquipmentSkillMaster.allowedEffects(EquipmentSkillPool.attack).length,5);
  expect(EquipmentSkillMaster.allowedEffects(EquipmentSkillPool.defense).length,5);
  expect(EquipmentSkillMaster.allowedEffects(EquipmentSkillPool.special).length,4);
  expect(EquipmentSkillMaster.allowedEffects(EquipmentSkillPool.relic),isEmpty);
  final inv=AbyssInventory();
  final item=inv.addEquipment('test',EquipmentSlot.hands,EquipmentRarity.gr);
  for(var i=0;i<20;i++){inv.enhance(item.id,i);}
  inv.equip(item.id);
  EquipmentSkillGrant grant(int milestone,int level)=>EquipmentSkillGrant(instanceId:item.id,milestone:milestone,skillId:entry.id,level:level);
  for(var level=1;level<=10;level++){
   expect(master.effectPolicy.snapshot(inv,[grant(3,level)]).value(EquipmentEffect.physicalPercent),level*1000);
  }
  expect(master.effectPolicy.snapshot(inv,[grant(3,10),grant(6,10),grant(9,10),grant(12,10)]).value(EquipmentEffect.physicalPercent),30000);
 });
 test('分類違い・主人公ID・重複・未承認上限・上書きを拒否',(){
  EquipmentSkillMasterEntry invalid(String id,EquipmentSkillPool pool,EquipmentEffect effect)=>EquipmentSkillMasterEntry(id:id,rarity:EquipmentSkillRarity.common,pool:pool,effect:effect,perLevel:100);
  for(final e in [
   invalid('skill:time',EquipmentSkillPool.attack,EquipmentEffect.physicalPercent),
   invalid(entry.id,EquipmentSkillPool.defense,EquipmentEffect.physicalPercent),
   invalid(entry.id,EquipmentSkillPool.attack,EquipmentEffect.penetration),
   invalid(entry.id,EquipmentSkillPool.relic,EquipmentEffect.physicalPercent),
  ]){expect(()=>EquipmentSkillMaster([e]),throwsArgumentError);}
  expect(()=>EquipmentSkillMaster([entry,entry]),throwsArgumentError);
  expect(()=>EquipmentSkillMaster([entry],additionalCaps:{EquipmentEffect.physicalPercent:100}),throwsArgumentError);
 });
 test('EXはGRと同じ全帯境界、帯内均等乱数と独立抽選',(){
  const ex=EquipmentInstance(id:'eq_1',masterId:'test',slot:EquipmentSlot.hands,rarity:EquipmentRarity.ex);
  const gr=EquipmentInstance(id:'eq_2',masterId:'test',slot:EquipmentSlot.hands,rarity:EquipmentRarity.gr);
  final layout=ExEquipmentSkillLayout(masterId:'test',slot:EquipmentSlot.hands,fixedSkills:const [ExFixedEquipmentSkill(id:'fixed',level:1)],randomMilestones:[5]);
  for(final roll in [0,1499,1500,5499,5500,9699,9700,9999]){
   for(var offset=0;offset<(roll>=9700?1:3);offset++){
    int draw(EquipmentInstance item,ExEquipmentSkillLayout? config){
     final rolls=[0,0,roll,if(roll<9700)offset].iterator;
     return master.draw(item,(bound){expect(rolls.moveNext(),true);expect(rolls.current,inInclusiveRange(0,bound-1));return rolls.current;},exLayout:config).level;
    }
    final minimum=roll<1500?1:roll<5500?4:roll<9700?7:10;
    expect(draw(ex,layout),minimum+offset);
    expect(draw(gr,null),minimum+offset);
   }
  }
  expect(()=>master.draw(ex,(_)=>0),throwsStateError);
  var call=0;
  expect(()=>master.draw(gr,(bound)=>call++==3?bound:0),throwsRangeError);
 });
}
