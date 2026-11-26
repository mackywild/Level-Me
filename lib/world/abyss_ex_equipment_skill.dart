import 'abyss_inventory.dart';
import 'abyss_equipment_skill_policy.dart';
import 'abyss_equipment_skill_pool.dart';
import 'abyss_equipment_skill_odds.dart';

/// EX固有スキルは装備マスターに固定され、強化値に依存しない。
class ExFixedEquipmentSkill {
 const ExFixedEquipmentSkill({required this.id,required this.level});
 final String id;
 final int level;
}

/// EXの個別定義。実際の枠数・段階・Lv確率は本番マスター承認後に設定する。
/// ランダム枠の抽選確定・保存・戦闘適用は本クラスの責務外。
class ExEquipmentSkillLayout {
 ExEquipmentSkillLayout({
  required this.masterId,
  required this.slot,
  required Iterable<ExFixedEquipmentSkill> fixedSkills,
  required Iterable<int> randomMilestones,
 }):fixedSkills=List.unmodifiable(fixedSkills),
    randomMilestones=List.unmodifiable(randomMilestones){
  if(masterId.trim().isEmpty)throw ArgumentError.value(masterId,'masterId');
  if(this.fixedSkills.isEmpty||this.randomMilestones.isEmpty){
   throw ArgumentError('EX requires fixed skills and random slots');
  }
  final ids=<String>{};
  for(final skill in this.fixedSkills){
   if(skill.id.trim().isEmpty||!ids.add(skill.id)||!EquipmentSkillPolicy.validSkillLevel(skill.level)){
    throw ArgumentError('Invalid EX fixed skill');
   }
  }
  var previous=0;
  for(final milestone in this.randomMilestones){
   if(milestone<=previous||milestone>EquipmentSkillPolicy.maxEnhancement){
    throw ArgumentError('Invalid EX random milestone');
   }
   previous=milestone;
  }
 }
 final String masterId;
 final EquipmentSlot slot;
 final List<ExFixedEquipmentSkill> fixedSkills;
 final List<int> randomMilestones;

 EquipmentSkillPool get randomPool=>EquipmentSkillPoolOdds.poolForSlot(slot);

 void _requireInstance(EquipmentInstance item){
  if(item.rarity!=EquipmentRarity.ex||item.masterId!=masterId||item.slot!=slot){
   throw StateError('EX equipment layout mismatch');
  }
  if(item.enhancement<0||item.enhancement>EquipmentSkillPolicy.maxEnhancement){
   throw RangeError.range(item.enhancement,0,EquipmentSkillPolicy.maxEnhancement,'enhancement');
  }
 }

 /// 入手時(+0)から固有スキルが解放済み。装着・効果適用とは別。
 List<ExFixedEquipmentSkill> unlockedFixedSkills(EquipmentInstance item){
  _requireInstance(item);
  return fixedSkills;
 }

 /// 到達済みの段階のみ。付与済み結果を推測・再生成するAPIではない。
 List<int> reachedRandomMilestones(EquipmentInstance item){
  _requireInstance(item);
  return List.unmodifiable(randomMilestones.where((level)=>level<=item.enhancement));
 }

 int? nextRandomGrant(EquipmentInstance item,int nextEnhancement){
  _requireInstance(item);
  if(nextEnhancement<0||nextEnhancement>EquipmentSkillPolicy.maxEnhancement){
   throw RangeError.range(nextEnhancement,0,EquipmentSkillPolicy.maxEnhancement,'enhancement');
  }
  if(nextEnhancement!=item.enhancement+1)throw StateError('Equipment enhancement must advance by one');
  return randomMilestones.contains(nextEnhancement)?nextEnhancement:null;
 }
}

/// 既存の部位別・希少度別抽選から隔離された魔遺物専用候補を扱う。
/// 固有スキルはランダム候補として登録しない（呼び出し側のマスター責務）。
class RelicEquipmentSkillPool {
 RelicEquipmentSkillPool(Iterable<EquipmentSkillCandidate> candidates)
  :_odds=EquipmentSkillPoolOdds(_validate(candidates));
 final EquipmentSkillPoolOdds _odds;

 static List<EquipmentSkillCandidate> _validate(Iterable<EquipmentSkillCandidate> candidates){
  final entries=List<EquipmentSkillCandidate>.of(candidates);
  if(entries.any((skill)=>skill.pool!=EquipmentSkillPool.relic)){
   throw ArgumentError('Relic pool accepts relic skills only');
  }
  return entries;
 }

 /// EXのLv抽選は未承認なので種類だけを選択できる。
 EquipmentSkillCandidate drawType(int Function(int) nextInt)=>
  _odds.draw(EquipmentSkillPool.relic,nextInt);

 ({EquipmentSkillCandidate skill,EquipmentSkillLevelBand band}) drawWithLevelBand(
  EquipmentRarity rarity,int Function(int) nextInt)=>
  _odds.drawWithLevelBand(EquipmentSlot.relic,rarity,nextInt);
}
