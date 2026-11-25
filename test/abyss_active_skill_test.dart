import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

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
 const spec=ActiveSkillSpec(id:'skill:test',name:'試験攻撃',powerPercent:150,physicalCost:5,cooldown:2);
 const def=SkillDefinition(id:'skill:test',name:'試験攻撃',kind:SkillKind.active,execution:spec);
 final catalog=SkillCatalog(const [def]);
 const stats=WorldStats(hp:100,physical:2,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 WorldState world({int enemyHp=10,int physical=27,int hp=100,Map<BattleBuff,int>? buffs})=>WorldState(hp:hp,physical:physical,sequence:1,hpAt:now,energyAt:now,battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:enemyHp,rngState:1,activeSkills:const [spec],buffs:buffs));
 test('物理消費・会心乱数・CDと既存コマンドでの経過',(){
  final w=world(buffs:{BattleBuff.energyDiscount:1});
  final engine=WorldEngine();
  expect(engine.activeSkillCost(w,spec),4);
  engine.actActiveSkill(w,spec.id,1,1,now);
  expect(w.physical,23);
  expect(w.battle!.enemyHp,8);
  expect(w.hp,98);
  expect(w.battle!.skillCooldowns[spec.id],2);
  expect(w.battle!.rngState,182605794);
  final before=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,spec.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
  engine.act(w,WorldCommand.guard,1,2,now);
  expect(w.battle!.skillCooldowns[spec.id],1);
  engine.act(w,WorldCommand.guard,1,3,now);
  expect(w.battle!.skillCooldowns,isEmpty);
  expect(engine.activeSkillCost(w,spec),5);
  engine.actActiveSkill(w,spec.id,1,4,now);
  expect(w.physical,18);
 });
 test('未装着・不足・古いターンは非消費、勝利と敗北は共通処理',(){
  final engine=WorldEngine();
  final w=world(physical:4);
  final before=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,spec.id,1,1,now),throwsStateError);
  expect(()=>engine.actActiveSkill(w,'skill:unknown',1,1,now),throwsStateError);
  expect(()=>engine.actActiveSkill(w,spec.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
  final victory=world(enemyHp:1);
  engine.actActiveSkill(victory,spec.id,1,1,now);
  expect(victory.battle,isNull);
  expect(victory.gold,40);
  expect(victory.summonTickets,3);
  expect(victory.physical,22);
  final defeat=world(hp:1);
  engine.actActiveSkill(defeat,spec.id,1,1,now);
  expect(defeat.battle,isNull);
  expect(defeat.hp,0);
  expect(defeat.physical,22);
 });
 test('旧戦闘互換・不正snapshot/CDと未承認定義拒否',(){
  final w=world(),raw=w.battle!.toJson();
  final legacy=Map<String,dynamic>.of(raw)..remove('activeSkills')..remove('skillCooldowns');
  expect(WorldBattle.fromJson(legacy).activeSkills,isEmpty);
  for(final invalid in [
   {...raw,'activeSkills':null},
   {...raw,'activeSkills':[spec.toJson(),spec.toJson()]},
   {...raw,'skillCooldowns':{'skill:unknown':1}},
   {...raw,'skillCooldowns':{spec.id:3}},
   {...raw,'skillCooldowns':{spec.id:1.0}},
   {...raw,'activeSkills':[{...spec.toJson(),'powerPercent':0}]},
  ]){
   expect(()=>WorldBattle.fromJson(invalid),throwsFormatException);
  }
  expect(()=>SkillCatalog.production.validateBattle(w,SkillState()),throwsFormatException);
  final state=SkillState();
  catalog.learn(WorldState(),state,spec.id);
  catalog.equip(WorldState(),state,spec.id);
  catalog.validateBattle(w,state);
  final altered=WorldState.fromJson({...w.toJson(),'battle':{...raw,'activeSkills':[{...spec.toJson(),'powerPercent':151}]}});
  expect(()=>catalog.validateBattle(altered,state),throwsFormatException);
  expect(()=>w.battle!.activeSkills.clear(),throwsUnsupportedError);
 });
 test('実ファイル：開始時固定・保存失敗・再起動後再試行・二重拒否',() async{
  final dir=await Directory.systemTemp.createTemp('active-skill-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(spec.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(spec.id,expectedGeneration:gen,expectedRevision:1);
  await c.startWorldBattle('p01_main');
  expect(c.state.world.battle!.activeSkills.single.id,spec.id);
  final id=c.state.world.battle!.id;
  await expectLater(c.unequipWorldSkill(spec.id,expectedGeneration:gen,expectedRevision:2),throwsStateError);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.fail=true;
  await expectLater(c.useBattleActiveSkill(spec.id,id,1,expectedGeneration:gen),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  await restored.useBattleActiveSkill(spec.id,id,1,expectedGeneration:restored.restoreGeneration);
  expect(jsonEncode(restored.state.toJson()),attempted);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.world.gold,40);
  expect(restored.state.world.physical,22);
  await expectLater(restored.useBattleActiveSkill(spec.id,id,1,expectedGeneration:restored.restoreGeneration),throwsStateError);
 });
}
