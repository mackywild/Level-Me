import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_awakening_candidate.dart';
import 'package:level_me/world/abyss_chrono_finisher_candidates.dart';
import 'package:level_me/world/abyss_repair_candidates.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/abyss_ultimate_candidate.dart';
import 'package:level_me/world/world_engine.dart';
import 'helpers/extended_world_catalog.dart';

void main(){
 const now=1700000000000;
 const awakening=AwakeningSkillCandidate.definition;
 const heal=RepairSkillCandidates.definitions;
 const stop=ChronoFinisherCandidates.definitions;
 const ultimate=UltimateSkillCandidate.definition,collapse=WorldCollapseSkillCandidate.definition;
 final specs=[heal.first.execution!,awakening.execution!,stop.last.execution!,ultimate.execution!,collapse.execution!];
 const stats=WorldStats(hp:100,physical:2,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 setUpAll(()=>loadExtendedWorldCatalog(21));
 WorldState world()=>WorldState(cleared:{'p03_main','p06_main','p12_main','p18_main','p21_main'},hpAt:now,energyAt:now,lifespan:BigInt.from(1000));
 test('規則v1の回復率・覚醒・共有CD・奥義解放条件を固定',(){
  expect(heal.where((d)=>d.execution!.effect==ActiveSkillEffect.repairHp).map((d)=>d.execution!.rules.repairPercent),[10,25,50,100]);
  expect(awakening.execution!.rules.awakeningPercent,30);
  expect(awakening.execution!.rules.awakeningDuration,3);
  expect(stop.first.execution!.rules.requiredStages,[12]);
  expect(stop.last.execution!.rules.requiredStages,[12,6]);
  expect(stop.last.execution!.rules.sharedStopCooldown,5);
  expect(ultimate.execution!.rules.requiredStages,[18]);
  expect(collapse.execution!.rules.requiredStages,[21]);
  expect(()=>stop.last.execution!.rules.requiredStages.clear(),throwsUnsupportedError);
 });
 test('v3は能動順序と各規則を明示保存、欠落/null/型/値/版を厳密拒否',(){
  final w=world(),engine=WorldEngine();
  engine.start(w,stats,'p01_main',now,activeSkills:specs);
  final raw=w.battle!.toJson(),rules=raw['activeRuleSnapshots'] as List;
  expect(raw['executionVersion'],3);
  expect(rules.length,5);
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  expect(restored.toJson(),w.toJson());
  for(final bad in [null,[],{},rules.reversed.toList(),[...rules,rules.first]]){
   expect(()=>WorldBattle.fromJson({...raw,'activeRuleSnapshots':bad}),throwsFormatException);
  }
  for(var i=0;i<rules.length;i++){
   final row=rules[i] as Map<String,dynamic>;
   for(final key in row.keys){
    for(final altered in [{...row}..remove(key),{...row,key:null}]){
     final next=List<dynamic>.of(rules)..[i]=altered;
     expect(()=>WorldBattle.fromJson({...raw,'activeRuleSnapshots':next}),throwsFormatException,reason:key);
    }
   }
   for(final key in ['version','repairPercent','awakeningPercent','awakeningDuration','sharedStopCooldown']){
    final next=List<dynamic>.of(rules)..[i]={...row,key:(row[key] as int).toDouble()};
    expect(()=>WorldBattle.fromJson({...raw,'activeRuleSnapshots':next}),throwsFormatException);
    final changed=List<dynamic>.of(rules)..[i]={...row,key:(row[key] as int)+1};
    expect(()=>WorldBattle.fromJson({...raw,'activeRuleSnapshots':changed}),throwsFormatException);
   }
  }
  final badStages=List<dynamic>.of(rules)..[2]={...(rules[2] as Map<String,dynamic>),'requiredStages':[12,6.0]};
  expect(()=>WorldBattle.fromJson({...raw,'activeRuleSnapshots':badStages}),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...raw}..remove('activeRuleSnapshots')),throwsFormatException);
 });
 test('v2/v1/版なしは旧形式のまま規則v1を使い戦闘継続',(){
  final w=world(),engine=WorldEngine();
  engine.start(w,stats,'p01_main',now,activeSkills:specs);
  final v2=w.battle!.toJson()..remove('activeRuleSnapshots');
  v2['executionVersion']=2;
  final v1={...v2,'executionVersion':1}..remove('encounterSnapshot');
  final legacy={...v1}..remove('executionVersion')..remove('lifeRewardPercent')..remove('lifeRewardBonuses');
  for(final raw in [v2,v1,legacy]){
   final old=WorldState.fromJson({...w.toJson(),'battle':raw}),b=old.battle!;
   expect(b.executionVersion,raw['executionVersion']);
   expect(b.toJson().containsKey('activeRuleSnapshots'),false);
   engine.actActiveSkill(old,awakening.id,b.id,1,now);
   expect(b.awakeningTurns,3);
   expect(b.skillCooldowns[awakening.id],5);
   expect(old.lifespan,BigInt.from(970));
   expect(b.toJson().containsKey('activeRuleSnapshots'),false);
  }
  expect(()=>WorldBattle.fromJson({...v2,'activeRuleSnapshots':[]}),throwsFormatException);
 });
 test('実ファイル：覚醒発動後再起動し規則と効果・寿命・熟練度を維持',() async{
  final dir=await Directory.systemTemp.createTemp('active-rule-v1-');
  addTearDown(()=>dir.delete(recursive:true));
  final catalog=SkillCatalog(const [awakening]);
  final store=LocalStore(directory:dir);
  final c=AppController(store,skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.add('p12_main');
  c.state.world.lifespan=BigInt.from(30);
  await store.save(c.state);
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(awakening.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(awakening.id,expectedGeneration:gen,expectedRevision:1);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  await c.useBattleActiveSkill(awakening.id,id,1,expectedGeneration:gen);
  final raw=c.state.world.battle!.toJson();
  expect(raw['executionVersion'],3);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.toJson(),raw);
  expect(restored.state.world.battle!.awakeningTurns,3);
  expect(restored.state.world.lifespan,BigInt.zero);
  expect(restored.state.skills.learned[awakening.id],1);
  await restored.worldCommand(WorldCommand.guard,id,2,expectedGeneration:restored.restoreGeneration);
  expect(restored.state.world.battle!.awakeningTurns,2);
  expect(restored.state.world.battle!.skillCooldowns[awakening.id],4);
 });
}
