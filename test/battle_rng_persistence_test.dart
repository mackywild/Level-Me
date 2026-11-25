import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';
import 'package:level_me/world/abyss_buff.dart';
import 'package:level_me/world/abyss_consumable.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Store extends LocalStore {
 _Store(Directory dir):super(directory:dir);
 Completer<void>? gate,entered;
 bool fail=false;
 String? attempted;
 @override Future<void> save(AppStateData state) async {
  attempted=jsonEncode(state.toJson());
  if(gate!=null){entered!.complete();await gate!.future;}
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}
void main(){
 const now=1700000000000;
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const evasion=BuffItem(id:'item:evasion_test',name:'試験回避薬',kind:BattleBuff.evasion);
 const hp=RecoveryItem(id:'item:hp_test',name:'試験回復薬',target:RecoveryTarget.hp,percent:20);
 final buffs=BuffCatalog(const [evasion]);
 final recovery=ConsumableCatalog(const [hp]);
 const stats=WorldStats(hp:100,physical:2,magic:2,defense:10,physicalMax:27,magicMax:38,crit:0.05);
 test('乱数状態の既知系列・JSON往復・旧セーブ決定的移行',(){
  final b=WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:10,rngState:1);
  BattleRandom.next(b);
  expect(b.rngState,48271);
  BattleRandom.next(b);
  expect(b.rngState,182605794);
  final raw=b.toJson();
  final clone=WorldBattle.fromJson(jsonDecode(jsonEncode(raw)) as Map<String,dynamic>);
  expect(BattleRandom.next(clone),BattleRandom.next(b));
  expect(clone.rngState,b.rngState);
  final old=Map<String,dynamic>.of(raw)..remove('rngVersion')..remove('rngState');
  expect(WorldBattle.fromJson(old).rngState,WorldBattle.fromJson(old).rngState);
  for(final invalid in [null,0,-1,2147483647,1.0,'1']){
   expect(()=>WorldBattle.fromJson({...raw,'rngState':invalid}),throwsFormatException);
  }
  for(final invalid in [null,0,2,1.0,'1']){
   expect(()=>WorldBattle.fromJson({...raw,'rngVersion':invalid}),throwsFormatException);
  }
  expect(()=>WorldBattle.fromJson(Map<String,dynamic>.of(raw)..remove('rngVersion')),throwsFormatException);
  expect(()=>WorldBattle.fromJson(Map<String,dynamic>.of(raw)..remove('rngState')),throwsFormatException);
 });
 test('通常攻撃と回避の乱数は保存状態から再現し、防御のみでは進まない',(){
  final w=WorldState(hp:100,energyAt:now,hpAt:now,sequence:1,
   battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:10,rngState:1));
  final engine=WorldEngine();
  engine.act(w,WorldCommand.guard,1,1,now);
  expect(w.battle!.rngState,1);
  final copy=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  engine.act(w,WorldCommand.claw,1,2,now);
  WorldEngine().act(copy,WorldCommand.claw,1,2,now);
  expect(jsonEncode(w.toJson()),jsonEncode(copy.toJson()));
  expect(w.battle!.rngState,182605794);
  engine.finishBuffTurn(w,BattleBuff.evasion,1,3,now,'回避');
  WorldEngine().finishBuffTurn(copy,BattleBuff.evasion,1,3,now,'回避');
  expect(jsonEncode(w.toJson()),jsonEncode(copy.toJson()));
  expect(w.battle!.rngState,1291394886);
 });
 for(final mode in ['command','recovery','buff']){
  test('実ファイル：$mode の保存失敗後に再起動しても確定結果が一致する',() async {
   final dir=await Directory.systemTemp.createTemp('battle-rng-');
   addTearDown(()=>dir.delete(recursive:true));
   final store=_Store(dir);
   final c=AppController(store,portableBackup:PortableBackup(directory:dir),buffCatalog:buffs,consumableCatalog:recovery,clockMs:()=>now);
   addTearDown(c.dispose);
   await c.initialize();
   c.state.inventory.addStack(evasion.id,2);
   c.state.inventory.addStack(hp.id,2);
   await c.startWorldBattle('p01_main');
   final id=c.state.world.battle!.id;
   // 既知seedと低攻撃力で勝利による乱数状態消滅を避ける。
   c.state.world.battle=WorldBattle(id:id,encounterId:'p01_main',stats:stats,enemyHp:10,rngState:1,
    buffs:mode=='buff'?{}:{BattleBuff.evasion:2});
   c.state.world.hp=50;
   await store.save(c.state);
   final raw=await c.exportPortableBackup();
   final before=jsonEncode(c.state.world.toJson());
   final primary=File('${dir.path}/${LocalStore.fileName}');
   final bytes=await primary.readAsString();
   Future<void> act(AppController controller) async {
    if(mode=='command'){
     await controller.worldCommand(WorldCommand.claw,id,1,expectedGeneration:controller.restoreGeneration);
    }else if(mode=='recovery'){
     await controller.useBattleRecoveryItem(hp.id,id,1,0,expectedGeneration:controller.restoreGeneration);
    }else{
     await controller.useBattleBuffItem(evasion.id,id,1,0,expectedGeneration:controller.restoreGeneration);
    }
   }
   store.gate=Completer<void>();
   store.entered=Completer<void>();
   store.fail=true;
   final failed=expectLater(act(c),throwsStateError);
   await store.entered!.future;
   final attempted=AppStateData.fromJson(jsonDecode(store.attempted!) as Map<String,dynamic>);
   expect(attempted.world.battle!.rngState,isNot(1));
   expect(jsonEncode(c.state.world.toJson()),before);
   expect(await primary.readAsString(),bytes);
   store.gate!.complete();
   await failed;
   expect(jsonEncode(c.state.world.toJson()),before);
   expect(await primary.readAsString(),bytes);
   final restarted=AppController(LocalStore(directory:dir),buffCatalog:buffs,consumableCatalog:recovery,clockMs:()=>now);
   addTearDown(restarted.dispose);
   await restarted.initialize();
   expect(restarted.state.world.battle!.rngState,1);
   await act(restarted);
   expect(jsonEncode(restarted.state.world.toJson()),jsonEncode(attempted.world.toJson()));
   expect(jsonEncode(restarted.state.inventory.toJson()),jsonEncode(attempted.inventory.toJson()));
   await expectLater(act(restarted),throwsStateError);
   final committed=AppController(LocalStore(directory:dir),buffCatalog:buffs,consumableCatalog:recovery,clockMs:()=>now);
   addTearDown(committed.dispose);
   await committed.initialize();
   expect(jsonEncode(committed.state.world.toJson()),jsonEncode(attempted.world.toJson()));
   store.gate=null;
   store.fail=false;
   final generation=c.restoreGeneration;
   await c.importPortableBackup(raw);
   await expectLater(c.worldCommand(WorldCommand.guard,id,1,expectedGeneration:generation),throwsStateError);
   expect(c.state.world.battle!.rngState,1);
  });
 }
}
