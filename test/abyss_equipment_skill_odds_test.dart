import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_equipment_skill_odds.dart';
import 'package:level_me/world/abyss_inventory.dart';

void main(){
 const expected=<EquipmentRarity,List<int>>{
  EquipmentRarity.r:[6500,2900,590,10],
  EquipmentRarity.sr:[5500,3500,970,30],
  EquipmentRarity.ssr:[4500,4000,1440,60],
  EquipmentRarity.ur:[3500,4300,2100,100],
  EquipmentRarity.lr:[2500,4500,2800,200],
  EquipmentRarity.gr:[1500,4000,4200,300],
 };
 test('承認済み確率と全6万抽選値の頻度が厳密に一致する',(){
  expect(EquipmentSkillOdds.version,1);
  expect(EquipmentSkillOdds.rollCount,10000);
  expect(expected.keys.toSet(),EquipmentRarity.values.where((r)=>r!=EquipmentRarity.n&&r!=EquipmentRarity.ex).toSet());
  for(final entry in expected.entries){
   expect(EquipmentSkillOdds.weights(entry.key),entry.value);
   expect(entry.value.fold<int>(0,(a,b)=>a+b),10000);
   final counts=List<int>.filled(4,0);
   for(var roll=0;roll<10000;roll++){
    counts[EquipmentSkillOdds.bandForRoll(entry.key,roll).index]++;
   }
   expect(counts,entry.value);
  }
 });
 test('全希少度で各帯の開始・終了境界が一致する',(){
  for(final entry in expected.entries){
   var start=0;
   for(var band=0;band<4;band++){
    final end=start+entry.value[band]-1;
    expect(EquipmentSkillOdds.bandForRoll(entry.key,start),EquipmentSkillLevelBand.values[band]);
    expect(EquipmentSkillOdds.bandForRoll(entry.key,end),EquipmentSkillLevelBand.values[band]);
    start=end+1;
   }
   expect(start,10000);
  }
 });
 test('Lv帯は1〜10を重複・欠落なく分割する',(){
  final actual=<int>[];
  for(final band in EquipmentSkillLevelBand.values){
   for(var level=band.minimum;level<=band.maximum;level++){actual.add(level);}
  }
  expect(actual,List<int>.generate(10,(i)=>i+1));
  expect(EquipmentSkillLevelBand.maxLevel.minimum,10);
  expect(EquipmentSkillLevelBand.maxLevel.maximum,10);
 });
 test('高希少度ほど上位帯の累積確率が高く、全希少度でLv10が可能',(){
  List<int>? previous;
  for(final entry in expected.entries){
   final weights=EquipmentSkillOdds.weights(entry.key);
   expect(weights.last,greaterThan(0));
   final tails=List<int>.generate(3,(i)=>weights.skip(i+1).fold<int>(0,(a,b)=>a+b));
   final before=previous;
   if(before!=null){
    for(var i=0;i<tails.length;i++){expect(tails[i],greaterThan(before[i]));}
   }
   previous=tails;
  }
 });
 test('確率表は外部変更不可、不正な乱数値は拒否',(){
  for(final rarity in expected.keys){
   expect(()=>EquipmentSkillOdds.weights(rarity)[0]=1,throwsUnsupportedError);
   for(final invalid in [-1,10000,0x7fffffffffffffff]){
    expect(()=>EquipmentSkillOdds.bandForRoll(rarity,invalid),throwsRangeError);
   }
  }
 });
 test('Nの付与なしとEX未決を区別し、どちらも抽選不可',(){
  for(final rarity in [EquipmentRarity.n,EquipmentRarity.ex]){
   expect(()=>EquipmentSkillOdds.weights(rarity),throwsUnsupportedError);
   expect(()=>EquipmentSkillOdds.bandForRoll(rarity,0),throwsUnsupportedError);
   expect(()=>EquipmentSkillOdds.bandForRoll(rarity,9999),throwsUnsupportedError);
  }
 });
}
