import 'abyss_inventory.dart';

/// 承認済みの付与段階のみ。抽選・保存・強化実行とは独立する。
class EquipmentSkillPolicy {
 const EquipmentSkillPolicy._();
 static const maxEnhancement=20,minSkillLevel=1,maxSkillLevel=10;

 /// EXは個別仕様未確定のため、空枠扱いせず明示的に拒否する。
 static List<int> milestones(EquipmentRarity rarity)=>switch(rarity){
  EquipmentRarity.n=>const [],
  EquipmentRarity.r=>const [5],
  EquipmentRarity.sr=>const [5,10],
  EquipmentRarity.ssr=>const [5,10,15],
  EquipmentRarity.ur=>const [5,10,15,20],
  EquipmentRarity.lr=>const [4,8,12,16,20],
  EquipmentRarity.gr=>const [3,6,9,12,16,20],
  EquipmentRarity.ex=>throw UnsupportedError('EX equipment skill policy is undecided'),
 };
 static void _checkEnhancement(int level){
  if(level<0||level>maxEnhancement)throw RangeError.range(level,0,maxEnhancement,'enhancement');
 }
 static bool validSkillLevel(int level)=>level>=minSkillLevel&&level<=maxSkillLevel;
 static int slotCount(EquipmentRarity rarity)=>milestones(rarity).length;
 /// 指定強化値までに到達した付与段階。旧個体の結果を生成するAPIではない。
 static List<int> reachedMilestones(EquipmentRarity rarity,int enhancement){
  _checkEnhancement(enhancement);
  return List<int>.unmodifiable(milestones(rarity).where((level)=>level<=enhancement));
 }
 /// 1段階の強化に対し新規付与段階を返す。0からの開始を含む。
 /// 段階を飛ばす要求や+20からの強化を許容しない。
 static int? nextGrant(EquipmentRarity rarity,int current,int next){
  _checkEnhancement(current);
  _checkEnhancement(next);
  if(next!=current+1)throw StateError('Equipment enhancement must advance by one');
  return milestones(rarity).contains(next)?next:null;
 }
}
