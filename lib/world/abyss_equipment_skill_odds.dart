import 'abyss_inventory.dart';

/// 確定済みのLv帯。帯内の個別Lv確率は別途決定する。
enum EquipmentSkillLevelBand {
 low(1,3), middle(4,6), high(7,9), maxLevel(10,10);
 const EquipmentSkillLevelBand(this.minimum,this.maximum);
 final int minimum,maximum;
}

/// DEC-008の確率規則v1。乱数取得・付与確定・保存は呼び出し側の責務。
class EquipmentSkillOdds {
 const EquipmentSkillOdds._();
 static const version=1,rollCount=10000;

 /// 順番はLv1〜3、4〜6、7〜9、10。単位は0.01%。
 static List<int> weights(EquipmentRarity rarity)=>switch(rarity){
  EquipmentRarity.n=>throw UnsupportedError('N equipment has no skill slots'),
  EquipmentRarity.r=>const [6500,2900,590,10],
  EquipmentRarity.sr=>const [5500,3500,970,30],
  EquipmentRarity.ssr=>const [4500,4000,1440,60],
  EquipmentRarity.ur=>const [3500,4300,2100,100],
  EquipmentRarity.lr=>const [2500,4500,2800,200],
  EquipmentRarity.gr=>const [1500,4000,4200,300],
  EquipmentRarity.ex=>throw UnsupportedError('EX equipment skill odds are undecided'),
 };

 /// 0〜9999の一様な整数を受け取り、承認済みLv帯へ写像する。
 static EquipmentSkillLevelBand bandForRoll(EquipmentRarity rarity,int roll){
  if(roll<0||roll>=rollCount)throw RangeError.range(roll,0,rollCount-1,'roll');
  final probabilities=weights(rarity);
  var remaining=roll;
  for(var i=0;i<probabilities.length;i++){
   if(remaining<probabilities[i])return EquipmentSkillLevelBand.values[i];
   remaining-=probabilities[i];
  }
  throw StateError('Invalid equipment skill odds');
 }
}
