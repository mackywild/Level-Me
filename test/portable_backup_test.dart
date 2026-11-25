import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/services/fe_progress_store.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';

void main() {
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 late Directory dir;
 late LocalStore player;
 late FeProgressStore fe;
 late PortableBackup backup;
 File file(String name)=>File('${dir.path}/$name');
 setUp(() async {
  dir=await Directory.systemTemp.createTemp('level-me-backup-test-');
  player=LocalStore(directory:dir);
  fe=FeProgressStore(directory:dir);
  backup=PortableBackup(directory:dir);
 });
 tearDown(() async {await dir.delete(recursive:true);});

 test('Concurrent writes across FE stores preserve every answer',() async {
  final second=FeProgressStore(directory:dir);
  await Future.wait(List.generate(40,(i)=>(i.isEven?fe:second).record('q',i.isEven)));
  expect((await fe.load())['q'],List.generate(40,(i)=>i.isEven));
 });
 test('Concurrent flag operations preserve distinct IDs and ordering',() async {
  final second=FeProgressStore(directory:dir);
  await Future.wait(List.generate(20,(i)=>(i.isEven?fe:second).setFlag('q$i',true)));
  await Future.wait([fe.setFlag('q0',false),second.setFlag('q0',true),fe.setFlag('q1',false)]);
  expect(await fe.loadFlags(),{for(var i=0;i<20;i++)if(i!=1)'q$i'});
 });
 test('Corrupt FE progress is not replaced',() async {
  await fe.record('q',true);
  await fe.record('q',false);
  final before=await file('${PortableBackup.progressName}.bak').readAsString();
  await file(PortableBackup.progressName).writeAsString('not json');
  await expectLater(fe.record('q',true),throwsFormatException);
  expect(await file(PortableBackup.progressName).readAsString(),'not json');
  expect(await file('${PortableBackup.progressName}.bak').readAsString(),before);
 });
 test('Portable round trip restores player, learning and flags together',() async {
  final initial=AppStateData.initial()..totalExp=50;
  await player.save(initial);
  await fe.record('q',true);
  await fe.setFlag('q',true);
  final raw=await backup.export();
  initial.totalExp=90;
  await player.save(initial);
  await fe.record('q',false);
  await fe.setFlag('q',false);
  await backup.restore(raw);
  expect((await player.load()).totalExp,50);
  expect(await fe.load(),{'q':[true]});
  expect(await fe.loadFlags(),{'q'});
  expect(await file(PortableBackup.journalName).exists(),false);
  expect(await dir.list().any((e)=>e.path.contains('level_me_before_import_')),true);
 });
 test('Reject malformed or unknown version without overwriting',() async {
  await player.save(AppStateData.initial());
  final raw=await backup.export();
  final original=await file(PortableBackup.playerName).readAsString();
  final invalid=jsonDecode(raw) as Map<String,dynamic>;
  invalid['version']=999;
  await expectLater(backup.restore(jsonEncode(invalid)),throwsFormatException);
  expect(await file(PortableBackup.playerName).readAsString(),original);
  expect(await file(PortableBackup.journalName).exists(),false);
 });
 test('Interrupted restore resumes from journal before loading',() async {
  final state=AppStateData.initial()..totalExp=70;
  await player.save(state);
  await fe.record('q',true);
  final raw=await backup.export();
  state.totalExp=100;
  await player.save(state);
  await fe.record('q',false);
  await file(PortableBackup.journalName).writeAsString(raw,flush:true);
  await backup.resumePendingRestore();
  expect((await player.load()).totalExp,70);
  expect(await fe.load(),{'q':[true]});
  expect(await file(PortableBackup.journalName).exists(),false);
  await backup.resumePendingRestore();
  expect((await player.load()).totalExp,70);
 });
 test('v1 external backup is migrated to v2 without altering legacy file',() async {
  final old=AppStateData.initial()..totalExp=120;
  final raw=jsonEncode({'format':'level-me-backup','version':1,'files':{PortableBackup.legacyPlayerName:old.toJson()..remove('world'),PortableBackup.progressName:{'q':[true]},PortableBackup.flagsName:['q']}});
  await backup.restore(raw);
  expect((await player.load()).totalExp,120);
  expect(await fe.loadFlags(),{'q'});
  expect(jsonDecode(await backup.export())['version'],2);
 });
 test('portable backup roundtrip retains active world battle',() async {
  final state=AppStateData.initial();
  final engine=WorldEngine();
  final stats=WorldStats.fromRanks(level:1,fitness:1,intelligence:1,discipline:1,creativity:1);
  engine.start(state.world,stats,'p01_main',10000000);
  await player.save(state);
  final raw=await backup.export();
  engine.act(state.world,WorldCommand.claw,1,1,10000000);
  await player.save(state);
  await backup.restore(raw);
  final restored=await player.load();
  expect(restored.world.battle!.encounterId,'p01_main');
  expect(restored.world.battle!.turn,1);
  expect(restored.world.gold,0);
 });
 test('portable inventory restores stacks, equipment, discovery, sequence and currencies',() async {
  final state=AppStateData.initial()..totalExp=500..gachaTickets=4;
  state.world.gold=123;
  state.world.summonTickets=3;
  state.world.supplyTickets=2;
  state.world.lifespan=BigInt.from(365);
  state.inventory.addStack('test_material',5);
  state.inventory.addStack('test_consumed',1);
  state.inventory.removeStack('test_consumed',1);
  state.inventory.addEquipment('test_ring',EquipmentSlot.ring,EquipmentRarity.r);
  state.inventory.addEquipment('test_ring',EquipmentSlot.ring,EquipmentRarity.r);
  final expected=jsonEncode(state.inventory.toJson());
  await player.save(state);
  await fe.record('q',true);
  await fe.setFlag('q',true);
  final raw=await backup.export();
  state.inventory.removeStack('test_material',5);
  state.inventory.addEquipment('test_ring',EquipmentSlot.ring,EquipmentRarity.r);
  state.world.gold=999;
  await player.save(state);
  await fe.record('q',false);
  await fe.setFlag('q',false);
  await backup.restore(raw);
  final restored=await LocalStore(directory:dir).load();
  expect(jsonEncode(restored.inventory.toJson()),expected);
  expect(restored.inventory.stacks['test_material'],5);
  expect(restored.inventory.equipment.length,2);
  expect(restored.inventory.discovered,contains('test_consumed'));
  expect(restored.inventory.stacks.containsKey('test_consumed'),false);
  expect(restored.totalExp,500);
  expect(restored.gachaTickets,4);
  expect(restored.world.gold,123);
  expect(restored.world.summonTickets,3);
  expect(restored.world.supplyTickets,2);
  expect(restored.world.lifespan,BigInt.from(365));
  expect(await fe.load(),{'q':[true]});
  expect(await fe.loadFlags(),{'q'});
  expect(restored.inventory.addEquipment('test_ring',EquipmentSlot.ring,EquipmentRarity.r).id,'eq_3');
  await player.save(restored);
  expect((await player.load()).inventory.equipment.length,3);
 });
 test('invalid inventory import leaves all existing files and recovery state unchanged',() async {
  final state=AppStateData.initial()..totalExp=100;
  state.inventory.addStack('test_material',5);
  state.inventory.addEquipment('test_ring',EquipmentSlot.ring,EquipmentRarity.r);
  await player.save(state);
  state.world.gold=123;
  await player.save(state);
  await fe.record('q',true);
  await fe.record('q',false);
  await fe.setFlag('q',true);
  final raw=await backup.export();
  final before=<String,String>{};
  for(final name in PortableBackup.names){
   for(final suffix in ['', '.bak']){
    final f=file('$name$suffix');
    if(await f.exists())before['$name$suffix']=await f.readAsString();
   }
  }
  final entries=(await dir.list().map((e)=>e.path).toList())..sort();
  for(final invalidVersion in [true,false]){
   final envelope=jsonDecode(raw) as Map<String,dynamic>;
   final files=envelope['files'] as Map<String,dynamic>;
   final imported=files[PortableBackup.playerName] as Map<String,dynamic>;
   imported['totalExp']=999;
   final inventory=imported['inventory'] as Map<String,dynamic>;
   if(invalidVersion){inventory['version']=999;}else{(inventory['stacks'] as Map)['test_material']=0;}
   await expectLater(backup.restore(jsonEncode(envelope)),throwsFormatException);
   for(final entry in before.entries){
    expect(await file(entry.key).readAsString(),entry.value);
   }
   expect((await dir.list().map((e)=>e.path).toList())..sort(),entries);
   expect(await file(PortableBackup.journalName).exists(),false);
  }
  final restored=await player.load();
  expect(restored.totalExp,100);
  expect(restored.world.gold,123);
  expect(restored.inventory.stacks['test_material'],5);
 });
 test('controller rejects incompatible equipped masters before touching files or readiness',() async {
  final catalog=EquipmentCatalog(const [
   EquipmentDefinition(id:'equipment:ring',name:'Ring',slot:EquipmentSlot.ring,rarity:EquipmentRarity.r,physical:5,magic:2,defense:1),
   EquipmentDefinition(id:'equipment:head',name:'Head',slot:EquipmentSlot.head,rarity:EquipmentRarity.sr,physical:3,magic:4,defense:6),
  ]);
  final controller=AppController(player,portableBackup:backup,equipmentCatalog:catalog);
  addTearDown(controller.dispose);
  await controller.initialize();
  final initial=controller.state;
  final base=controller.worldStats;
  await fe.record('q',true);
  await fe.setFlag('q',true);
  final raw=await controller.exportPortableBackup();
  final original=jsonEncode(initial.toJson());
  final before=<String,String>{};
  for(final name in PortableBackup.names){
   for(final suffix in ['', '.bak']){
    final f=file('$name$suffix');
    if(await f.exists())before['$name$suffix']=await f.readAsString();
   }
  }
  final paths=(await dir.list().map((e)=>e.path).toList())..sort();
  for(final variant in [0,1,2]){
   final imported=AppStateData.initial()..totalExp=999;
   final item=imported.inventory.addEquipment(variant==0?'equipment:missing':'equipment:ring',variant==1?EquipmentSlot.head:EquipmentSlot.ring,variant==2?EquipmentRarity.ssr:EquipmentRarity.r);
   imported.inventory.equip(item.id);
   final envelope=jsonDecode(raw) as Map<String,dynamic>;
   (envelope['files'] as Map)[PortableBackup.playerName]=imported.toJson();
   await expectLater(controller.importPortableBackup(jsonEncode(envelope)),throwsStateError);
   expect(controller.ready,true);
   expect(identical(controller.state,initial),true);
   expect(jsonEncode(controller.state.toJson()),original);
   for(final entry in before.entries){
    expect(await file(entry.key).readAsString(),entry.value);
   }
   expect((await dir.list().map((e)=>e.path).toList())..sort(),paths);
  }
  final valid=AppStateData.fromJson(jsonDecode(original) as Map<String,dynamic>);
  final ring=valid.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.r);
  final head=valid.inventory.addEquipment('equipment:head',EquipmentSlot.head,EquipmentRarity.sr);
  valid.inventory.equip(ring.id);
  valid.inventory.equip(head.id);
  final envelope=jsonDecode(raw) as Map<String,dynamic>;
  (envelope['files'] as Map)[PortableBackup.playerName]=valid.toJson();
  await controller.importPortableBackup(jsonEncode(envelope));
  expect(controller.ready,true);
  expect(controller.state.inventory.equipped.length,2);
  expect(controller.worldStats.physical,base.physical+8);
  expect(controller.worldStats.magic,base.magic+6);
  expect(controller.worldStats.defense,base.defense+7);
  expect((await player.load()).inventory.equipped,valid.inventory.equipped);
 });
 test('incompatible local backup and pending journal are preserved without publication',() async {
  final controller=AppController(player,portableBackup:backup);
  addTearDown(controller.dispose);
  await controller.initialize();
  final original=await file(PortableBackup.playerName).readAsString();
  final raw=await backup.export();
  final invalid=AppStateData.initial();
  final item=invalid.inventory.addEquipment('equipment:missing',EquipmentSlot.ring,EquipmentRarity.r);
  invalid.inventory.equip(item.id);
  final badPlayer=jsonEncode(invalid.toJson());
  await file('${PortableBackup.playerName}.bak').writeAsString(badPlayer);
  expect(await controller.hasBackup(),false);
  await expectLater(controller.restoreBackup(),throwsStateError);
  expect(controller.ready,true);
  expect(await file(PortableBackup.playerName).readAsString(),original);
  expect(await file('${PortableBackup.playerName}.bak').readAsString(),badPlayer);
  final envelope=jsonDecode(raw) as Map<String,dynamic>;
  (envelope['files'] as Map)[PortableBackup.playerName]=invalid.toJson();
  final journal=jsonEncode(envelope);
  await file(PortableBackup.journalName).writeAsString(journal);
  await expectLater(controller.initialize(),throwsStateError);
  expect(controller.ready,false);
  expect(await file(PortableBackup.journalName).readAsString(),journal);
  expect(await file(PortableBackup.playerName).readAsString(),original);
  expect(await file('${PortableBackup.playerName}.bak').readAsString(),badPlayer);
 });
}
