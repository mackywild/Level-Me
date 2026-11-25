import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

void main(){
 const now=1700000000000;
 const spec=ActiveSkillSpec(id:'skill:test',name:'試験',powerPercent:1,physicalCost:1,cooldown:1);
 const active=SkillDefinition(id:'skill:test',name:'試験',kind:SkillKind.active,execution:spec);
 const passive=SkillDefinition(id:'skill:passive',name:'常時',kind:SkillKind.passive);
 const empty=SkillDefinition(id:'skill:empty',name:'未定',kind:SkillKind.active);
 final catalog=SkillCatalog(const [active,passive,empty]);
 const stats=WorldStats(hp:100,physical:2,magic:1,defense:10,physicalMax:27,magicMax:38,crit:0);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 SkillState state(int count)=>SkillState.fromJson({'version':2,'revision':3,'learned':{active.id:count,passive.id:0,empty.id:0},'active':[active.id,empty.id],'passive':[passive.id]});
 WorldState world({int hp=100,int enemyHp=10,int physical=27})=>WorldState(hp:hp,physical:physical,sequence:1,hpAt:now,energyAt:now,battle:WorldBattle(id:1,encounterId:'p01_main',stats:stats,enemyHp:enemyHp,rngState:1,activeSkills:const [spec]));
 test('レベル境界と上限飽和',(){
  for(var level=1;level<=10;level++){
   final count=(level-1)*10;
   expect(SkillMastery.level(count),level);
   if(count>0)expect(SkillMastery.level(count-1),level-1);
  }
  expect(SkillMastery.next(89),90);
  expect(SkillMastery.next(90),90);
  expect(()=>SkillMastery.level(-1),throwsRangeError);
  expect(()=>SkillMastery.next(91),throwsRangeError);
 });
 test('旧形式は0のみ移行、新形式の値とrevisionを厳密検証',(){
  final legacy={'version':1,'learned':{active.id:0},'active':[active.id],'passive':<String>[]};
  final migrated=SkillState.fromJson(legacy);
  expect(migrated.revision,0);
  expect(migrated.toJson()['version'],2);
  expect(migrated.learned[active.id],0);
  expect(()=>SkillState.fromJson({...legacy,'learned':{active.id:1}}),throwsFormatException);
  final raw=state(10).toJson();
  for(final bad in [null,-1,91,1.0,'1']){
   expect(()=>SkillState.fromJson({...raw,'learned':{active.id:bad,passive.id:0,empty.id:0}}),throwsFormatException);
  }
  expect(()=>SkillState.fromJson(Map<String,dynamic>.of(raw)..remove('revision')),throwsFormatException);
  for(final id in [passive.id,empty.id]){
   final invalid=SkillState.fromJson({...raw,'learned':{active.id:10,passive.id:0,empty.id:0,id:1}});
   expect(()=>catalog.validateSaved(invalid),throwsFormatException);
  }
  expect(()=>SkillCatalog.production.validateSaved(state(1)),throwsFormatException);
  expect(SkillState.fromJson(jsonDecode(jsonEncode(raw)) as Map<String,dynamic>).toJson(),raw);
 });
 test('成立した行動のみ成長し、CD・旧ターン・不足・未定義は非加算',(){
  final s=state(9),w=world(),engine=WorldEngine();
  catalog.executeActive(engine,w,s,active.id,1,1,now);
  expect(s.learned[active.id],10);
  expect(SkillMastery.level(s.learned[active.id]!),2);
  expect(s.revision,3);
  expect(s.learned[passive.id],0);
  final before=jsonEncode(s.toJson()),battleBefore=jsonEncode(w.toJson());
  expect(()=>catalog.executeActive(engine,w,s,active.id,1,1,now),throwsStateError);
  expect(()=>catalog.executeActive(engine,w,s,active.id,1,2,now),throwsStateError);
  expect(()=>catalog.executeActive(engine,w,s,empty.id,1,2,now),throwsStateError);
  expect(()=>catalog.executeActive(engine,world(physical:0),s,active.id,1,1,now),throwsStateError);
  expect(jsonEncode(s.toJson()),before);
  expect(jsonEncode(w.toJson()),battleBefore);
  engine.act(w,WorldCommand.guard,1,2,now);
  catalog.executeActive(engine,w,s,active.id,1,3,now);
  expect(s.learned[active.id],11);
 });
 test('勝利・敗北・最大熟練度での使用と解除後保持',(){
  final engine=WorldEngine();
  final win=world(enemyHp:1),s=state(89);
  catalog.executeActive(engine,win,s,active.id,1,1,now);
  expect(win.battle,isNull);
  expect(s.learned[active.id],90);
  final loss=world(hp:1);
  catalog.executeActive(engine,loss,s,active.id,1,1,now);
  expect(loss.battle,isNull);
  expect(loss.hp,0);
  expect(s.learned[active.id],90);
  final fresh=state(0),defeat=world(hp:1);
  catalog.executeActive(engine,defeat,fresh,active.id,1,1,now);
  expect(fresh.learned[active.id],1);
  catalog.unequip(win,s,active.id);
  expect(s.learned[active.id],90);
  catalog.equip(win,s,active.id);
  expect(s.learned[active.id],90);
 });
}
