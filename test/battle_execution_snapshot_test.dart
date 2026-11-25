import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/abyss_predation_candidates.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

void main(){
 const now=1700000000000;
 const spec=ActiveSkillSpec(id:'skill:test',name:'試験攻撃',powerPercent:100,physicalCost:4,cooldown:2);
 const active=SkillDefinition(id:'skill:test',name:'試験攻撃',kind:SkillKind.active,execution:spec);
 const rewards=PredationSkillCandidates.definitions;
 const stats=WorldStats(hp:100,physical:40,magic:45,defense:10,physicalMax:27,magicMax:38,crit:0);
 late SkillCatalog catalog;
 setUpAll((){
  WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync());
  catalog=SkillCatalog([active,...rewards]);
 });
 WorldState world()=>WorldState(cleared:{'p01_main','p02_main','p03_main'},hpAt:now,energyAt:now,lifespan:BigInt.from(100));
 SkillState loadout(WorldState w){
  final s=SkillState();
  for(final d in catalog.definitions){catalog.learn(w,s,d.id);catalog.equip(w,s,d.id);}
  return s;
 }
 test('新規戦闘は版番号・空を含むsnapshot・数値寿命率を明示保存',(){
  final engine=WorldEngine(),w=world();
  engine.start(w,stats,'p03_hunt',now);
  final raw=w.battle!.toJson();
  expect(raw['executionVersion'],3);
  expect(raw['activeSkills'],isEmpty);
  expect(raw['skillCooldowns'],isEmpty);
  expect(raw['lifeRewardBonuses'],isEmpty);
  expect(raw['lifeRewardPercent'],100);
  final decoded=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  expect(decoded.toJson(),w.toJson());
  catalog.validateBattle(decoded,SkillState());
 });
 test('版番号・必須項目・個別定義の欠落/不正を読み込み時に拒否',(){
  final engine=WorldEngine(),w=world(),s=loadout(w);
  engine.start(w,stats,'p03_hunt',now,activeSkills:catalog.snapshot(s),lifeRewardBonuses:catalog.rewardSnapshot(s));
  final raw=w.battle!.toJson();
  for(final key in ['executionVersion','activeSkills','skillCooldowns','lifeRewardBonuses','lifeRewardPercent']){
   expect(()=>WorldBattle.fromJson({...raw}..remove(key)),throwsFormatException,reason:key);
  }
  for(final bad in [null,0,4,1.0,'1']){
   expect(()=>WorldBattle.fromJson({...raw,'executionVersion':bad}),throwsFormatException);
  }
  for(final bad in [null,100,129,131,130.0,'130']){
   expect(()=>WorldBattle.fromJson({...raw,'lifeRewardPercent':bad}),throwsFormatException);
  }
  for(final key in spec.toJson().keys){
   expect(()=>WorldBattle.fromJson({...raw,'activeSkills':[spec.toJson()..remove(key)]}),throwsFormatException,reason:key);
  }
  expect(()=>WorldBattle.fromJson({...raw,'lifeRewardBonuses':[]}),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...raw,'skillCooldowns':null}),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...raw,'activeSkills':null}),throwsFormatException);
 });
 test('RV-130: v3の全非条件付き項目の欠落・null・誤型を拒否する',(){
  final engine=WorldEngine(),w=world(),s=loadout(w);
  engine.start(w,stats,'p03_hunt',now,activeSkills:catalog.snapshot(s),lifeRewardBonuses:catalog.rewardSnapshot(s));
  final raw=w.battle!.toJson();
  // 装着依存フィールドのない戦闘では出力される全項目が必須。
  for(final key in raw.keys){
   expect(()=>WorldBattle.fromJson({...raw}..remove(key)),throwsFormatException,reason:'欠落: $key');
   expect(()=>WorldBattle.fromJson({...raw,key:null}),throwsFormatException,reason:'null: $key');
  }
  for(final key in ['id','enemyHp','turn','slowTurns','acceleratedClaws','stopCooldown','energyRemainder','hpRemainder','rngVersion','rngState','lifeRewardPercent']){
   expect(()=>WorldBattle.fromJson({...raw,key:1.0}),throwsFormatException,reason:'小数: $key');
   expect(()=>WorldBattle.fromJson({...raw,key:'1'}),throwsFormatException,reason:'文字列: $key');
  }
  for(final key in ['buffs','statuses','skillCooldowns','stats']){
   expect(()=>WorldBattle.fromJson({...raw,key:[]}),throwsFormatException,reason:key);
  }
  for(final key in ['log','activeSkills','lifeRewardBonuses']){
   expect(()=>WorldBattle.fromJson({...raw,key:<String,dynamic>{}}),throwsFormatException,reason:key);
  }
  expect(()=>WorldBattle.fromJson({...raw,'encounterId':1}),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...raw,'log':['戦闘開始',1]}),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...raw}..remove('rngVersion')..remove('rngState')),throwsFormatException);
  final baseStats=stats.toJson();
  for(final key in baseStats.keys){
   expect(()=>WorldBattle.fromJson({...raw,'stats':{...baseStats}..remove(key)}),throwsFormatException,reason:'能力値欠落: $key');
   expect(()=>WorldBattle.fromJson({...raw,'stats':{...baseStats,key:null}}),throwsFormatException,reason:'能力値null: $key');
   expect(()=>WorldBattle.fromJson({...raw,'stats':{...baseStats,key:'1'}}),throwsFormatException,reason:'能力値誤型: $key');
   if(key!='crit'){
    expect(()=>WorldBattle.fromJson({...raw,'stats':{...baseStats,key:1.0}}),throwsFormatException,reason:'能力値小数: $key');
   }
  }
  for(final crit in [double.nan,double.infinity,-0.1,1.1]){
   expect(()=>WorldBattle.fromJson({...raw,'stats':{...baseStats,'crit':crit}}),throwsFormatException);
  }
 });
 test('RV-130: v3の進行中状態を維持し、旧形式だけ補完を許容する',(){
  final w=world(),engine=WorldEngine();
  engine.start(w,stats,'p03_hunt',now);
  final raw=w.battle!.toJson();
  final progressed={...raw,'turn':4,'rngState':182605794,'acceleratedClaws':2,'stopCooldown':3,
   'slowTurns':1,'energyRemainder':123,'hpRemainder':456,'buffs':{'attack':2},'statuses':{'poison':1}};
  final restored=WorldState.fromJson({...w.toJson(),'battle':progressed});
  expect(restored.battle!.toJson(),progressed);
  final legacy={...progressed}..remove('activeRuleSnapshots')..remove('encounterSnapshot')..remove('executionVersion')..remove('lifeRewardPercent')..remove('lifeRewardBonuses')
   ..remove('rngVersion')..remove('rngState')..remove('buffs')..remove('statuses')
   ..remove('acceleratedClaws')..remove('stopCooldown')..remove('energyRemainder')..remove('hpRemainder');
  final old=WorldState.fromJson({...w.toJson(),'battle':legacy}).battle!;
  expect(old.executionVersion,isNull);
  expect(old.rngState,BattleRandom.legacySeed(old.id,old.turn));
  expect(old.buffs,isEmpty);
  expect(old.statuses,isEmpty);
  expect([old.acceleratedClaws,old.stopCooldown,old.energyRemainder,old.hpRemainder],[0,0,0,0]);
  final nullable={...legacy,'acceleratedClaws':null,'stopCooldown':null,'energyRemainder':null,'hpRemainder':null};
  expect(WorldBattle.fromJson(nullable).toJson(),old.toJson());
  expect(()=>WorldBattle.fromJson({...legacy,'rngVersion':BattleRandom.version}),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...legacy,'buffs':null}),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...legacy,'statuses':null}),throwsFormatException);
 });
 test('版付きの空能動snapshotと空報酬snapshotを装着済み状態に照合して拒否',(){
  final engine=WorldEngine(),w=world(),s=loadout(w);
  engine.start(w,stats,'p03_hunt',now,activeSkills:catalog.snapshot(s),lifeRewardBonuses:catalog.rewardSnapshot(s));
  final raw=w.battle!.toJson();
  final missingActive=WorldState.fromJson({...w.toJson(),'battle':{...raw,'activeSkills':[]}});
  expect(()=>catalog.validateBattle(missingActive,s),throwsFormatException);
  final missingRewards=WorldState.fromJson({...w.toJson(),'battle':{...raw,'lifeRewardBonuses':[],'lifeRewardPercent':100}});
  expect(()=>catalog.validateBattle(missingRewards,s),throwsFormatException);
  final both=WorldState.fromJson({...w.toJson(),'battle':{...raw,'activeSkills':[],'lifeRewardBonuses':[],'lifeRewardPercent':100}});
  expect(()=>catalog.validateBattle(both,s),throwsFormatException);
  catalog.validateBattle(WorldState.fromJson(w.toJson()),s);
 });
 test('版番号導入前の保存形式は数値を捏造せず既存規則で継続',(){
  final w=world(),s=SkillState();
  catalog.learn(w,s,active.id);catalog.equip(w,s,active.id);
  w.sequence=1;
  w.battle=WorldBattle(id:1,encounterId:'p03_hunt',stats:stats,enemyHp:35,rngState:1);
  final raw=w.battle!.toJson()..remove('activeSkills')..remove('skillCooldowns');
  final old=WorldState.fromJson({...w.toJson(),'battle':raw});
  expect(old.battle!.executionVersion,isNull);
  expect(old.battle!.lifeRewardPercent,100);
  expect(old.battle!.toJson().containsKey('lifeRewardPercent'),false);
  catalog.validateBattle(old,s);
  final legacySpec=spec.toJson()..remove('hits')..remove('effect')..remove('lifeCost');
  final legacy=WorldState.fromJson({...w.toJson(),'battle':{...raw,'activeSkills':[legacySpec]}});
  catalog.validateBattle(legacy,s);
  expect(legacy.battle!.activeSkills.single.toJson(),spec.toJson());
 });
 test('寿命報酬率130を固定保存し勝利時の基礎寿命報酬へ適用',(){
  final engine=WorldEngine(),w=world(),s=loadout(w);
  engine.start(w,stats,'p03_hunt',now,activeSkills:catalog.snapshot(s),lifeRewardBonuses:catalog.rewardSnapshot(s));
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  expect(restored.battle!.lifeRewardPercent,130);
  expect(restored.battle!.executionVersion,3);
  final id=restored.battle!.id;
  engine.actActiveSkill(restored,spec.id,id,1,now);
  expect(restored.battle,isNull);
  expect(restored.lifespan,BigInt.from(139));
  expect(restored.gold,25);
  expect(restored.supplyTickets,1);
 });
 test('実ファイル：版付きsnapshotの再起動・能動勝利・報酬/熟練度保存',() async{
  final dir=await Directory.systemTemp.createTemp('battle-execution-v3-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=LocalStore(directory:dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.addAll(['p01_main','p02_main','p03_main']);
  c.state.world.lifespan=BigInt.from(100);
  await store.save(c.state);
  final gen=c.restoreGeneration;
  for(final d in catalog.definitions){
   await c.learnWorldSkill(d.id,expectedGeneration:gen,expectedRevision:c.state.skills.revision);
   await c.equipWorldSkill(d.id,expectedGeneration:gen,expectedRevision:c.state.skills.revision);
  }
  await c.startWorldBattle('p03_hunt');
  final id=c.state.world.battle!.id;
  final raw=c.state.world.battle!.toJson();
  expect(raw['executionVersion'],3);
  expect(raw['lifeRewardPercent'],130);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.toJson(),raw);
  final rg=restored.restoreGeneration;
  await restored.useBattleActiveSkill(spec.id,id,1,expectedGeneration:rg);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.world.lifespan,BigInt.from(139));
  expect(restored.state.world.gold,25);
  expect(restored.state.world.supplyTickets,1);
  expect(restored.state.skills.learned[spec.id],1);
  await expectLater(restored.useBattleActiveSkill(spec.id,id,1,expectedGeneration:rg),throwsStateError);
 });
}
