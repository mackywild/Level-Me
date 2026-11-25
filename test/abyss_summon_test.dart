import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_summon.dart';

void main(){
 const policy=SummonPolicy();
 test('all 10000 rolls match the design distribution exactly',(){
  final counts=List<int>.filled(8,0);
  for(var roll=0;roll<10000;roll++){
   final result=policy.draw(highestUnlocked:EquipmentRarity.ex,roll:roll,misses:{});
   counts[result.rarity.index]++;
  }
  expect(counts,[4500,3000,1800,500,150,40,9,1]);
 });
 test('locked probabilities transfer to highest unlocked rarity',(){
  expect(policy.effectiveWeights(EquipmentRarity.r),[4500,5500,0,0,0,0,0,0]);
  expect(policy.effectiveWeights(EquipmentRarity.sr),[4500,3000,2500,0,0,0,0,0]);
  for(final tier in EquipmentRarity.values){
   final weights=policy.effectiveWeights(tier);
   expect(weights.reduce((a,b)=>a+b),10000);
   expect(weights.skip(tier.index+1).every((v)=>v==0),true);
   expect(policy.draw(highestUnlocked:tier,roll:9999,misses:{}).rarity,tier);
  }
 });
 test('pity triggers at exact limit and higher rarity resets lower counters',(){
  for(final entry in SummonPolicy.pityLimits.entries){
   final before=policy.draw(highestUnlocked:entry.key,roll:0,misses:{entry.key:entry.value-2});
   expect(before.rarity,EquipmentRarity.n);
   expect(before.misses[entry.key],entry.value-1);
   final due=policy.draw(highestUnlocked:entry.key,roll:0,misses:before.misses);
   expect(due.rarity,entry.key);
   expect(due.misses[entry.key],0);
  }
  final outcome=policy.draw(highestUnlocked:EquipmentRarity.ur,roll:0,misses:{EquipmentRarity.ssr:49,EquipmentRarity.ur:149},guaranteeSr:true);
  expect(outcome.rarity,EquipmentRarity.ur);
  expect(outcome.misses[EquipmentRarity.ssr],0);
  expect(outcome.misses[EquipmentRarity.ur],0);
 });
 test('locked pity stays unchanged and guarantee never bypasses unlock',(){
  final outcome=policy.draw(highestUnlocked:EquipmentRarity.r,roll:0,misses:{EquipmentRarity.ssr:49},guaranteeSr:true);
  expect(outcome.rarity,EquipmentRarity.n);
  expect(outcome.misses[EquipmentRarity.ssr],49);
  expect(policy.draw(highestUnlocked:EquipmentRarity.sr,roll:0,misses:{},guaranteeSr:true).rarity,EquipmentRarity.sr);
  expect(policy.draw(highestUnlocked:EquipmentRarity.ex,roll:9999,misses:{},guaranteeSr:true).rarity,EquipmentRarity.ex);
 });
 test('invalid inputs reject and caller counters remain immutable',(){
  final counters={EquipmentRarity.ssr:48};
  final outcome=policy.draw(highestUnlocked:EquipmentRarity.ssr,roll:0,misses:counters);
  expect(counters[EquipmentRarity.ssr],48);
  expect(outcome.misses[EquipmentRarity.ssr],49);
  expect(()=>outcome.misses.clear(),throwsUnsupportedError);
  for(final roll in [-1,10000]){
   expect(()=>policy.draw(highestUnlocked:EquipmentRarity.ex,roll:roll,misses:{}),throwsRangeError);
  }
  for(final value in [-1,50]){
   expect(()=>policy.draw(highestUnlocked:EquipmentRarity.ex,roll:0,misses:{EquipmentRarity.ssr:value}),throwsArgumentError);
  }
  expect(()=>policy.draw(highestUnlocked:EquipmentRarity.ex,roll:0,misses:{EquipmentRarity.n:1}),throwsArgumentError);
 });
 test('draft costs are one equipment, five relic, one supply ticket',(){
  expect(SummonPolicy.costs[SummonPool.equipment],1);
  expect(SummonPolicy.costs[SummonPool.relic],5);
  expect(SummonPolicy.costs[SummonPool.supplies],1);
 });
}
