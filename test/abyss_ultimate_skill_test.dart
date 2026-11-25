import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/abyss_ultimate_candidate.dart';
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
 const def=UltimateSkillCandidate.definition;
 final spec=def.execution!;
 late SkillCatalog catalog;
 const stats=WorldStats(hp:100,physical:1,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 setUpAll((){
  loadExtendedWorldCatalog(18);
  catalog=SkillCatalog(const [def]);
 });
 WorldState world({int life=180,bool unlocked=true,int hp=100,int enemyHp=10,Map<BattleBuff,int>? buffs})=>WorldState(
  hp:hp,physical:0,lifespan:BigInt.from(life),cleared:{if(unlocked)'p18_main'},sequence:1,hpAt:now,energyAt:now,
  battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:enemyHp,rngState:1,activeSkills:[spec],
   acceleratedClaws:2,stopCooldown:3,buffs:buffs),
 );
 test('設計候補500%・寿命180日、試験ST18・CD8、本番無効',(){
  expect((spec.powerPercent,spec.lifeCost,spec.cooldown,spec.hits),(500,180,8,1));
  expect(def.acquisition.clearedStage,18);
  try{
   WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync());
   expect(()=>SkillCatalog(const [def]),throwsFormatException);
  }finally{loadExtendedWorldCatalog(18);}
  final raw=File(AbyssMaster.assetPath).readAsStringSync();
  final rows=(jsonDecode(raw) as Map<String,dynamic>)['skills'] as List;
  expect(rows.singleWhere((r)=>r['id']==def.id)['name'],def.name);
  final s=SkillState(),w=WorldState();
  expect(()=>catalog.learn(w,s,def.id),throwsStateError);
  w.cleared.add('p18_main');
  catalog.learn(w,s,def.id);
  expect(s.learned[def.id],0);
  expect(AbyssMaster.fromJson(raw).skills.definitions,isEmpty);
 });
 test('単体攻撃と通常反撃、寿命のみ全額消費、停止・加速・乱数の整合',(){
  final engine=WorldEngine(),w=world(buffs:{BattleBuff.energyDiscount:2}),b=w.battle!;
  engine.actActiveSkill(w,spec.id,1,1,now);
  expect(w.lifespan,BigInt.zero);
  expect(w.physical,0);
  expect(w.magic,38);
  expect(w.hp,98);
  expect(b.enemyHp,6);
  expect(b.turn,2);
  expect(b.stopCooldown,2);
  expect(b.acceleratedClaws,2);
  expect(b.skillCooldowns[spec.id],8);
  expect(b.buffs[BattleBuff.energyDiscount],1);
  expect(b.rngState,48271*48271%BattleRandom.modulus);
  expect(engine.activeSkillCooldown(b,spec),8);
 });
 test('独立CD満了後再使用、未解放・寿命不足・旧turnは非消費',(){
  final engine=WorldEngine();
  for(final w in [world(unlocked:false),world(life:179)]){
   final before=jsonEncode(w.toJson());
   expect(()=>engine.actActiveSkill(w,spec.id,1,1,now),throwsStateError);
   expect(jsonEncode(w.toJson()),before);
  }
  final w=world(life:360),b=w.battle!;
  final first=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,spec.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),first);
  engine.actActiveSkill(w,spec.id,1,1,now);
  final before=jsonEncode(w.toJson());
  expect(()=>engine.actActiveSkill(w,spec.id,1,2,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
  for(var i=0;i<8;i++){engine.act(w,WorldCommand.guard,1,b.turn,now);}
  expect(b.skillCooldowns,isEmpty);
  expect(b.stopCooldown,0);
  expect(engine.activeSkillUnavailable(w,spec.id),isNull);
  engine.actActiveSkill(w,spec.id,1,b.turn,now);
  expect(w.lifespan,BigInt.zero);
  expect(b.enemyHp,1);
  expect(b.skillCooldowns[spec.id],8);
 });
 test('撃破時反撃なし、敗北時寿命返還なし',(){
  final engine=WorldEngine(),win=world(enemyHp:4,hp:1),lose=world(hp:1);
  engine.actActiveSkill(win,spec.id,1,1,now);
  expect(win.battle,isNull);
  expect(win.hp,1);
  expect(win.gold,40);
  expect(win.summonTickets,3);
  expect(win.lifespan,BigInt.zero);
  engine.actActiveSkill(lose,spec.id,1,1,now);
  expect(lose.battle,isNull);
  expect(lose.hp,0);
  expect(lose.gold,0);
  expect(lose.lifespan,BigInt.zero);
 });
 test('定義・習得条件・snapshot改変拒否とCD保存互換',(){
  final raw=spec.toJson();
  for(final invalid in [
   {...raw,'lifeCost':179},{...raw,'powerPercent':501},{...raw,'powerPercent':600},
   {...raw,'hits':2},{...raw,'physicalCost':1},{...raw,'cooldown':7},
   {...raw,'id':'skill:time_end'},{...raw,'effect':'stopAttack'},
  ]){
   expect(()=>ActiveSkillSpec.fromJson(invalid),throwsFormatException);
  }
  expect(()=>SkillCatalog([SkillDefinition(id:def.id,name:def.name,kind:SkillKind.active,execution:spec)]),throwsFormatException);
  final s=SkillState(),empty=WorldState(cleared:{'p18_main'});
  catalog.learn(empty,s,def.id);catalog.equip(empty,s,def.id);
  final w=world();
  final engine=WorldEngine();
  engine.actActiveSkill(w,spec.id,1,1,now);
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  catalog.validateBattle(restored,s);
  expect(restored.battle!.skillCooldowns[spec.id],8);
  final altered=WorldState.fromJson({...w.toJson(),'battle':{...w.battle!.toJson(),'activeSkills':[{...raw,'name':'改変'}]}});
  expect(()=>catalog.validateBattle(altered,s),throwsFormatException);
  expect(()=>WorldBattle.fromJson({...w.battle!.toJson(),'skillCooldowns':{spec.id:9}}),throwsFormatException);
 });
 test('実ファイル：時空断裂の勝利保存失敗・再起動再試行・二重報酬防止',() async{
  final dir=await Directory.systemTemp.createTemp('ultimate-skill-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
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
  final id=c.state.world.battle!.id;
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
  final rg=restored.restoreGeneration;
  await restored.useBattleActiveSkill(spec.id,id,1,expectedGeneration:rg);
  expect(jsonEncode(restored.state.toJson()),attempted);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.world.lifespan,BigInt.zero);
  expect(restored.state.world.gold,40);
  expect(restored.state.world.summonTickets,3);
  expect(restored.state.world.physical,27);
  expect(restored.state.skills.learned[spec.id],1);
  final after=jsonEncode(restored.state.toJson());
  await expectLater(restored.useBattleActiveSkill(spec.id,id,1,expectedGeneration:rg),throwsStateError);
  expect(jsonEncode(restored.state.toJson()),after);
 });
}
