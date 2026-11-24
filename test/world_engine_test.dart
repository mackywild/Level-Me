import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final stats=WorldStats.fromRanks(level:1,fitness:1,intelligence:1,discipline:1,creativity:1);
 const now=10000000;
 late WorldEngine engine;
 late WorldState w;
 setUp((){engine=WorldEngine(random:Random(42));w=WorldState();});
 void act(WorldCommand c){final b=w.battle!;engine.act(w,c,b.id,b.turn,now);}
 void clear(String id){engine.start(w,stats,id,now);for(var i=0;i<20&&w.battle!=null;i++){act(WorldCommand.claw);}expect(w.cleared,contains(id));}
 test('catalog has three main and nine free encounters',(){
  expect(WorldCatalog.encounters.where((e)=>e.main).length,3);
  expect(WorldCatalog.encounters.where((e)=>!e.main).length,9);
  expect(WorldCatalog.encounters.map((e)=>e.id).toSet().length,12);
 });
 test('main progression, first rewards and repeatable free quests',(){
  expect(()=>engine.start(w,stats,'p02_main',now),throwsStateError);
  expect(()=>engine.start(w,stats,'p01_hunt',now),throwsStateError);
  clear('p01_main');clear('p02_main');clear('p03_main');
  expect(w.summonTickets,9);expect(w.lifespan,BigInt.from(365));
  expect(()=>engine.start(w,stats,'p03_main',now),throwsStateError);
  clear('p03_hunt');clear('p03_hunt');
  expect(w.supplyTickets,1);expect(w.lifespan,BigInt.from(425));
 });
 test('save and resume active battle; stale command rejected',(){
  clear('p01_main');
  engine.start(w,stats,'p01_elite',now);
  final b=w.battle!;
  act(WorldCommand.guard);
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  expect(restored.battle!.turn,2);expect(restored.hp,w.hp);
  expect(()=>engine.act(restored,WorldCommand.claw,b.id,1,now),throwsStateError);
  engine.act(restored,WorldCommand.retreat,b.id,2,now);
  expect(restored.battle,isNull);expect(restored.supplyTickets,0);
 });
 test('lifespan survives large integer JSON roundtrip',(){
  w.lifespan=BigInt.parse('9999999999999999999999999999999999999');
  expect(WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>).lifespan,w.lifespan);
 });
 test('natural recovery outside battle only and capped',(){
  engine.refresh(w,stats,now);w.physical=0;w.magic=0;w.hp=50;
  engine.refresh(w,stats,now+1800000);
  expect(w.physical,3);expect(w.magic,3);expect(w.hp,55);
  engine.refresh(w,stats,now+100000000);
  expect(w.hp,stats.hp);expect(w.physical,stats.physicalMax);expect(w.magic,stats.magicMax);
 });
 test('low energy fallback permits claw and no negative resources',(){
  engine.refresh(w,stats,now);w.physical=0;w.magic=0;
  engine.start(w,stats,'p01_main',now);
  expect(engine.unavailable(w,WorldCommand.heavyClaw),isNotNull);
  act(WorldCommand.claw);
  expect(w.physical,0);expect(w.magic,0);
 });
 test('time slow requires unlock and spends lifespan only once per cast',(){
  clear('p01_main');clear('p02_main');clear('p03_main');
  engine.start(w,stats,'p03_elite',now);
  final before=w.lifespan;act(WorldCommand.slow);
  expect(w.lifespan,before-BigInt.from(3));expect(w.battle!.slowTurns,1);
  expect(engine.unavailable(w,WorldCommand.slow),isNotNull);
  act(WorldCommand.guard);expect(w.battle!.slowTurns,0);
 });
 test('daily recovery during active battle is deferred',(){
  clear('p01_main');
  engine.start(w,stats,'p01_elite',now);
  final before=w.physical;
  engine.rewardEffort(w,stats,now,physical:15,magic:0,levelUp:false);
  expect(w.physical,before);expect(w.pendingPhysical,15);
  act(WorldCommand.retreat);engine.refresh(w,stats,now);
  expect(w.physical,stats.physicalMax);expect(w.pendingPhysical,0);
 });
 test('legacy save migrates without modifying daily data',(){
  final legacy=AppStateData.initial()..totalExp=500;
  final raw=legacy.toJson()..remove('world');
  final state=AppStateData.fromJson(raw);
  expect(state.totalExp,500);expect(state.quests.length,legacy.quests.length);
  expect(state.world.cleared,isEmpty);
 });
 test('damage formula obeys defense and minimum damage',(){
  expect(engine.damage(40,0,1),40);
  expect(engine.damage(40,100,1),20);
  expect(engine.damage(1,1000,0.25),1);
 });
 test('battle preserves nine minutes of natural recovery including after reload',(){
  clear('p01_main');
  w.physical=0;w.hp=50;
  engine.start(w,stats,'p01_elite',now+540000);
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  final b=restored.battle!;
  engine.act(restored,WorldCommand.retreat,b.id,b.turn,now+900000);
  engine.refresh(restored,stats,now+959999);
  expect(restored.physical,0);
  engine.refresh(restored,stats,now+960000);
  expect(restored.physical,1);
  engine.refresh(restored,stats,now+2160000);
  expect(restored.hp,55);
 });
 test('stage identifiers support double-digit progression',(){
  expect(WorldCatalog.mainId(9),'p09_main');
  expect(WorldCatalog.mainId(10),'p10_main');
  final e=WorldEncounter('p10_main',10,'test','enemy',10,1,0,0,main:true);
  expect(engine.isUnlocked(w,e),false);
  w.cleared.add('p09_main');
  expect(engine.isUnlocked(w,e),true);
 });
 test('master validation rejects duplicate IDs without replacing loaded catalog',(){
  final raw=jsonDecode(File(WorldCatalog.assetPath).readAsStringSync()) as Map<String,dynamic>;
  final entries=raw['encounters'] as List;
  entries.add(entries.first);
  expect(()=>WorldCatalog.loadJson(jsonEncode(raw)),throwsFormatException);
  expect(WorldCatalog.encounters.length,12);
 });
}
