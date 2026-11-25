import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_consumable.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_rewind_candidate.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';
import 'helpers/extended_world_catalog.dart';

class _Store extends LocalStore {
 _Store(Directory dir):super(directory:dir);
 bool fail=false;
 String? attempted;
 @override Future<void> save(AppStateData state) async{
  attempted=jsonEncode(state.toJson());
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}

void main(){
 const now=1700000000000;
 const def=RewindSkillCandidate.definition;
 final spec=def.execution!;
 late SkillCatalog catalog;
 const stats=WorldStats(hp:100,physical:2,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 setUpAll((){
  loadExtendedWorldCatalog(16);
  catalog=SkillCatalog(const [def]);
 });
 WorldState start(WorldEngine engine,{int hp=100,int life=90,bool equipped=true}){
  final w=WorldState(hp:hp,lifespan:BigInt.from(life),cleared:{'p16_main'},hpAt:now,energyAt:now,gold:12,magicCrystals:3,summonTickets:2,supplyTickets:1,itemUseSequence:4);
  engine.start(w,stats,'p01_main',now,activeSkills:equipped?[spec]:const []);
  return w;
 }
 test('設計書ST16・90日・CD8、実マスターは未公開、本番無効',(){
  expect((def.acquisition.clearedStage,spec.lifeCost,spec.cooldown),(16,90,8));
  try{
   WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync());
   expect(()=>SkillCatalog(const [def]),throwsFormatException);
  }finally{loadExtendedWorldCatalog(16);}
  final raw=File(AbyssMaster.assetPath).readAsStringSync();
  final rows=(jsonDecode(raw) as Map<String,dynamic>)['skills'] as List;
  expect(rows.singleWhere((r)=>r['id']==def.id)['name'],def.name);
  expect(AbyssMaster.fromJson(raw).skills.definitions,isEmpty);
  final state=SkillState(),w=WorldState();
  expect(()=>catalog.learn(w,state,def.id),throwsStateError);
  w.cleared.add('p16_main');
  catalog.learn(w,state,def.id);
  expect(state.learned[def.id],0);
 });
 test('前ターン開始HPのみ復元し反撃、物理消費・敵HP・乱数・資産を巻き戻さない',(){
  final engine=WorldEngine(),w=start(engine),b=w.battle!;
  expect(b.previousTurnHp,isNull);
  final first=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,spec.id,b.id,1,now),throwsStateError);
  expect(jsonEncode(w.toJson()),first);
  engine.act(w,WorldCommand.claw,b.id,1,now);
  expect(w.hp,98);
  expect(b.previousTurnHp,100);
  expect(w.physical,23);
  final enemyHp=b.enemyHp,rng=b.rngState;
  final loaded=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  expect(loaded.battle!.previousTurnHp,100);
  engine.actActiveSkill(loaded,spec.id,b.id,2,now);
  final after=loaded.battle!;
  // HP100へ戻してから通常反撃2。結果HPが同じでも成立した行動。
  expect(loaded.hp,98);
  expect(after.previousTurnHp,98);
  expect(after.turn,3);
  expect(after.skillCooldowns[spec.id],8);
  expect(after.enemyHp,enemyHp);
  expect(after.rngState,rng);
  expect(loaded.physical,23);
  expect(loaded.magic,38);
  expect(loaded.lifespan,BigInt.zero);
  expect(loaded.gold,12);
  expect(loaded.magicCrystals,3);
  expect(loaded.summonTickets,2);
  expect(loaded.supplyTickets,1);
  expect(loaded.itemUseSequence,4);
  expect(after.log.any((l)=>l.contains('HP +2')),true);
  final before=jsonEncode(loaded.toJson());
  expect(()=>engine.actActiveSkill(loaded,spec.id,b.id,3,now),throwsStateError);
  expect(jsonEncode(loaded.toJson()),before);
  for(var i=0;i<8;i++){engine.act(loaded,WorldCommand.guard,b.id,after.turn,now);}
  expect(after.skillCooldowns,isEmpty);
  expect(engine.activeSkillUnavailable(loaded,spec.id),'寿命不足');
 });
 test('回復アイテム使用前のHPを記録し、逆行でHPを下げず消費も戻さない',(){
  final engine=WorldEngine(),w=start(engine,hp:50),b=w.battle!;
  final inventory=AbyssInventory()..addStack('item:test',1);
  final items=ConsumableCatalog(const [RecoveryItem(id:'item:test',name:'試験薬',target:RecoveryTarget.hp,percent:20)]);
  items.useInBattle(world:w,inventory:inventory,id:'item:test',expectedSequence:4,battleId:b.id,expectedTurn:1,engine:engine,now:now);
  expect(w.hp,68);
  expect(b.previousTurnHp,50);
  expect(inventory.stacks,isEmpty);
  expect(w.itemUseSequence,5);
  final before=jsonEncode(w.toJson());
  expect(engine.activeSkillUnavailable(w,spec.id),'復元できるHPなし');
  expect(()=>engine.actActiveSkill(w,spec.id,b.id,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
  expect(inventory.stacks,isEmpty);
  engine.act(w,WorldCommand.claw,b.id,2,now);
  expect(w.hp,66);
  expect(b.previousTurnHp,68);
  engine.actActiveSkill(w,spec.id,b.id,3,now);
  expect(w.hp,66);
  expect(w.itemUseSequence,5);
  expect(inventory.stacks,isEmpty);
 });
 test('未解放・寿命不足・古いturnは履歴と資産を変更しない',(){
  final engine=WorldEngine();
  final locked=WorldState(lifespan:BigInt.from(90),hpAt:now,energyAt:now);
  final lockedBefore=jsonEncode(locked.toJson());
  expect(()=>engine.start(locked,stats,'p01_main',now,activeSkills:[spec]),throwsStateError);
  expect(jsonEncode(locked.toJson()),lockedBefore);
  final tampered=start(engine)..cleared.remove('p16_main');
  for(final w in [tampered,start(engine,life:89)]){
   final b=w.battle!;
   engine.act(w,WorldCommand.guard,b.id,1,now);
   final before=jsonEncode(w.toJson());
   expect(()=>engine.actActiveSkill(w,spec.id,b.id,2,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
  final w=start(engine),b=w.battle!;
  engine.act(w,WorldCommand.guard,b.id,1,now);
  final before=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,spec.id,b.id,1,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
 });
 test('履歴欠落・不正型・境界・別turn・現在HP不一致を拒否、旧戦闘は互換',(){
  final engine=WorldEngine(),w=start(engine),b=w.battle!;
  final first=b.toJson();
  expect(()=>WorldBattle.fromJson({...first,'rewindHistory':{'turn':1,'startHp':100,'previousHp':100}}),throwsFormatException);
  engine.act(w,WorldCommand.guard,b.id,1,now);
  final raw=b.toJson();
  final history=raw['rewindHistory'] as Map<String,dynamic>;
  for(final bad in [
   null,{}, {...history,'turn':1},{...history,'previousHp':null},
   {...history,'previousHp':0},{...history,'previousHp':101},{...history,'previousHp':100.0},
   {...history,'startHp':0},{...history,'startHp':101},{...history,'startHp':'99'},
   {...history}..remove('previousHp'),
  ]){
   expect(()=>WorldBattle.fromJson({...raw,'rewindHistory':bad}),throwsFormatException);
  }
  expect(()=>WorldBattle.fromJson({...raw}..remove('rewindHistory')),throwsFormatException);
  expect(()=>WorldState.fromJson({...w.toJson(),'battle':{...raw,'rewindHistory':{...history,'startHp':100}}}),throwsFormatException);
  final old=start(engine,equipped:false);
  engine.act(old,WorldCommand.guard,old.battle!.id,1,now);
  expect(old.battle!.toJson().containsKey('rewindHistory'),false);
  expect(WorldState.fromJson(jsonDecode(jsonEncode(old.toJson())) as Map<String,dynamic>).battle!.previousTurnHp,isNull);
  expect(()=>WorldBattle.fromJson({...old.battle!.toJson(),'rewindHistory':history}),throwsFormatException);
  for(final bad in [
   {...spec.toJson(),'lifeCost':89},{...spec.toJson(),'cooldown':7},
   {...spec.toJson(),'physicalCost':1},{...spec.toJson(),'id':'skill:unknown'},
  ]){
   expect(()=>ActiveSkillSpec.fromJson(bad),throwsFormatException);
  }
 });
 test('撤退後の新戦闘に履歴を持ち越さない',(){
  final engine=WorldEngine(),w=start(engine),b=w.battle!;
  engine.act(w,WorldCommand.guard,b.id,1,now);
  engine.act(w,WorldCommand.retreat,b.id,2,now);
  expect(w.battle,isNull);
  engine.start(w,stats,'p01_main',now,activeSkills:[spec]);
  expect(w.battle!.id,isNot(b.id));
  expect(w.battle!.previousTurnHp,isNull);
  expect(engine.activeSkillUnavailable(w,spec.id),'前ターンのHP記録なし');
 });
 test('実ファイル：履歴・寿命・熟練度・CDを保存失敗後に同一結果で再試行',() async{
  final dir=await Directory.systemTemp.createTemp('rewind-skill-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.add('p16_main');
  c.state.world.lifespan=BigInt.from(90);
  await store.save(c.state);
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(spec.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(spec.id,expectedGeneration:gen,expectedRevision:1);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  await c.worldCommand(WorldCommand.guard,id,1,expectedGeneration:gen);
  expect(c.state.world.battle!.previousTurnHp,100);
  expect(c.state.world.hp,99);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.useBattleActiveSkill(spec.id,id,2,expectedGeneration:gen),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.previousTurnHp,100);
  await restored.useBattleActiveSkill(spec.id,id,2,expectedGeneration:restored.restoreGeneration);
  expect(jsonEncode(restored.state.toJson()),attempted);
  expect(restored.state.world.hp,98);
  expect(restored.state.world.battle!.previousTurnHp,99);
  expect(restored.state.world.battle!.skillCooldowns[spec.id],8);
  expect(restored.state.world.lifespan,BigInt.zero);
  expect(restored.state.skills.learned[spec.id],1);
  await expectLater(restored.useBattleActiveSkill(spec.id,id,2,expectedGeneration:restored.restoreGeneration),throwsStateError);
 });
}
