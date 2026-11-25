import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_summon.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _WorstDamageRandom implements Random {
 int calls=0;
 @override double nextDouble()=>calls++%2==0?0.9:0;
 @override int nextInt(int max)=>0;
 @override bool nextBool()=>false;
}

void main(){
 late AbyssMaster master;
 final base=WorldStats.fromRanks(level:1,fitness:1,intelligence:1,discipline:1,creativity:1);
 setUpAll((){
  WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync());
  final raw=jsonDecode(File(AbyssMaster.assetPath).readAsStringSync()) as Map<String,dynamic>;
  expect(raw['enabled'],false);
  master=AbyssMaster.fromJson(jsonEncode(raw..['enabled']=true));
 });
 test('序章マスターの部位別最大加算値と素手の基本性能を維持する',(){
  final caps=[[1,3,4],[5,6,12],[9,10,18],[14,20,28]];
  for(final rarity in EquipmentRarity.values.take(4)){
   for(var stat=0;stat<3;stat++){
    final inventory=AbyssInventory();
    int value(String id){
     final d=master.equipment.find(id)!;
     return [d.physical,d.magic,d.defense][stat];
    }
    for(final slot in EquipmentSlot.values){
     final ids=[for(final pool in [SummonPool.equipment,SummonPool.relic])for(final r in EquipmentRarity.values.take(rarity.index+1))for(final entry in master.summon.entries(pool,r))if(master.equipment.find(entry.masterId)!.slot==slot)entry.masterId];
     if(ids.isEmpty)continue;
     ids.sort((a,b)=>value(b).compareTo(value(a)));
     final d=master.equipment.find(ids.first)!;
     inventory.equip(inventory.addEquipment(d.id,d.slot,d.rarity).id);
    }
    expect(inventory.equipped.containsKey(EquipmentSlot.hands),false);
    final equipped=master.equipment.apply(base,inventory);
    expect([equipped.physical-base.physical,equipped.magic-base.magic,equipped.defense-base.defense][stat],caps[rarity.index][stat]);
    expect(equipped.hp,base.hp);
    expect(equipped.physicalMax,base.physicalMax);
    expect(equipped.magicMax,base.magicMax);
   }
  }
  expect(master.equipment.apply(base,AbyssInventory()).toJson(),base.toJson());
 });
 test('素手の最低乱数でも現行12戦を満タンから勝利できる',(){
  final engine=WorldEngine(random:_WorstDamageRandom());
  final world=WorldState();
  var now=1000000;
  for(final e in WorldCatalog.encounters){
   // 戦闘ごとの満タン条件。連戦の回復時間を保証する試験ではない。
   world.hp=base.hp;
   world.physical=base.physicalMax;
   world.magic=base.magicMax;
   world.energyAt=now;
   world.hpAt=now;
   engine.start(world,base,e.id,now);
   var turns=0;
   while(world.battle!=null&&turns<20){
    final battle=world.battle!;
    engine.act(world,WorldCommand.claw,battle.id,battle.turn,now);
    turns++;
   }
   expect(world.battle,isNull,reason:e.id);
   expect(world.cleared.contains(e.id),true,reason:e.id);
   expect(world.hp,greaterThan(0),reason:e.id);
   now+=1000;
  }
  expect(world.summonTickets,9);
  expect(world.supplyTickets,9);
  expect(world.gold,525);
 });
 test('フリー再戦でGは増えるが召喚券は増えない',(){
  final engine=WorldEngine(random:_WorstDamageRandom());
  final world=WorldState();
  const now=1000000;
  for(final id in ['p01_main','p01_hunt','p01_hunt']){
   world.hp=base.hp;
   world.physical=base.physicalMax;
   world.magic=base.magicMax;
   world.energyAt=now;
   world.hpAt=now;
   engine.start(world,base,id,now);
   for(var turn=0;world.battle!=null&&turn<20;turn++){
    final battle=world.battle!;
    engine.act(world,WorldCommand.claw,battle.id,battle.turn,now);
   }
   expect(world.battle,isNull);
   expect(world.hp,greaterThan(0));
  }
  expect(world.summonTickets,3);
  expect(world.supplyTickets,1);
  expect(world.gold,70);
  expect(SummonPolicy.costs[SummonPool.equipment],1);
  expect(SummonPolicy.costs[SummonPool.relic],5);
  expect(SummonPolicy.costs[SummonPool.supplies],1);
 });
}
