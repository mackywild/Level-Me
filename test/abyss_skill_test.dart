import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/abyss_master.dart';

class _Store extends LocalStore {
 _Store(Directory dir):super(directory:dir);
 bool fail=false;
 Completer<void>? entered,gate;
 @override Future<void> save(AppStateData state) async {
  if(gate!=null){entered!.complete();await gate!.future;}
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}
void main(){
 const now=1700000000000;
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final catalog=SkillCatalog([
  for(var i=0;i<7;i++)SkillDefinition(id:'skill:a$i',name:'能動$i',kind:SkillKind.active),
  for(var i=0;i<4;i++)SkillDefinition(id:'skill:p$i',name:'常時$i',kind:SkillKind.passive),
 ]);
 test('習得・装着の6枠/3枠制限と重複・未習得拒否',(){
  final w=WorldState(),s=SkillState();
  expect(()=>catalog.equip(w,s,'skill:a0'),throwsStateError);
  expect(()=>catalog.learn(w,s,'skill:unknown'),throwsStateError);
  for(final def in catalog.definitions){catalog.learn(w,s,def.id);}
  expect(()=>catalog.learn(w,s,'skill:a0'),throwsStateError);
  for(var i=0;i<6;i++){catalog.equip(w,s,'skill:a$i');}
  for(var i=0;i<3;i++){catalog.equip(w,s,'skill:p$i');}
  expect(s.active.length,6);
  expect(s.passive.length,3);
  final before=jsonEncode(s.toJson());
  expect(()=>catalog.equip(w,s,'skill:a6'),throwsStateError);
  expect(()=>catalog.equip(w,s,'skill:p3'),throwsStateError);
  expect(()=>catalog.equip(w,s,'skill:a0'),throwsStateError);
  expect(jsonEncode(s.toJson()),before);
  catalog.unequip(w,s,'skill:a0');
  catalog.equip(w,s,'skill:a6');
  expect(s.learned['skill:a0'],0);
  expect(s.active.last,'skill:a6');
  expect(()=>s.active.clear(),throwsUnsupportedError);
  expect(()=>s.learned.clear(),throwsUnsupportedError);
  final restored=SkillState.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String,dynamic>);
  catalog.validateSaved(restored);
  expect(jsonEncode(restored.toJson()),jsonEncode(s.toJson()));
 });
 test('旧セーブと不正形式・種別・未承認マスターを検証',(){
  final old=AppStateData.initial().toJson()..remove('skills');
  expect(AppStateData.fromJson(old).skills.learned,isEmpty);
  final raw=SkillState().toJson();
  for(final invalid in [
   {...raw,'version':1.0},
   {...raw,'version':2},
   {...raw,'learned':null},
   {...raw,'learned':{'bad':0}},
   {...raw,'learned':{'skill:a0':-1}},
   {...raw,'learned':{'skill:a0':0.0}},
   {...raw,'active':['skill:a0']},
   {...raw,'learned':{'skill:a0':0},'active':['skill:a0','skill:a0']},
   {...raw,'learned':{'skill:a0':0},'active':['skill:a0'],'passive':['skill:a0']},
   {...raw,'learned':{for(var i=0;i<7;i++)'skill:a$i':0},'active':[for(var i=0;i<7;i++)'skill:a$i']},
   {...raw,'learned':{for(var i=0;i<4;i++)'skill:p$i':0},'passive':[for(var i=0;i<4;i++)'skill:p$i']},
  ]){
   expect(()=>SkillState.fromJson(invalid),throwsFormatException);
  }
  final wrong=SkillState.fromJson({...raw,'learned':{'skill:a0':0},'passive':['skill:a0']});
  expect(()=>catalog.validateSaved(wrong),throwsFormatException);
  final unknown=SkillState.fromJson({...raw,'learned':{'skill:unknown':0}});
  expect(()=>catalog.validateSaved(unknown),throwsFormatException);
  expect(()=>SkillCatalog.production.validateSaved(wrong),throwsFormatException);
  expect(()=>SkillCatalog([catalog.definitions.first,catalog.definitions.first]),throwsFormatException);
 });
 test('戦闘中は習得・装着・解除を変更しない',(){
  final w=WorldState(),s=SkillState();
  catalog.learn(w,s,'skill:a0');
  catalog.learn(w,s,'skill:p0');
  catalog.equip(w,s,'skill:a0');
  final stats=WorldStats.fromRanks(level:1,fitness:1,intelligence:1,discipline:1,creativity:1);
  WorldEngine().start(w,stats,'p01_main',now);
  final before=jsonEncode(s.toJson());
  expect(()=>catalog.learn(w,s,'skill:a1'),throwsStateError);
  expect(()=>catalog.equip(w,s,'skill:p0'),throwsStateError);
  expect(()=>catalog.unequip(w,s,'skill:a0'),throwsStateError);
  expect(jsonEncode(s.toJson()),before);
 });
 test('実ファイル：遅延保存中非公開・失敗再試行・再起動・外部復元',() async{
  final dir=await Directory.systemTemp.createTemp('skills-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,portableBackup:PortableBackup(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  final initial=await c.exportPortableBackup();
  final gen=c.restoreGeneration;
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=jsonEncode(c.state.toJson()),bytes=await primary.readAsString();
  store.entered=Completer<void>();store.gate=Completer<void>();store.fail=true;
  final failure=expectLater(c.learnWorldSkill('skill:a0',expectedGeneration:gen,expectedRevision:c.state.skills.revision),throwsStateError);
  await store.entered!.future;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  await expectLater(c.learnWorldSkill('skill:a1',expectedGeneration:gen,expectedRevision:c.state.skills.revision),throwsStateError);
  store.gate!.complete();
  await failure;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.gate=null;store.fail=false;
  await c.learnWorldSkill('skill:a0',expectedGeneration:gen,expectedRevision:c.state.skills.revision);
  await c.equipWorldSkill('skill:a0',expectedGeneration:gen,expectedRevision:c.state.skills.revision);
  final learned=jsonEncode(c.state.skills.toJson());
  store.fail=true;
  await expectLater(c.unequipWorldSkill('skill:a0',expectedGeneration:gen,expectedRevision:c.state.skills.revision),throwsStateError);
  expect(jsonEncode(c.state.skills.toJson()),learned);
  store.fail=false;
  final blocked=AppController(LocalStore(directory:dir),clockMs:()=>now);
  addTearDown(blocked.dispose);
  final committed=await primary.readAsString();
  await expectLater(blocked.initialize(),throwsFormatException);
  expect(await primary.readAsString(),committed);
  final restored=AppController(LocalStore(directory:dir),portableBackup:PortableBackup(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(jsonEncode(restored.state.skills.toJson()),learned);
  await expectLater(restored.learnWorldSkill('skill:a0',expectedGeneration:restored.restoreGeneration,expectedRevision:restored.state.skills.revision),throwsStateError);
  await expectLater(restored.equipWorldSkill('skill:a0',expectedGeneration:restored.restoreGeneration,expectedRevision:restored.state.skills.revision),throwsStateError);
  final previousGeneration=restored.restoreGeneration;
  await restored.importPortableBackup(initial);
  expect(restored.state.skills.learned,isEmpty);
  await expectLater(restored.learnWorldSkill('skill:a0',expectedGeneration:previousGeneration,expectedRevision:restored.state.skills.revision),throwsStateError);
  await restored.learnWorldSkill('skill:a0',expectedGeneration:restored.restoreGeneration,expectedRevision:restored.state.skills.revision);
  expect(restored.state.skills.learned['skill:a0'],0);
 });
 test('本番のスキル定義は空、実マスターと試験カタログの混用を拒否',() async{
  final dir=await Directory.systemTemp.createTemp('skills-master-');
  addTearDown(()=>dir.delete(recursive:true));
  final master=AbyssMaster.fromJson(File(AbyssMaster.assetPath).readAsStringSync());
  final c=AppController(LocalStore(directory:dir),skillCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  expect(()=>c.configureAbyssMaster(master),throwsFormatException);
  final prod=AppController(LocalStore(directory:dir),clockMs:()=>now);
  addTearDown(prod.dispose);
  await prod.initialize();
  expect(prod.skillDefinitions,isEmpty);
  await expectLater(prod.learnWorldSkill('skill:a0',expectedGeneration:prod.restoreGeneration,expectedRevision:prod.state.skills.revision),throwsStateError);
  expect(prod.state.skills.learned,isEmpty);
 });
}
