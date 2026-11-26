import 'abyss_inventory.dart';
import 'abyss_equipment_skill_odds.dart';

enum EquipmentSkillRarity { common, rare, ultraRare }
enum EquipmentSkillPool { attack, defense, special, relic }

/// 抽選対象の定義。本番ID・効果値は別途承認する。
class EquipmentSkillCandidate {
 const EquipmentSkillCandidate({required this.id,required this.pool,required this.rarity});
 final String id;
 final EquipmentSkillPool pool;
 final EquipmentSkillRarity rarity;
}

/// DEC-009: 整数重みで希少度を抽選し、その中から均等に選択する。
/// 候補は消費しない。保存・強化トランザクションとは独立。
class EquipmentSkillPoolOdds {
 EquipmentSkillPoolOdds(Iterable<EquipmentSkillCandidate> candidates){
  final ids=<String>{};
  for(final candidate in candidates){
   if(candidate.id.trim().isEmpty||!ids.add(candidate.id)){
    throw ArgumentError.value(candidate.id,'id','Empty or duplicate skill ID');
   }
   (_pools[candidate.pool]??=<EquipmentSkillCandidate>[]).add(candidate);
  }
 }
 static const version=1;
 static const weights=<EquipmentSkillRarity,int>{
  EquipmentSkillRarity.common:70,
  EquipmentSkillRarity.rare:25,
  EquipmentSkillRarity.ultraRare:5,
 };
 final Map<EquipmentSkillPool,List<EquipmentSkillCandidate>> _pools={};

 static EquipmentSkillPool poolForSlot(EquipmentSlot slot)=>switch(slot){
  EquipmentSlot.hands=>EquipmentSkillPool.attack,
  EquipmentSlot.head||EquipmentSlot.body||EquipmentSlot.arms||EquipmentSlot.legs=>EquipmentSkillPool.defense,
  EquipmentSlot.ring||EquipmentSlot.necklace=>EquipmentSkillPool.special,
  EquipmentSlot.relic=>EquipmentSkillPool.relic,
 };

 List<EquipmentSkillCandidate> candidatesFor(EquipmentSkillPool pool,EquipmentSkillRarity rarity)=>
  List.unmodifiable((_pools[pool]??const <EquipmentSkillCandidate>[]).where((candidate)=>candidate.rarity==rarity));

 int totalWeight(EquipmentSkillPool pool)=>EquipmentSkillRarity.values.fold<int>(0,(sum,rarity)=>
  sum+(candidatesFor(pool,rarity).isEmpty?0:weights[rarity]!));

 static int _checkedRoll(int Function(int) nextInt,int bound){
  if(bound<=0)throw StateError('No eligible equipment skills');
  final roll=nextInt(bound);
  if(roll<0||roll>=bound)throw RangeError.range(roll,0,bound-1,'roll');
  return roll;
 }

 EquipmentSkillCandidate draw(EquipmentSkillPool pool,int Function(int) nextInt){
  var roll=_checkedRoll(nextInt,totalWeight(pool));
  for(final rarity in EquipmentSkillRarity.values){
   final candidates=candidatesFor(pool,rarity);
   if(candidates.isEmpty)continue;
   final weight=weights[rarity]!;
   if(roll<weight)return candidates[_checkedRoll(nextInt,candidates.length)];
   roll-=weight;
  }
  throw StateError('Invalid equipment skill pool weights');
 }

 /// 別々の一様乱数を要求する。N/EXは既存Lv帯規則に従い拒否。
 /// Lv10以外は帯のみ返す（帯内の個別Lv確定・保存は後続）。
 ({EquipmentSkillCandidate skill,EquipmentSkillLevelBand band}) drawWithLevelBand(
  EquipmentSlot slot,EquipmentRarity rarity,int Function(int) nextInt){
  EquipmentSkillOdds.weights(rarity);
  final skill=draw(poolForSlot(slot),nextInt);
  final band=EquipmentSkillOdds.bandForRoll(rarity,_checkedRoll(nextInt,EquipmentSkillOdds.rollCount));
  return (skill:skill,band:band);
 }
}
