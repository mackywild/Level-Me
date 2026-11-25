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
 const stats=WorldStats(hp:100,physical:1,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 const item=BuffItem(id:'item:lethal_test',name:'試験不屈薬',kind:BattleBuff.lethalProtection);
 final catalog=BuffCatalog(const [item]);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 WorldState state({int hp=100,Map<BattleBuff,int>? buffs})=>WorldState(hp:hp,sequence:1,hpAt:now,energyAt:now,battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:10,rngState:1,buffs:buffs??{BattleBuff.lethalProtection:1}));
 test('非致死では経過せず、致死境界で一度だけ発動する',(){
  final engine=WorldEngine();
  final w=state();
  for(var i=0;i<4;i++){
   engine.act(w,WorldCommand.guard,1,w.battle!.turn,now);
   expect(w.battle!.buffs[BattleBuff.lethalProtection],1);
  }
  final damage=engine.damage(WorldCatalog.byId('p01_main').attack,stats.defense,0.5);
  w.hp=damage;
  engine.act(w,WorldCommand.guard,1,w.battle!.turn,now);
  expect(w.hp,1);
  expect(w.battle!.buffs.containsKey(BattleBuff.lethalProtection),false);
  engine.act(w,WorldCommand.guard,1,w.battle!.turn,now);
  expect(w.hp,0);
  expect(w.battle,isNull);
  expect(w.lastResult,contains('敗北'));
 });
 test('回避成功は耐性を消費せず、再生は致死耐性発動後に処理する',(){
  final engine=WorldEngine();
  final w=state(hp:1,buffs:{BattleBuff.lethalProtection:1,BattleBuff.evasion:1,BattleBuff.regeneration:2});
  engine.act(w,WorldCommand.guard,1,1,now);
  expect(w.battle!.log,contains('敵の反撃を回避した。'));
  expect(w.battle!.buffs[BattleBuff.lethalProtection],1);
  expect(w.hp,6);
  w.hp=1;
  engine.act(w,WorldCommand.guard,1,2,now);
  expect(w.hp,6);
  expect(w.battle!.buffs,isEmpty);
 });
 test('使用時の反撃にも有効、再使用は未発動中拒否、撤退で消滅',(){
  final engine=WorldEngine();
  final s=AppStateData.initial();
  s.world.battle=state(buffs:{}).battle;
  s.world.sequence=1;s.world.hpAt=now;s.world.energyAt=now;
  s.inventory.addStack(item.id,2);
  catalog.use(world:s.world,inventory:s.inventory,id:item.id,expectedSequence:0,battleId:1,turn:1,engine:engine,now:now);
  expect(s.world.battle!.buffs[BattleBuff.lethalProtection],1);
  final before=jsonEncode(s.toJson());
  expect(()=>catalog.use(world:s.world,inventory:s.inventory,id:item.id,expectedSequence:1,battleId:1,turn:2,engine:engine,now:now),throwsStateError);
  expect(jsonEncode(s.toJson()),before);
  engine.act(s.world,WorldCommand.retreat,1,2,now);
  expect(s.world.battle,isNull);
  expect(s.inventory.stacks[item.id],1);
  final low=AppStateData.initial();
  low.world.battle=state(buffs:{}).battle;
  low.world.sequence=1;low.world.hp=1;
  low.inventory.addStack(item.id,1);
  catalog.use(world:low.world,inventory:low.inventory,id:item.id,expectedSequence:0,battleId:1,turn:1,engine:engine,now:now);
  expect(low.world.hp,1);
  expect(low.world.battle!.buffs,isEmpty);
  expect(low.inventory.stacks,isEmpty);
 });
 test('不正な残り回数は拒否する',(){
  final raw=state().battle!.toJson();
  for(final value in [0,2,-1,1.0,null]){
   expect(()=>WorldBattle.fromJson({...raw,'buffs':{'lethalProtection':value}}),throwsFormatException);
  }
 });
 test('実ファイル：致死発動の保存失敗・再起動・再試行・二重拒否',() async{
  final dir=await Directory.systemTemp.createTemp('lethal-protection-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,buffCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.inventory.addStack(item.id,2);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  await c.useBattleBuffItem(item.id,id,1,0,expectedGeneration:c.restoreGeneration);
  c.state.world.hp=1;
  await store.save(c.state);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.worldCommand(WorldCommand.guard,id,2,expectedGeneration:c.restoreGeneration),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  final blocked=AppController(LocalStore(directory:dir),clockMs:()=>now);
  addTearDown(blocked.dispose);
  await expectLater(blocked.initialize(),throwsFormatException);
  expect(await primary.readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),buffCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.buffs[BattleBuff.lethalProtection],1);
  await restored.worldCommand(WorldCommand.guard,id,2,expectedGeneration:restored.restoreGeneration);
  expect(jsonEncode(restored.state.toJson()),attempted);
  expect(restored.state.world.hp,1);
  expect(restored.state.world.battle!.buffs,isEmpty);
  await expectLater(restored.worldCommand(WorldCommand.guard,id,2,expectedGeneration:restored.restoreGeneration),throwsStateError);
  expect(restored.state.inventory.stacks[item.id],1);
  await restored.worldCommand(WorldCommand.guard,id,3,expectedGeneration:restored.restoreGeneration);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.world.lastResult,contains('敗北'));
 });
}
