import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_buff.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Store extends LocalStore {
 _Store(Directory dir):super(directory:dir);
 bool fail=false;
 @override Future<void> save(AppStateData state) async {
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}
void main(){
 const now=1700000000000;
 const stats=WorldStats(hp:100,physical:1,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 const item=BuffItem(id:'item:discount_test',name:'試験省力薬',kind:BattleBuff.energyDiscount);
 final catalog=BuffCatalog(const [item]);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 WorldState state({bool active=true})=>WorldState(sequence:1,hpAt:now,energyAt:now,battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:10,rngState:1,buffs:active?{BattleBuff.energyDiscount:3}:{}));
 test('消費境界と紅爪の低威力経路を検証する',(){
  final engine=WorldEngine();
  for(final active in [false,true]){
   for(final command in [WorldCommand.claw,WorldCommand.heavyClaw,WorldCommand.magic]){
    final w=state(active:active);
    final cost=switch(command){WorldCommand.claw=>active?3:4,WorldCommand.heavyClaw=>active?7:9,_=>active?5:6};
    expect(engine.energyCost(w,command),cost);
    w.physical=cost-1;w.magic=cost-1;
    final before=jsonEncode(w.toJson());
    if(command==WorldCommand.claw){
     engine.act(w,command,1,1,now);
     expect(w.physical,cost-1);
    }else{
     expect(engine.unavailable(w,command),isNotNull);
     expect(()=>engine.act(w,command,1,1,now),throwsStateError);
     expect(jsonEncode(w.toJson()),before);
    }
    final exact=state(active:active);
    exact.physical=cost;exact.magic=cost;
    expect(engine.unavailable(exact,command),isNull);
    engine.act(exact,command,1,1,now);
    expect(command==WorldCommand.magic?exact.magic:exact.physical,0);
   }
  }
 });
 test('発動後3ターン、重複拒否、満了、寿命消費不変',(){
  final engine=WorldEngine();
  final s=AppStateData.initial();
  s.world.battle=state(active:false).battle;
  s.world.sequence=1;
  s.world.hpAt=now;s.world.energyAt=now;
  s.inventory.addStack(item.id,2);
  catalog.use(world:s.world,inventory:s.inventory,id:item.id,expectedSequence:0,battleId:1,turn:1,engine:engine,now:now);
  expect(s.world.battle!.buffs[BattleBuff.energyDiscount],3);
  final before=jsonEncode(s.toJson());
  expect(()=>catalog.use(world:s.world,inventory:s.inventory,id:item.id,expectedSequence:1,battleId:1,turn:2,engine:engine,now:now),throwsStateError);
  expect(jsonEncode(s.toJson()),before);
  s.world.cleared.addAll(['p03_main','p06_main','p12_main']);
  s.world.lifespan=BigInt.from(100);
  for(final command in [WorldCommand.slow,WorldCommand.accelerate,WorldCommand.stopTime]){
   engine.act(s.world,command,1,s.world.battle!.turn,now);
  }
  expect(s.world.lifespan,BigInt.from(60));
  expect(s.world.battle!.buffs.containsKey(BattleBuff.energyDiscount),false);
  expect(engine.energyCost(s.world,WorldCommand.claw),4);
  expect(s.inventory.stacks[item.id],1);
 });
 test('実ファイル保存失敗と再試行、再起動、未承認効果拒否',() async {
  final dir=await Directory.systemTemp.createTemp('energy-discount-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,buffCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.inventory.addStack(item.id,2);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.useBattleBuffItem(item.id,id,1,0,expectedGeneration:c.restoreGeneration),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.fail=false;
  await c.useBattleBuffItem(item.id,id,1,0,expectedGeneration:c.restoreGeneration);
  final restored=AppController(LocalStore(directory:dir),buffCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.buffs[BattleBuff.energyDiscount],3);
  expect(restored.state.inventory.stacks[item.id],1);
  final blocked=AppController(LocalStore(directory:dir),clockMs:()=>now);
  addTearDown(blocked.dispose);
  final committed=await primary.readAsString();
  await expectLater(blocked.initialize(),throwsFormatException);
  expect(await primary.readAsString(),committed);
 });
}
