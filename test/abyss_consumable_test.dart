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

class _DelayedStore extends LocalStore {
 _DelayedStore(Directory directory):super(directory:directory);
 Completer<void>? gate,entered;
 bool fail=false;
 @override Future<void> save(AppStateData state) async {
  if(gate!=null){entered!.complete();await gate!.future;}
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}
void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const hp=RecoveryItem(id:'item:hp_test',name:'試験用HP回復薬',target:RecoveryTarget.hp,percent:20);
 const physical=RecoveryItem(id:'item:physical_test',name:'試験用物理回復薬',target:RecoveryTarget.physical,percent:15);
 const magic=RecoveryItem(id:'item:magic_test',name:'試験用魔法回復薬',target:RecoveryTarget.magic,percent:50);
 final catalog=ConsumableCatalog(const [hp,physical,magic]);
 final stats=WorldStats.fromRanks(level:1,fitness:1,intelligence:1,discipline:1,creativity:1);
 test('回復量は最大値基準で端数切り捨て、上限で停止する',(){
  final s=AppStateData.initial();
  s.world.hp=90;
  s.world.physical=0;
  s.world.magic=0;
  for(final item in [hp,physical,magic]){s.inventory.addStack(item.id,1);}
  for(final (item,amount) in [(hp,10),(physical,4),(magic,19)]){
   expect(catalog.use(world:s.world,stats:stats,inventory:s.inventory,id:item.id,expectedSequence:s.world.itemUseSequence),amount);
  }
  expect(s.world.hp,100);
  expect(s.world.physical,4);
  expect(s.world.magic,19);
  expect(s.inventory.stacks,isEmpty);
  expect(s.inventory.discovered,containsAll([hp.id,physical.id,magic.id]));
  expect(s.world.itemUseSequence,3);
 });
 test('満タン・未所持・未承認・古い番号・上限超過では消費しない',(){
  final s=AppStateData.initial();
  s.inventory.addStack(hp.id,2);
  void reject(ConsumableCatalog policy,String id,int seq){
   final before=jsonEncode(s.toJson());
   expect(()=>policy.use(world:s.world,stats:stats,inventory:s.inventory,id:id,expectedSequence:seq),throwsStateError);
   expect(jsonEncode(s.toJson()),before);
  }
  reject(catalog,hp.id,0);
  s.world.hp=50;
  reject(ConsumableCatalog.production,hp.id,0);
  reject(catalog,magic.id,0);
  reject(catalog,hp.id,1);
  s.world.itemUseSequence=0x7fffffffffffffff;
  reject(catalog,hp.id,s.world.itemUseSequence);
 });
 test('不正マスターと不正な取引番号を拒否する',(){
  expect(()=>ConsumableCatalog(const [hp,hp]),throwsFormatException);
  expect(()=>ConsumableCatalog(const [RecoveryItem(id:'item:bad',name:'試験',target:RecoveryTarget.hp,percent:101)]),throwsFormatException);
  expect(()=>ConsumableCatalog(const [RecoveryItem(id:'item:bad',name:'試験',target:RecoveryTarget.hp,percent:0)]),throwsFormatException);
  final old=WorldState().toJson()..remove('itemUseSequence');
  expect(WorldState.fromJson(old).itemUseSequence,0);
  expect(()=>WorldState.fromJson({...old,'itemUseSequence':-1}),throwsFormatException);
  expect(()=>WorldState.fromJson({...old,'itemUseSequence':null}),throwsA(isA<TypeError>()));
 });
 test('回復使用の遅延保存・失敗・再起動・復元後の重複拒否',() async {
  final dir=await Directory.systemTemp.createTemp('abyss-recovery-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_DelayedStore(dir);
  final c=AppController(store,portableBackup:PortableBackup(directory:dir),consumableCatalog:catalog);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.hp=40;
  c.state.world.hpAt=DateTime.now().millisecondsSinceEpoch;
  c.state.inventory.addStack(hp.id,2);
  await store.save(c.state);
  final raw=await c.exportPortableBackup();
  final generation=c.restoreGeneration;
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final bytes=await primary.readAsString();
  store.gate=Completer<void>();
  store.entered=Completer<void>();
  store.fail=true;
  final failed=expectLater(c.useWorldRecoveryItem(hp.id,0,expectedGeneration:generation),throwsStateError);
  await store.entered!.future;
  expect(c.inventoryBusy,true);
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  await expectLater(c.useWorldRecoveryItem(hp.id,0,expectedGeneration:generation),throwsStateError);
  store.gate!.complete();
  await failed;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.gate=null;
  store.fail=false;
  expect(await c.useWorldRecoveryItem(hp.id,0,expectedGeneration:generation),20);
  expect(c.state.world.hp,60);
  expect(c.state.inventory.stacks[hp.id],1);
  final restarted=AppController(LocalStore(directory:dir),portableBackup:PortableBackup(directory:dir),consumableCatalog:catalog);
  addTearDown(restarted.dispose);
  await restarted.initialize();
  expect(restarted.state.world.hp,60);
  expect(restarted.state.world.itemUseSequence,1);
  await expectLater(restarted.useWorldRecoveryItem(hp.id,0,expectedGeneration:restarted.restoreGeneration),throwsStateError);
  await c.importPortableBackup(raw);
  await expectLater(c.useWorldRecoveryItem(hp.id,0,expectedGeneration:generation),throwsStateError);
  expect(c.state.world.hp,40);
  expect(c.state.inventory.stacks[hp.id],2);
  expect(await c.useWorldRecoveryItem(hp.id,0,expectedGeneration:c.restoreGeneration),20);
  await c.startWorldBattle('p01_main');
  final battleBefore=jsonEncode(c.state.toJson());
  await expectLater(c.useWorldRecoveryItem(hp.id,1,expectedGeneration:c.restoreGeneration),throwsStateError);
  expect(jsonEncode(c.state.toJson()),battleBefore);
 });
}
