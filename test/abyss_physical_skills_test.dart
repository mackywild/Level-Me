import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_physical_candidates.dart';
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
 final catalog=SkillCatalog(PhysicalSkillCandidates.definitions);
 const spec=ActiveSkillSpec(id:'skill:test_multi',name:'試験多段',powerPercent:40,hits:6,physicalCost:5,cooldown:2);
 const def=SkillDefinition(id:'skill:test_multi',name:'試験多段',kind:SkillKind.active,execution:spec);
 final testCatalog=SkillCatalog(const [def]);
 const stats=WorldStats(hp:100,physical:2,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 WorldState world({int enemyHp=10,int physical=27})=>WorldState(physical:physical,sequence:1,hpAt:now,energyAt:now,battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:enemyHp,rngState:1,activeSkills:const [spec]));
 int rngAfter(int count){
  var seed=1;
  for(var i=0;i<count;i++){seed=seed*48271%BattleRandom.modulus;}
  return seed;
 }
 test('設計書5候補のID/名称/威力/消費/hit数と本番無効を固定',(){
  final rows=(jsonDecode(File(AbyssMaster.assetPath).readAsStringSync()) as Map<String,dynamic>)['skills'] as List;
  final expected={'skill:swift_fist':(110,5,1),'skill:double_claw':(65,6,2),'skill:shock':(200,12,1),'skill:flurry':(40,15,6),'skill:crimson_flurry':(45,25,10)};
  expect(catalog.definitions.length,5);
  for(final def in catalog.definitions){
   final s=def.execution!;
   expect((s.powerPercent,s.physicalCost,s.hits),expected[def.id]);
   expect(rows.singleWhere((r)=>r['id']==def.id)['name'],def.name);
  }
  expect(AbyssMaster.fromJson(File(AbyssMaster.assetPath).readAsStringSync()).skills.definitions,isEmpty);
 });
 test('多段は一括消費・1ターン・各hit独立乱数・反撃1回',(){
  final w=world(),engine=WorldEngine();
  engine.actActiveSkill(w,spec.id,1,1,now);
  expect(w.physical,22);
  expect(w.battle!.enemyHp,4);
  expect(w.battle!.turn,2);
  expect(w.hp,98);
  expect(w.battle!.rngState,rngAfter(12));
  expect(w.battle!.skillCooldowns[spec.id],2);
  expect(w.battle!.log.where((l)=>l.contains('試験多段')).length,6);
  expect(w.battle!.log.where((l)=>l.contains('敵の反撃')).length,1);
 });
 test('途中撃破は残りhitと反撃を行わず報酬1回',(){
  final w=world(enemyHp:2),b=w.battle!;
  WorldEngine().actActiveSkill(w,spec.id,1,1,now);
  expect(w.battle,isNull);
  expect(b.rngState,rngAfter(4));
  expect(w.physical,22);
  expect(w.hp,100);
  expect(w.gold,40);
  expect(w.summonTickets,3);
 });
 test('旧定義は1hit・不正値とsnapshot改変を拒否',(){
  final raw=spec.toJson();
  expect(ActiveSkillSpec.fromJson(Map<String,dynamic>.of(raw)..remove('hits')).hits,1);
  for(final bad in [null,0,-1,11,2.0,'2']){
   expect(()=>ActiveSkillSpec.fromJson({...raw,'hits':bad}),throwsFormatException);
  }
  expect(()=>ActiveSkillSpec.fromJson({...raw,'powerPercent':100,'hits':6}),throwsFormatException);
  final w=world(),state=SkillState(),empty=WorldState();
  testCatalog.learn(empty,state,spec.id);
  testCatalog.equip(empty,state,spec.id);
  testCatalog.validateBattle(w,state);
  final altered=WorldState.fromJson({...w.toJson(),'battle':{...w.battle!.toJson(),'activeSkills':[{...raw,'hits':5}]}});
  expect(()=>testCatalog.validateBattle(altered,state),throwsFormatException);
 });
 test('実ファイル非致死：多段・乱数・CD・熟練度を同時保存し失敗後再現',() async{
  const low=ActiveSkillSpec(id:'skill:low',name:'試験低威力',powerPercent:1,hits:2,physicalCost:3,cooldown:2);
  final cat=SkillCatalog(const [SkillDefinition(id:'skill:low',name:'試験低威力',kind:SkillKind.active,execution:low)]);
  final dir=await Directory.systemTemp.createTemp('multi-skill-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,skillCatalog:cat,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  final gen=c.restoreGeneration;
  await c.learnWorldSkill(low.id,expectedGeneration:gen,expectedRevision:0);
  await c.equipWorldSkill(low.id,expectedGeneration:gen,expectedRevision:1);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id,enemyHp=c.state.world.battle!.enemyHp;
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${LocalStore.fileName}'),bytes=await File('${dir.path}/${LocalStore.fileName}').readAsString();
  store.fail=true;
  await expectLater(c.useBattleActiveSkill(low.id,id,1,expectedGeneration:gen),throwsStateError);
  final attempted=store.attempted!;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.fail=false;
  await c.useBattleActiveSkill(low.id,id,1,expectedGeneration:gen);
  expect(jsonEncode(c.state.toJson()),attempted);
  expect(c.state.world.battle!.enemyHp,enemyHp-2);
  expect(c.state.world.battle!.skillCooldowns[low.id],2);
  expect(c.state.skills.learned[low.id],1);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:cat,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.toJson(),c.state.world.battle!.toJson());
  expect(restored.state.skills.learned[low.id],1);
  await expectLater(restored.useBattleActiveSkill(low.id,id,1,expectedGeneration:restored.restoreGeneration),throwsStateError);
  expect(restored.state.skills.learned[low.id],1);
 });
}
