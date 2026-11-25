import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _FixedRandom implements Random {
 @override double nextDouble()=>0.5;
 @override bool nextBool()=>false;
 @override int nextInt(int max)=>0;
}

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
 test('chrono unlocks and insufficient lifespan reject without mutation',(){
  engine.start(w,stats,'p01_main',now);
  expect(engine.unavailable(w,WorldCommand.accelerate),isNotNull);
  expect(engine.unavailable(w,WorldCommand.stopTime),isNotNull);
  w.cleared.addAll(['p06_main','p12_main']);
  expect(engine.unavailable(w,WorldCommand.accelerate),'寿命不足');
  expect(()=>act(WorldCommand.stopTime),throwsStateError);
  expect(w.lifespan,BigInt.zero);
  expect(w.battle!.turn,1);
 });
 test('time stop skips one enemy action and persists cooldown',(){
  w.cleared.add('p12_main');w.lifespan=BigInt.from(100);
  const durable=WorldStats(hp:10000,physical:1,magic:1,defense:1000,physicalMax:27,magicMax:38,crit:0);
  engine.start(w,durable,'p01_main',now);
  expect(WorldCatalog.byId('p01_main').timeResistant,false);
  final hp=w.hp;
  act(WorldCommand.stopTime);
  expect(w.hp,hp);expect(w.lifespan,BigInt.from(70));
  expect(w.battle!.stopCooldown,5);
  w=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  for(var i=5;i>0;i--){
   expect(w.battle!.stopCooldown,i);
   expect(engine.unavailable(w,WorldCommand.stopTime),isNotNull);
   act(WorldCommand.guard);
  }
  expect(w.battle!.stopCooldown,0);
  expect(engine.unavailable(w,WorldCommand.stopTime),isNull);
 });
 test('self acceleration doubles two claws, then returns to normal after reload',(){
  engine=WorldEngine(random:_FixedRandom());
  w.cleared.addAll(['p01_main','p06_main']);w.lifespan=BigInt.from(100);
  const durable=WorldStats(hp:10000,physical:11,magic:1,defense:1000,physicalMax:27,magicMax:38,crit:0);
  engine.start(w,durable,'p01_elite',now);
  act(WorldCommand.accelerate);
  expect(w.lifespan,BigInt.from(93));expect(w.battle!.acceleratedClaws,2);
  expect(engine.unavailable(w,WorldCommand.accelerate),isNotNull);
  w=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  act(WorldCommand.guard);expect(w.battle!.acceleratedClaws,2);
  for(final expected in [20,20,10]){
   final before=w.battle!.enemyHp;
   act(WorldCommand.claw);
   expect(w.battle,isNotNull);
   expect(before-w.battle!.enemyHp,expected);
   expect(w.battle!.acceleratedClaws,expected==10?0:(before==75?1:0));
  }
  expect(w.physical,15);
  expect(engine.unavailable(w,WorldCommand.accelerate),isNull);
 });
 test('time resistance blocks stop but consumes lifespan and starts cooldown',(){
  final raw=jsonDecode(File(WorldCatalog.assetPath).readAsStringSync()) as Map<String,dynamic>;
  final entries=raw['encounters'] as List;
  final enemy=entries.firstWhere((e)=>e['id']=='p01_main') as Map<String,dynamic>;
  enemy['timeResistant']=true;
  addTearDown(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
  WorldCatalog.loadJson(jsonEncode(raw));
  w.cleared.add('p12_main');w.lifespan=BigInt.from(100);
  engine.start(w,stats,'p01_main',now);
  final before=w.hp;
  act(WorldCommand.stopTime);
  expect(w.hp,lessThan(before));
  expect(w.lifespan,BigInt.from(70));
  expect(w.battle!.stopCooldown,5);
  expect(w.battle!.log,contains('時間停止は無効化された。'));
 });
 test('old active battle save defaults chrono state to zero',(){
  engine.start(w,stats,'p01_main',now);
  final raw=jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>;
  (raw['battle'] as Map)..remove('activeRuleSnapshots')..remove('encounterSnapshot')..remove('executionVersion')..remove('lifeRewardPercent')..remove('lifeRewardBonuses')..remove('acceleratedClaws')..remove('stopCooldown');
  final restored=WorldState.fromJson(raw);
  expect(restored.battle!.acceleratedClaws,0);
  expect(restored.battle!.stopCooldown,0);
 });
 group('composite claw',(){
  const durable=WorldStats(hp:10000,physical:11,magic:1,defense:1000,physicalMax:27,magicMax:38,crit:0);
  void startComposite({bool resistant=false}){
   if(resistant){
    final raw=jsonDecode(File(WorldCatalog.assetPath).readAsStringSync()) as Map<String,dynamic>;
    final enemy=(raw['encounters'] as List).firstWhere((e)=>e['id']=='p01_elite') as Map<String,dynamic>;
    enemy['timeResistant']=true;
    addTearDown(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
    WorldCatalog.loadJson(jsonEncode(raw));
   }
   engine=WorldEngine(random:_FixedRandom());
   w.cleared.add('p01_main');
   w.lifespan=BigInt.from(200);
   engine.start(w,durable,'p01_elite',now);
  }
  test('requires both unlocks and 90 days without mutating rejected state',(){
   startComposite();
   expect(engine.unavailable(w,WorldCommand.compositeClaw),isNotNull);
   w.cleared.add('p06_main');
   expect(engine.unavailable(w,WorldCommand.compositeClaw),isNotNull);
   w.cleared.add('p12_main');
   w.lifespan=BigInt.from(89);
   final before=jsonEncode(w.toJson());
   expect(engine.unavailable(w,WorldCommand.compositeClaw),'寿命不足');
   expect(()=>act(WorldCommand.compositeClaw),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
   w.lifespan=BigInt.from(90);
   expect(engine.unavailable(w,WorldCommand.compositeClaw),isNull);
   act(WorldCommand.compositeClaw);
   expect(w.lifespan,BigInt.zero);
  });
  test('400 percent damage, single turn, exact cost, shared cooldown survives reload',(){
   startComposite();
   w.cleared.addAll(['p06_main','p12_main']);
   final hp=w.hp,physical=w.physical,magic=w.magic;
   final id=w.battle!.id,turn=w.battle!.turn;
   act(WorldCommand.compositeClaw);
   expect(w.battle,isNotNull);
   expect(w.battle!.enemyHp,35);
   expect(w.hp,hp);
   expect(w.physical,physical);expect(w.magic,magic);
   expect(w.lifespan,BigInt.from(110));
   expect(w.battle!.turn,turn+1);
   expect(w.battle!.stopCooldown,5);
   expect(w.battle!.acceleratedClaws,0);
   final snapshot=jsonEncode(w.toJson());
   expect(()=>engine.act(w,WorldCommand.compositeClaw,id,turn,now),throwsStateError);
   expect(jsonEncode(w.toJson()),snapshot);
   w=WorldState.fromJson(jsonDecode(snapshot) as Map<String,dynamic>);
   for(var cd=5;cd>0;cd--){
    expect(w.battle!.stopCooldown,cd);
    expect(engine.unavailable(w,WorldCommand.stopTime),'クールダウン中');
    expect(engine.unavailable(w,WorldCommand.compositeClaw),'クールダウン中');
    act(WorldCommand.guard);
   }
   expect(w.battle!.stopCooldown,0);
   expect(engine.unavailable(w,WorldCommand.compositeClaw),isNull);
   act(WorldCommand.stopTime);
   expect(w.battle!.stopCooldown,5);
   w.lifespan=BigInt.from(100);
   expect(engine.unavailable(w,WorldCommand.compositeClaw),'クールダウン中');
  });
  test('resistance prevents stop but not damage or cost',(){
   startComposite(resistant:true);
   w.cleared.addAll(['p06_main','p12_main']);
   final hp=w.hp;
   act(WorldCommand.compositeClaw);
   expect(w.battle!.enemyHp,35);
   expect(w.hp,lessThan(hp));
   expect(w.lifespan,BigInt.from(110));
   expect(w.battle!.stopCooldown,5);
  });
  test('existing acceleration does not multiply composite damage or consume normal claw charges',(){
   startComposite();
   w.cleared.addAll(['p06_main','p12_main']);
   act(WorldCommand.accelerate);
   act(WorldCommand.compositeClaw);
   expect(w.battle!.enemyHp,35);
   expect(w.battle!.acceleratedClaws,2);
   expect(w.lifespan,BigInt.from(103));
  });
 });
}
