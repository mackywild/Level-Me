import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/abyss_ultimate_candidate.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';
import 'helpers/extended_world_catalog.dart';

void main(){
 const now=1700000000000,limit=0x7fffffffffffffff;
 const stats=WorldStats(hp:100,physical:40,magic:45,defense:10,physicalMax:27,magicMax:38,crit:0);
 const def=UltimateSkillCandidate.definition;
 final spec=def.execution!;
 const physical=ActiveSkillSpec(id:'skill:test',name:'試験攻撃',powerPercent:100,physicalCost:4,cooldown:2);
 late String master;
 setUpAll(()=>master=File(WorldCatalog.assetPath).readAsStringSync());
 setUp(()=>loadExtendedWorldCatalog(21));
 tearDown(()=>WorldCatalog.loadJson(master));
 WorldState world()=>WorldState(cleared:{'p06_main','p12_main','p18_main'},hpAt:now,energyAt:now,lifespan:BigInt.from(1000));
 void change(String id,Map<String,dynamic> fields){
  final root=jsonDecode(master) as Map<String,dynamic>;
  final row=(root['encounters'] as List).singleWhere((e)=>e['id']==id) as Map<String,dynamic>;
  row.addAll(fields);
  WorldCatalog.loadJson(jsonEncode(root));
 }
 test('G・初回召喚券の上限ちょうどを許可し1超過を開始前に拒否',(){
  final engine=WorldEngine();
  for(final balances in [(limit-39,0),(0,limit-2)]){
   final w=world()..gold=balances.$1..summonTickets=balances.$2;
   final before=jsonEncode(w.toJson());
   expect(()=>engine.start(w,stats,'p01_main',now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
  final w=world()..gold=limit-40..summonTickets=limit-3;
  engine.start(w,stats,'p01_main',now);
  engine.act(w,WorldCommand.claw,w.battle!.id,1,now);
  expect(w.battle,isNull);
  expect(w.gold,limit);
  expect(w.summonTickets,limit);
  expect(w.supplyTickets,0);
  expect(w.cleared.contains('p01_main'),true);
  expect(WorldState.fromJson(w.toJson()).gold,limit);
 });
 test('初回補給券は上限ちょうど、再戦は券上限でも追加なし',(){
  final engine=WorldEngine(),w=world();
  w.cleared.add('p01_main');
  w.supplyTickets=limit;
  w.summonTickets=limit;
  final before=jsonEncode(w.toJson());
  expect(()=>engine.start(w,stats,'p01_hunt',now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
  w.supplyTickets=limit-1;
  w.gold=limit-30;
  engine.start(w,stats,'p01_hunt',now);
  engine.act(w,WorldCommand.claw,w.battle!.id,1,now);
  expect(w.gold,limit-15);
  expect(w.supplyTickets,limit);
  engine.start(w,stats,'p01_hunt',now);
  engine.act(w,WorldCommand.claw,w.battle!.id,1,now);
  expect(w.gold,limit);
  expect(w.supplyTickets,limit);
  expect(w.summonTickets,limit);
 });
 test('極端な敵GとBigInt寿命、開始時固定報酬を境界判定に利用',(){
  change('p01_hunt',{'gold':limit,'lifeDays':limit});
  final engine=WorldEngine(),w=world();
  w.cleared.addAll(['p01_main','p03_main']);
  w.gold=1;
  expect(()=>engine.start(w,stats,'p01_hunt',now),throwsStateError);
  w.gold=0;
  engine.start(w,stats,'p01_hunt',now,lifeRewardBonuses:[LifeRewardBonus.timeAbsorption,LifeRewardBonus.predatorInstinct]);
  final raw=w.toJson();
  change('p01_hunt',{'gold':1,'lifeDays':1});
  final restored=WorldState.fromJson(raw);
  restored.gold=1;
  final before=jsonEncode(restored.toJson());
  expect(()=>engine.act(restored,WorldCommand.claw,restored.battle!.id,1,now),throwsStateError);
  expect(jsonEncode(restored.toJson()),before);
  restored.gold=0;
  engine.act(restored,WorldCommand.claw,restored.battle!.id,1,now);
  expect(restored.gold,limit);
  expect(restored.lifespan,BigInt.from(1000)+BigInt.from(limit)*BigInt.from(130)~/BigInt.from(100));
 });
 test('既存戦闘の全攻撃拒否は寿命・エネルギー・乱数・CD・turnを変更しない',(){
  final engine=WorldEngine(),w=world();
  engine.start(w,stats,'p01_main',now,activeSkills:[physical,spec]);
  w.gold=limit;
  final b=w.battle!,before=jsonEncode(w.toJson());
  for(final command in [WorldCommand.claw,WorldCommand.heavyClaw,WorldCommand.magic,WorldCommand.compositeClaw]){
   expect(engine.unavailable(w,command),contains('ゴールド'));
   expect(()=>engine.act(w,command,b.id,1,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
  for(final active in [physical,spec]){
   expect(engine.activeSkillUnavailable(w,active.id),contains('ゴールド'));
   expect(()=>engine.actActiveSkill(w,active.id,b.id,1,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
  expect(engine.unavailable(w,WorldCommand.guard),isNull);
  engine.act(w,WorldCommand.guard,b.id,1,now);
  expect(b.turn,2);
  expect(engine.unavailable(w,WorldCommand.retreat),isNull);
  engine.act(w,WorldCommand.retreat,b.id,2,now);
  expect(w.battle,isNull);
  expect(w.gold,limit);
  expect(w.cleared.contains('p01_main'),false);
 });
 test('旧形式戦闘・初回券超過も攻撃前拒否しゼロG報酬は許可',(){
  final engine=WorldEngine(),w=world();
  engine.start(w,stats,'p01_main',now);
  final raw=w.battle!.toJson()..remove('activeRuleSnapshots')..remove('encounterSnapshot')..remove('executionVersion')..remove('lifeRewardPercent')..remove('lifeRewardBonuses');
  final old=WorldState.fromJson({...w.toJson(),'battle':raw});
  old.summonTickets=limit-2;
  final before=jsonEncode(old.toJson());
  expect(engine.unavailable(old,WorldCommand.claw),contains('召喚券'));
  expect(()=>engine.act(old,WorldCommand.claw,old.battle!.id,1,now),throwsStateError);
  expect(jsonEncode(old.toJson()),before);
  change('p01_hunt',{'gold':0});
  final zero=world()..gold=limit..supplyTickets=limit;
  zero.cleared.addAll(['p01_main','p01_hunt']);
  engine.start(zero,stats,'p01_hunt',now);
  engine.act(zero,WorldCommand.claw,zero.battle!.id,1,now);
  expect(zero.gold,limit);
  expect(zero.supplyTickets,limit);
 });
 test('実ファイル：上限拒否は公開状態・原本・熟練度を保持し再起動後も撤退可能',() async{
  final dir=await Directory.systemTemp.createTemp('battle-reward-overflow-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=LocalStore(directory:dir),catalog=SkillCatalog(const [def]);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.add('p18_main');
  c.state.world.lifespan=BigInt.from(180);
  await store.save(c.state);
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(spec.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(spec.id,expectedGeneration:gen,expectedRevision:1);
  await c.startWorldBattle('p01_main');
  c.state.world.gold=limit;
  await store.save(c.state);
  final id=c.state.world.battle!.id;
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  await expectLater(c.worldCommand(WorldCommand.claw,id,1,expectedGeneration:gen),throwsStateError);
  await expectLater(c.useBattleActiveSkill(spec.id,id,1,expectedGeneration:gen),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.gold,limit);
  expect(restored.state.world.lifespan,BigInt.from(180));
  expect(restored.state.skills.learned[spec.id],0);
  final rg=restored.restoreGeneration;
  await expectLater(restored.useBattleActiveSkill(spec.id,id,1,expectedGeneration:rg),throwsStateError);
  await restored.worldCommand(WorldCommand.retreat,id,1,expectedGeneration:rg);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.world.gold,limit);
  expect(restored.state.world.lifespan,BigInt.from(180));
  expect(restored.state.skills.learned[spec.id],0);
 });
}
