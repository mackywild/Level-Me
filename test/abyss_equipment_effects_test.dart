import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';

void main(){
 final rule=EquipmentEffectRule(effect:EquipmentEffect.physicalPercent,pool:EquipmentSkillPool.defense,levelValues:List.filled(10,2000));
 final policy=EquipmentEffectPolicy(rules:{'test':rule},caps:{EquipmentEffect.physicalPercent:5000});
 EquipmentInstance add(AbyssInventory inv,EquipmentSlot slot){
  final item=inv.addEquipment('test',slot,EquipmentRarity.ssr);
  for(var i=0;i<15;i++){inv.enhance(item.id,i);}
  return inv.equipment[item.id]!;
 }
 EquipmentSkillGrant grant(EquipmentInstance item,int milestone,{int level=1,String id='test'})=>
  EquipmentSkillGrant(instanceId:item.id,milestone:milestone,skillId:id,level:level);
 test('同一個体・複数装備の加算と効果別上限、未装着除外、snapshot不変',(){
  final inv=AbyssInventory();
  final head=add(inv,EquipmentSlot.head),body=add(inv,EquipmentSlot.body);
  inv.equip(head.id);
  final grants=[grant(head,5),grant(head,10),grant(body,5)];
  final first=policy.snapshot(inv,grants);
  expect(first.value(EquipmentEffect.physicalPercent),4000);
  inv.equip(body.id);
  final second=policy.snapshot(inv,grants);
  expect(second.value(EquipmentEffect.physicalPercent),5000);
  inv.unequip(EquipmentSlot.head);
  expect(policy.snapshot(inv,grants).value(EquipmentEffect.physicalPercent),2000);
  expect(first.value(EquipmentEffect.physicalPercent),4000);
  expect(second.value(EquipmentEffect.physicalPercent),5000);
  expect(()=>second.totals.clear(),throwsUnsupportedError);
 });
 test('枠重複・未到達・分類・未知ID・不正Lvを拒否',(){
  final inv=AbyssInventory();
  final head=add(inv,EquipmentSlot.head),ring=add(inv,EquipmentSlot.ring);
  inv.equip(head.id);
  for(final grants in [
   [grant(head,5),grant(head,5)],
   [grant(head,20)],[grant(head,5,level:0)],[grant(head,5,level:11)],
   [grant(ring,5)],[grant(head,5,id:'unknown')],
   [const EquipmentSkillGrant(instanceId:'missing',milestone:5,skillId:'test',level:1)],
  ]){expect(()=>policy.snapshot(inv,grants),throwsStateError);}
 });
 test('効果曲線と上限を検証し、追加攻撃の再帰発動を禁止',(){
  expect(()=>EquipmentEffectPolicy(rules:{'test':rule},caps:{}),throwsArgumentError);
  for(final effect in [EquipmentEffect.damageReduction,EquipmentEffect.energyDiscount,EquipmentEffect.cooldownReduction]){
   expect(()=>EquipmentEffectPolicy(rules:{},caps:{effect:10000}),throwsArgumentError);
  }
  expect(()=>EquipmentEffectPolicy(rules:{},caps:{EquipmentEffect.extraAttackChance:10001}),throwsArgumentError);
  expect(()=>EquipmentEffectRule(effect:EquipmentEffect.physicalPercent,pool:EquipmentSkillPool.attack,levelValues:[1]),throwsArgumentError);
  expect(EquipmentEffectPolicy.canTriggerExtraAttack(isExtraAttack:false),true);
  expect(EquipmentEffectPolicy.canTriggerExtraAttack(isExtraAttack:true),false);
 });
}
