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
 String? attempted;
 @override Future<void> save(AppStateData state) async {
  attempted=jsonEncode(state.toJson());
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}
void main(){
 const now=1700000000000;
 final raw=File(WorldCatalog.assetPath).readAsStringSync();
 const stats=WorldStats(hp:100,physical:1,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 const item=BuffItem(id:'item:suppress_test',name:'試験再生封じ薬',kind:BattleBuff.regenerationSuppression);
 final catalog=BuffCatalog(const [item]);
 void load(Object? percent,{bool resistant=false}){
  final root=jsonDecode(raw) as Map<String,dynamic>;
  final row=(root['encounters'] as List).first as Map<String,dynamic>;
  row['hp']=100;
  row['regenerationPercent']=percent;
  row['timeResistant']=resistant;
  WorldCatalog.loadJson(jsonEncode(root));
 }
 setUp(()=>WorldCatalog.loadJson(raw));
 tearDown(()=>WorldCatalog.loadJson(raw));
 WorldState state({int hp=50,Map<BattleBuff,int>? buffs})=>WorldState(sequence:1,hpAt:now,energyAt:now,battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:hp,rngState:1,buffs:buffs));
 test('既存マスターは全敵再生なし、不正値拒否',(){
  expect(WorldCatalog.encounters.every((e)=>e.regenerationPercent==0),true);
  for(final bad in [null,-1,101,2.0,'2']){
   expect(()=>load(bad),throwsFormatException);
   expect(WorldCatalog.encounters.every((e)=>e.regenerationPercent==0),true);
  }
 });
 test('敵再生と抑制は最大HP基準、端数切り捨て、上限保護',(){
  load(11);
  final engine=WorldEngine();
  for(final suppressed in [false,true]){
   final w=state(buffs:suppressed?{BattleBuff.regenerationSuppression:1}:null);
   engine.act(w,WorldCommand.guard,1,1,now);
   expect(w.battle!.enemyHp,suppressed?55:61);
   expect(w.battle!.buffs,isEmpty);
   expect(w.battle!.rngState,1);
  }
  final almost=state(hp:98);
  engine.act(almost,WorldCommand.guard,1,1,now);
  expect(almost.battle!.enemyHp,100);
  load(1);
  final small=state(buffs:{BattleBuff.regenerationSuppression:1});
  engine.act(small,WorldCommand.guard,1,1,now);
  expect(small.battle!.enemyHp,50);
 });
 test('再生なしへの消費拒否と発動時・満了までの抑制',(){
  final s=AppStateData.initial();
  final engine=WorldEngine();
  engine.start(s.world,stats,'p01_main',now);
  s.inventory.addStack(item.id,2);
  void use()=>catalog.use(world:s.world,inventory:s.inventory,id:item.id,expectedSequence:s.world.itemUseSequence,battleId:1,turn:s.world.battle!.turn,engine:engine,now:now);
  final before=jsonEncode(s.toJson());
  expect(use,throwsStateError);
  expect(jsonEncode(s.toJson()),before);
  load(10);
  s.world.battle=state().battle;
  use();
  expect(s.world.battle!.enemyHp,55);
  expect(s.world.battle!.buffs[BattleBuff.regenerationSuppression],3);
  expect(use,throwsStateError);
  for(var i=0;i<3;i++){
   engine.act(s.world,WorldCommand.guard,1,s.world.battle!.turn,now);
  }
  expect(s.world.battle!.enemyHp,70);
  expect(s.world.battle!.buffs,isEmpty);
  engine.act(s.world,WorldCommand.guard,1,s.world.battle!.turn,now);
  expect(s.world.battle!.enemyHp,80);
  expect(s.inventory.stacks[item.id],1);
 });
 test('時間停止成功時は再生なし、耐性時は再生する',(){
  for(final resistant in [false,true]){
   load(10,resistant:resistant);
   final w=state(buffs:{BattleBuff.regenerationSuppression:1});
   w.cleared.add('p12_main');w.lifespan=BigInt.from(30);
   WorldEngine().act(w,WorldCommand.stopTime,1,1,now);
   expect(w.battle!.enemyHp,resistant?55:50);
   expect(w.battle!.buffs,isEmpty);
   expect(w.lifespan,BigInt.zero);
  }
 });
 test('敵撃破時とプレイヤー敗北時は敵再生しない',(){
  load(10);
  final engine=WorldEngine();
  final victory=state(hp:1);
  final b=victory.battle!;
  engine.act(victory,WorldCommand.claw,1,1,now);
  expect(victory.battle,isNull);
  expect(b.enemyHp,0);
  final defeat=state();
  defeat.hp=1;
  final d=defeat.battle!;
  engine.act(defeat,WorldCommand.guard,1,1,now);
  expect(defeat.battle,isNull);
  expect(d.enemyHp,50);
 });
 test('実ファイル：保存失敗・再起動後の同一結果と未承認効果拒否',() async{
  load(10);
  final dir=await Directory.systemTemp.createTemp('enemy-regen-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,buffCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.inventory.addStack(item.id,2);
  await c.startWorldBattle('p01_main');
  c.state.world.battle=state().battle;
  await store.save(c.state);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.useBattleBuffItem(item.id,1,1,0,expectedGeneration:c.restoreGeneration),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),buffCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  await restored.useBattleBuffItem(item.id,1,1,0,expectedGeneration:restored.restoreGeneration);
  expect(jsonEncode(restored.state.toJson()),attempted);
  expect(restored.state.world.battle!.enemyHp,55);
  expect(restored.state.inventory.stacks[item.id],1);
  await expectLater(restored.useBattleBuffItem(item.id,1,1,0,expectedGeneration:restored.restoreGeneration),throwsStateError);
  final committed=await primary.readAsString();
  final blocked=AppController(LocalStore(directory:dir),clockMs:()=>now);
  addTearDown(blocked.dispose);
  await expectLater(blocked.initialize(),throwsFormatException);
  expect(await primary.readAsString(),committed);
 });
}
