import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_buff.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

void main(){
 const now=1700000000000;
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const item=BuffItem(id:'item:regen_test',name:'試験再生薬',kind:BattleBuff.regeneration);
 final catalog=BuffCatalog(const [item]);
 final stats=WorldStats.fromRanks(level:1,fitness:1,intelligence:1,discipline:1,creativity:1);
 test('再生は使用ターンに発生せず、次ターンから経過し重複不可',(){
  final s=AppStateData.initial();
  final engine=WorldEngine();
  engine.start(s.world,stats,'p01_main',now);
  final b=s.world.battle!;
  s.inventory.addStack(item.id,2);
  s.world.hp=60;
  final attack=engine.damage(WorldCatalog.byId(b.encounterId).attack,stats.defense,1);
  catalog.use(world:s.world,inventory:s.inventory,id:item.id,expectedSequence:0,battleId:b.id,turn:1,engine:engine,now:now);
  expect(s.world.hp,60-attack);
  expect(b.buffs[BattleBuff.regeneration],5);
  final before=jsonEncode(s.toJson());
  expect(()=>catalog.use(world:s.world,inventory:s.inventory,id:item.id,expectedSequence:1,battleId:b.id,turn:2,engine:engine,now:now),throwsStateError);
  expect(jsonEncode(s.toJson()),before);
  final restored=AppStateData.fromJson(jsonDecode(before) as Map<String,dynamic>);
  expect(restored.world.battle!.buffs[BattleBuff.regeneration],5);
  engine.act(s.world,WorldCommand.guard,b.id,2,now);
  expect(b.buffs[BattleBuff.regeneration],4);
  expect(s.world.hp,60-attack-engine.damage(WorldCatalog.byId(b.encounterId).attack,stats.defense,0.5)+5);
 });
 test('旧戦闘セーブと不正な効果を検証する',(){
  final s=AppStateData.initial();
  WorldEngine().start(s.world,stats,'p01_main',now);
  final raw=s.world.battle!.toJson()..remove('buffs');
  expect(WorldBattle.fromJson(raw).buffs,isEmpty);
  for(final invalid in [null,{'attack':0},{'defense':4},{'unknown':1},{'regeneration':1.5}]){
   expect(()=>WorldBattle.fromJson({...raw,'buffs':invalid}),throwsFormatException);
  }
 });
 test('実ファイル保存と再起動後の二重使用拒否',() async {
  final dir=await Directory.systemTemp.createTemp('battle-buff-');
  addTearDown(()=>dir.delete(recursive:true));
  final c=AppController(LocalStore(directory:dir),buffCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.inventory.addStack(item.id,2);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  await c.useBattleBuffItem(item.id,id,1,0,expectedGeneration:c.restoreGeneration);
  final restored=AppController(LocalStore(directory:dir),buffCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.buffs[BattleBuff.regeneration],5);
  expect(restored.state.inventory.stacks[item.id],1);
  expect(restored.state.world.itemUseSequence,1);
  await expectLater(restored.useBattleBuffItem(item.id,id,1,0,expectedGeneration:restored.restoreGeneration),throwsStateError);
 });
}
