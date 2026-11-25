import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_buff.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_purification.dart';
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
 const item=PurificationItem(id:'item:purification_test',name:'試験浄化薬');
 const attack=BuffItem(id:'item:attack_test',name:'試験攻撃薬',kind:BattleBuff.attack);
 final catalog=PurificationCatalog(const [item]);
 final buffs=BuffCatalog(const [attack]);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 WorldBattle battle({bool poisoned=true})=>WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:10,rngState:1,statuses:poisoned?{BattleStatus.poison:3}:{},buffs:{BattleBuff.attack:3});
 WorldState world({bool poisoned=true})=>WorldState(hp:100,sequence:1,hpAt:now,energyAt:now,battle:battle(poisoned:poisoned));
 test('旧セーブ互換と状態異常の厳密な復元検証',(){
  final raw=battle().toJson();
  expect(WorldBattle.fromJson(raw).statuses[BattleStatus.poison],3);
  expect(WorldBattle.fromJson(Map<String,dynamic>.of(raw)..remove('statuses')).statuses,isEmpty);
  for(final bad in [null,{'unknown':1},{'poison':0},{'poison':4},{'poison':1.0}]){
   expect(()=>WorldBattle.fromJson({...raw,'statuses':bad}),throwsFormatException);
  }
 });
 test('毒は3ターン経過しHP1未満にしない',(){
  final w=world();
  final engine=WorldEngine();
  for(var i=0;i<3;i++){
   engine.act(w,WorldCommand.guard,1,i+1,now);
   expect(w.hp,100-(i+1)*6);
  }
  expect(w.battle!.statuses,isEmpty);
  final low=world();
  low.hp=2;
  engine.act(low,WorldCommand.guard,1,1,now);
  expect(low.hp,1);
  expect(low.battle!.statuses[BattleStatus.poison],2);
 });
 test('浄化は毒のみ解除しバフと時間系効果を維持する',(){
  final s=AppStateData.initial();
  s.world.battle=battle();
  s.world.sequence=1;
  s.world.battle!.acceleratedClaws=2;
  s.world.battle!.stopCooldown=3;
  s.inventory.addStack(item.id,2);
  final engine=WorldEngine();
  int use()=>catalog.use(world:s.world,inventory:s.inventory,id:item.id,expectedSequence:s.world.itemUseSequence,battleId:1,turn:s.world.battle!.turn,engine:engine,now:now);
  expect(use(),1);
  expect(s.world.battle!.statuses,isEmpty);
  expect(s.world.battle!.buffs[BattleBuff.attack],2);
  expect(s.world.battle!.acceleratedClaws,2);
  expect(s.world.battle!.stopCooldown,2);
  expect(s.world.hp,98);
  expect(s.world.battle!.turn,2);
  expect(s.inventory.stacks[item.id],1);
  final before=jsonEncode(s.toJson());
  expect(use,throwsStateError);
  expect(jsonEncode(s.toJson()),before);
 });
 test('本番マスターは浄化候補を公開せず衝突や有効化を拒否',(){
  Map<String,dynamic> root()=>jsonDecode(File(AbyssMaster.assetPath).readAsStringSync()) as Map<String,dynamic>;
  final raw=root();
  expect(AbyssMaster.fromJson(jsonEncode(raw)).purification.items,isEmpty);
  for(final change in <void Function(Map<String,dynamic>)>[
   (j){j['purificationEnabled']=true;},
   (j){(j['purification'] as List).first['id']='item:iron';},
   (j){(j['purification'] as List).first['id']=(j['buffs'] as List).first['id'];},
   (j){(j['purification'] as List).first['id']=(j['recovery'] as List).first['id'];},
   (j){(j['summon'] as List).add({'pool':'supplies','masterId':'item:purification'});},
  ]){
   final j=root();change(j);
   expect(()=>AbyssMaster.fromJson(jsonEncode(j)),throwsFormatException);
  }
 });
 test('実ファイル：未承認復元拒否・保存失敗・再起動・再送拒否',() async {
  final dir=await Directory.systemTemp.createTemp('purification-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,buffCatalog:buffs,purificationCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.inventory.addStack(item.id,2);
  await c.startWorldBattle('p01_main');
  c.state.world.battle=battle();
  await store.save(c.state);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  final blocked=AppController(LocalStore(directory:dir),buffCatalog:buffs,clockMs:()=>now);
  addTearDown(blocked.dispose);
  await expectLater(blocked.initialize(),throwsFormatException);
  expect(await primary.readAsString(),bytes);
  store.fail=true;
  await expectLater(c.useBattlePurificationItem(item.id,1,1,0,expectedGeneration:c.restoreGeneration),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),buffCatalog:buffs,purificationCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(await restored.useBattlePurificationItem(item.id,1,1,0,expectedGeneration:restored.restoreGeneration),1);
  expect(jsonEncode(restored.state.toJson()),attempted);
  expect(restored.state.world.battle!.statuses,isEmpty);
  expect(restored.state.inventory.stacks[item.id],1);
  await expectLater(restored.useBattlePurificationItem(item.id,1,1,0,expectedGeneration:restored.restoreGeneration),throwsStateError);
 });
}
