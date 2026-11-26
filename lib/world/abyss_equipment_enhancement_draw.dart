import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'abyss_inventory.dart';
import 'abyss_equipment_skill_master.dart';
import 'abyss_equipment_skill_policy.dart';

/// 版1: seed・個体ID・到達段階・抽選用途・再試行番号を分離したSHA-256乱数。
/// 外部バックアップ巻戻しやマスター変更への耐性は別途管理する。
class EquipmentEnhancementDraw {
 const EquipmentEnhancementDraw._();
 static const _purposes=['rarity','candidate','levelBand','levelWithinBand'];

 static StoredEquipmentSkill? prepare(AbyssInventory inventory,EquipmentInstance item,EquipmentSkillMaster master){
  final seed=inventory.equipmentSkillSeed;
  if(seed==null)throw StateError('Equipment skill seed missing');
  final milestone=EquipmentSkillPolicy.nextGrant(item.rarity,item.enhancement,item.enhancement+1);
  if(milestone==null)return null;
  final serial=int.parse(item.id.substring(3));
  var purposeIndex=0;
  int nextInt(int bound){
   const range=0x100000000;
   if(bound<=0||bound>range)throw ArgumentError('Invalid equipment draw bound');
   if(purposeIndex>=_purposes.length)throw StateError('Unexpected equipment draw purpose');
   final purpose=_purposes[purposeIndex++];
   final limit=range-range%bound;
   for(var attempt=0;;attempt++){
    final input='equipment-skill-draw:v1:$seed:$serial:$milestone:$purpose:$attempt';
    final bytes=sha256.convert(utf8.encode(input)).bytes;
    // 32bit符号付きbit演算を避け、プラットフォーム共通のbig-endian値を得る。
    final value=((bytes[0]*256+bytes[1])*256+bytes[2])*256+bytes[3];
    if(value<limit)return value%bound;
   }
  }
  final result=master.draw(item,nextInt);
  return StoredEquipmentSkill(milestone:milestone,skillId:result.skill.id,level:result.level,ruleVersion:EquipmentSkillMaster.version);
 }
}
