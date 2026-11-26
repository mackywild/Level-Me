import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_equipment_skill_odds.dart';
import 'package:level_me/world/abyss_inventory.dart';

void main(){
 const common=EquipmentSkillCandidate(id:'c',pool:EquipmentSkillPool.attack,rarity:EquipmentSkillRarity.common);
 const rare=EquipmentSkillCandidate(id:'r',pool:EquipmentSkillPool.attack,rarity:EquipmentSkillRarity.rare);
 const ultra=EquipmentSkillCandidate(id:'u',pool:EquipmentSkillPool.attack,rarity:EquipmentSkillRarity.ultraRare);
 const ultra2=EquipmentSkillCandidate(id:'u2',pool:EquipmentSkillPool.attack,rarity:EquipmentSkillRarity.ultraRare);
 const defense=EquipmentSkillCandidate(id:'d',pool:EquipmentSkillPool.defense,rarity:EquipmentSkillRarity.common);
 const attack=EquipmentSkillPool.attack;
 final odds=EquipmentSkillPoolOdds([common,rare,ultra,ultra2,defense]);

 test('全100乱数で70/25/5、同一希少度内は均等',(){
  expect(EquipmentSkillPoolOdds.version,1);
  final counts=<EquipmentSkillRarity,int>{};
  for(var i=0;i<100;i++){
   final rolls=[i,0].iterator;
   final skill=odds.draw(attack,(bound){expect(rolls.moveNext(),isTrue);return rolls.current;});
   counts.update(skill.rarity,(n)=>n+1,ifAbsent:()=>1);
  }
  expect(counts,EquipmentSkillPoolOdds.weights);
  for(var i=0;i<2;i++){
   final rolls=[95,i].iterator;
   expect(odds.draw(attack,(bound){rolls.moveNext();return rolls.current;}).id,['u','u2'][i]);
  }
 });
 test('全7種類の非空プールで整数重みを再正規化',(){
  const candidates=[common,rare,ultra];
  const expected=[70,25,5];
  for(var mask=1;mask<8;mask++){
   final subset=[for(var i=0;i<3;i++)if((mask&(1<<i))!=0)candidates[i]];
   final pool=EquipmentSkillPoolOdds(subset);
   final total=pool.totalWeight(attack);
   final counts=<String,int>{};
   for(var roll=0;roll<total;roll++){
    var call=0;
    final result=pool.draw(attack,(bound)=>call++==0?roll:0);
    counts.update(result.id,(n)=>n+1,ifAbsent:()=>1);
   }
   expect(counts,{for(var i=0;i<3;i++)if((mask&(1<<i))!=0)candidates[i].id:expected[i]});
   expect(total,counts.values.reduce((a,b)=>a+b));
  }
 });
 test('全装備枠の分類と分類外除外',(){
  expect(EquipmentSlot.values.map(EquipmentSkillPoolOdds.poolForSlot).toList(),[
   attack,EquipmentSkillPool.defense,EquipmentSkillPool.defense,EquipmentSkillPool.defense,
   EquipmentSkillPool.defense,EquipmentSkillPool.special,EquipmentSkillPool.special,EquipmentSkillPool.relic,
  ]);
  expect(odds.draw(EquipmentSkillPool.defense,(_)=>0).id,'d');
  expect(()=>odds.draw(EquipmentSkillPool.special,(_)=>throw StateError('must not draw')),throwsStateError);
 });
 test('R〜GRで超希少とLv帯は独立、同じIDを繰り返し取得可能',(){
  for(final rarity in EquipmentRarity.values.where((r)=>r!=EquipmentRarity.n&&r!=EquipmentRarity.ex)){
   for(final levelRoll in [0,9999]){
    for(final typeRoll in [0,95]){
     for(var repeat=0;repeat<2;repeat++){
      final rolls=[typeRoll,0,levelRoll].iterator;
      final bounds=<int>[];
      final result=odds.drawWithLevelBand(EquipmentSlot.hands,rarity,(bound){
       bounds.add(bound);expect(rolls.moveNext(),isTrue);return rolls.current;
      });
      expect(result.skill.id,typeRoll==0?'c':'u');
      expect(result.band,levelRoll==0?EquipmentSkillLevelBand.low:EquipmentSkillLevelBand.maxLevel);
      expect(bounds,[100,typeRoll==0?1:2,10000]);
     }
    }
   }
  }
 });
 test('不正ID・重複定義・不正乱数・N/EX拒否',(){
  expect(()=>EquipmentSkillPoolOdds([common,common]),throwsArgumentError);
  expect(()=>EquipmentSkillPoolOdds([const EquipmentSkillCandidate(id:' ',pool:attack,rarity:EquipmentSkillRarity.common)]),throwsArgumentError);
  expect(()=>odds.draw(attack,(_)=>-1),throwsRangeError);
  expect(()=>odds.draw(attack,(bound)=>bound),throwsRangeError);
  var calls=0;
  expect(()=>odds.draw(attack,(bound)=>calls++==0?0:bound),throwsRangeError);
  for(final rarity in [EquipmentRarity.n,EquipmentRarity.ex]){
   expect(()=>odds.drawWithLevelBand(EquipmentSlot.hands,rarity,(_)=>throw StateError('must not draw')),throwsUnsupportedError);
  }
  expect(()=>odds.candidatesFor(attack,EquipmentSkillRarity.common).clear(),throwsUnsupportedError);
  expect(()=>EquipmentSkillPoolOdds.weights[EquipmentSkillRarity.common]=1,throwsUnsupportedError);
 });
}
