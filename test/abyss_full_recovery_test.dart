import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_consumable.dart';
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
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const item=RecoveryItem(id:'item:all_test',name:'試験全回復薬',target:RecoveryTarget.all,percent:100);
 final catalog=ConsumableCatalog(const [item]);
 final stats=WorldStats.fromRanks(level:1,fitness:1,intelligence:1,discipline:1,creativity:1);
 test('全回復は不足資源だけを回復し、1個のみ消費する',(){
  final s=AppStateData.initial();
  s.world.hp=0;
  s.world.physical=stats.physicalMax;
  s.world.magic=10;
  s.inventory.addStack(item.id,2);
  expect(catalog.preview(world:s.world,stats:stats,inventory:s.inventory,id:item.id,expectedSequence:0),128);
  expect(catalog.use(world:s.world,stats:stats,inventory:s.inventory,id:item.id,expectedSequence:0),128);
  expect(s.world.hp,100);
  expect(s.world.physical,27);
  expect(s.world.magic,38);
  expect(s.inventory.stacks[item.id],1);
  final before=jsonEncode(s.toJson());
  expect(()=>catalog.use(world:s.world,stats:stats,inventory:s.inventory,id:item.id,expectedSequence:1),throwsStateError);
  expect(jsonEncode(s.toJson()),before);
 });
 test('全回復の不正割合・合計overflowは拒否する',(){
  expect(()=>ConsumableCatalog(const [RecoveryItem(id:'item:bad',name:'試験',target:RecoveryTarget.all,percent:50)]),throwsFormatException);
  final s=AppStateData.initial();
  s.world.hp=0;s.world.physical=0;s.world.magic=0;
  s.inventory.addStack(item.id,1);
  const huge=WorldStats(hp:0x7fffffffffffffff,physical:1,magic:1,defense:0,physicalMax:1,magicMax:1,crit:0);
  final before=jsonEncode(s.toJson());
  expect(()=>catalog.use(world:s.world,stats:huge,inventory:s.inventory,id:item.id,expectedSequence:0),throwsStateError);
  expect(jsonEncode(s.toJson()),before);
 });
 test('戦闘中の全回復は固定上限・反撃・1ターン消費を維持する',(){
  final s=AppStateData.initial();
  final engine=WorldEngine();
  engine.start(s.world,stats,'p01_main',now);
  final b=s.world.battle!;
  s.world.hp=40;s.world.physical=0;s.world.magic=0;
  s.inventory.addStack(item.id,1);
  expect(catalog.useInBattle(world:s.world,inventory:s.inventory,id:item.id,expectedSequence:0,battleId:b.id,expectedTurn:b.turn,engine:engine,now:now),125);
  expect(s.world.hp,100-engine.damage(WorldCatalog.byId(b.encounterId).attack,stats.defense,1));
  expect(s.world.physical,27);
  expect(s.world.magic,38);
  expect(b.turn,2);
  expect(s.world.itemUseSequence,1);
  expect(s.inventory.stacks,isEmpty);
 });
 test('全回復の保存失敗は原本を維持し再起動後の再送を拒否する',() async{
  final dir=await Directory.systemTemp.createTemp('full-recovery-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,consumableCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.hp=40;c.state.world.physical=0;c.state.world.magic=0;
  c.state.inventory.addStack(item.id,2);
  await store.save(c.state);
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.useWorldRecoveryItem(item.id,0,expectedGeneration:c.restoreGeneration),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.fail=false;
  expect(await c.useWorldRecoveryItem(item.id,0,expectedGeneration:c.restoreGeneration),125);
  final restarted=AppController(LocalStore(directory:dir),consumableCatalog:catalog,clockMs:()=>now);
  addTearDown(restarted.dispose);
  await restarted.initialize();
  expect(restarted.state.world.hp,100);
  expect(restarted.state.world.physical,27);
  expect(restarted.state.world.magic,38);
  expect(restarted.state.inventory.stacks[item.id],1);
  await expectLater(restarted.useWorldRecoveryItem(item.id,0,expectedGeneration:restarted.restoreGeneration),throwsStateError);
 });
}
