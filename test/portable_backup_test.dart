import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/fe_progress_store.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';

void main() {
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
}
