import 'abyss_inventory.dart';
import 'abyss_equipment_skill_master.dart';
import 'abyss_equipment_skill_policy.dart';

/// 版1: 永続seed、個体serial、到達段階から固定の乱数列を得る。
/// 外部バックアップ巻戻しやマスター変更への耐性は別途管理する。
class EquipmentEnhancementDraw {
 const EquipmentEnhancementDraw._();
 static StoredEquipmentSkill? prepare(AbyssInventory inventory,EquipmentInstance item,EquipmentSkillMaster master){
  final seed=inventory.equipmentSkillSeed;
  if(seed==null)throw StateError('Equipment skill seed missing');
  final milestone=EquipmentSkillPolicy.nextGrant(item.rarity,item.enhancement,item.enhancement+1);
  if(milestone==null)return null;
  final serial=int.parse(item.id.substring(3));
  // BigIntの固定幅演算でプラットフォーム差と整数overflowを避ける。
  final mask=BigInt.from(0xffffffff);
  var state=(BigInt.from(seed)^((BigInt.from(serial)*BigInt.from(0x9e3779b9))&mask)^BigInt.from(milestone))&mask;
  int nextInt(int bound){
   if(bound<=0||bound>0x100000000)throw ArgumentError('Invalid equipment draw bound');
   final range=BigInt.one<<32;
   final limit=range-range%BigInt.from(bound);
   while(true){
    state=(state*BigInt.from(1664525)+BigInt.from(1013904223))&mask;
    if(state<limit)return (state%BigInt.from(bound)).toInt();
   }
  }
  final result=master.draw(item,nextInt);
  return StoredEquipmentSkill(milestone:milestone,skillId:result.skill.id,level:result.level,ruleVersion:EquipmentSkillMaster.version);
 }
}
