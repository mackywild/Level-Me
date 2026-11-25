import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';
import 'package:level_me/world/abyss_consumable.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Store extends LocalStore {
 _Store(Directory directory):super(directory:directory);
 Completer<void>? gate,entered;
 bool fail=false;
 @override Future<void> save(AppStateData state) async {
  if(gate!=null){entered!.complete();await gate!.future;}
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}
void main(){
 const now=1700000000000;
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const hp=RecoveryItem(id:'item:hp_test',name:'試験回復薬',target:RecoveryTarget.hp,percent:20);
 const energy=RecoveryItem(id:'item:energy_test',name:'試験物理回復薬',target:RecoveryTarget.physical,percent:50);
 final catalog=ConsumableCatalog(const [hp,energy]);
 final stats=WorldStats.fromRanks(level:1,fitness:1,intelligence:1,discipline:1,creativity:1);
 test('回復は戦闘固定性能を参照し、反撃・遅延・CDを1ターン進める',(){
  final s=AppStateData.initial();
  final engine=WorldEngine();
  engine.start(s.world,stats,'p01_main',now);
  final b=s.world.battle!;
  s.world.hp=50;
  s.inventory.addStack(hp.id,2);
  b.slowTurns=2;
  b.stopCooldown=3;
  b.acceleratedClaws=2;
  final enemyHp=b.enemyHp;
  final attack=engine.damage(WorldCatalog.byId(b.encounterId).attack,stats.defense,0.7);
  expect(catalog.useInBattle(world:s.world,inventory:s.inventory,id:hp.id,expectedSequence:0,battleId:b.id,expectedTurn:1,engine:engine,now:now),20);
  expect(s.world.hp,70-attack);
  expect(b.turn,2);
  expect(b.enemyHp,enemyHp);
  expect(b.slowTurns,1);
  expect(b.stopCooldown,2);
  expect(b.acceleratedClaws,2);
  expect(s.world.itemUseSequence,1);
  expect(s.inventory.stacks[hp.id],1);
  expect(b.log.any((line)=>line.contains(hp.name)),true);
  expect(b.log.last,contains('敵の反撃'));
  final before=jsonEncode(s.toJson());
  expect(()=>catalog.useInBattle(world:s.world,inventory:s.inventory,id:hp.id,expectedSequence:1,battleId:b.id,expectedTurn:1,engine:engine,now:now),throwsStateError);
  expect(jsonEncode(s.toJson()),before);
 });
 test('満タン・未所持・無効・誤番号を拒否し、反撃敗北でも消費を維持する',(){
  final s=AppStateData.initial();
  final engine=WorldEngine();
  engine.start(s.world,stats,'p01_main',now);
  final b=s.world.battle!;
  s.inventory.addStack(hp.id,1);
  void reject(ConsumableCatalog policy,String id,int seq){
   final before=jsonEncode(s.toJson());
   expect(()=>policy.useInBattle(world:s.world,inventory:s.inventory,id:id,expectedSequence:seq,battleId:b.id,expectedTurn:b.turn,engine:engine,now:now),throwsStateError);
   expect(jsonEncode(s.toJson()),before);
  }
  reject(catalog,hp.id,0);
  s.world.hp=1;
  reject(catalog,energy.id,0);
  reject(ConsumableCatalog.production,hp.id,0);
  reject(catalog,hp.id,1);
  s.inventory.addStack(energy.id,1);
  s.world.physical=0;
  expect(catalog.useInBattle(world:s.world,inventory:s.inventory,id:energy.id,expectedSequence:0,battleId:b.id,expectedTurn:b.turn,engine:engine,now:now),13);
  expect(s.world.battle,isNull);
  expect(s.world.hp,0);
  expect(s.world.lastResult,contains('敗北'));
  expect(s.inventory.stacks.containsKey(energy.id),false);
  expect(s.world.itemUseSequence,1);
 });
 test('保存遅延・失敗・通常コマンドとの競合・再起動後の再送を拒否する',() async {
  final dir=await Directory.systemTemp.createTemp('battle-recovery-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,portableBackup:PortableBackup(directory:dir),consumableCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.hp=50;
  c.state.inventory.addStack(hp.id,2);
  await c.startWorldBattle('p01_main');
  final b=c.state.world.battle!;
  final generation=c.restoreGeneration;
  final raw=await c.exportPortableBackup();
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final bytes=await primary.readAsString();
  store.gate=Completer<void>();
  store.entered=Completer<void>();
  store.fail=true;
  final failure=expectLater(c.useBattleRecoveryItem(hp.id,b.id,1,0,expectedGeneration:generation),throwsStateError);
  await store.entered!.future;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  await expectLater(c.useBattleRecoveryItem(hp.id,b.id,1,0,expectedGeneration:generation),throwsStateError);
  store.gate!.complete();
  await failure;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.gate=null;
  store.fail=false;
  final use=c.useBattleRecoveryItem(hp.id,b.id,1,0,expectedGeneration:generation);
  final stale=expectLater(c.worldCommand(WorldCommand.guard,b.id,1),throwsStateError);
  expect(await use,20);
  await stale;
  expect(c.state.world.battle!.turn,2);
  expect(c.state.inventory.stacks[hp.id],1);
  final restarted=AppController(LocalStore(directory:dir),consumableCatalog:catalog,clockMs:()=>now);
  addTearDown(restarted.dispose);
  await restarted.initialize();
  expect(restarted.state.world.battle!.turn,2);
  expect(restarted.state.world.itemUseSequence,1);
  await expectLater(restarted.useBattleRecoveryItem(hp.id,b.id,1,0,expectedGeneration:restarted.restoreGeneration),throwsStateError);
  await c.importPortableBackup(raw);
  await expectLater(c.useBattleRecoveryItem(hp.id,b.id,1,0,expectedGeneration:generation),throwsStateError);
  expect(c.state.inventory.stacks[hp.id],2);
  expect(c.state.world.battle!.turn,1);
 });
}
