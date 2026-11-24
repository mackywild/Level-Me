import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';

void main() {
 late Directory directory;
 late LocalStore store;
 late File primary;
 late File backup;
 setUp(() async {
  directory=await Directory.systemTemp.createTemp('level-me-save-');
  store=LocalStore(directory:directory);
  primary=File('${directory.path}/level_me_state_v1.json');
  backup=File('${primary.path}.bak');
 });
 tearDown(() async {await directory.delete(recursive:true);});

 test('new install starts with initial data',() async {
  expect((await store.load()).totalExp,0);
  expect(await store.hasBackup(),false);
 });
 test('backup retains previous generation and identical saves do not rotate it',() async {
  final state=AppStateData.initial()..totalExp=10;
  await store.save(state);
  state.totalExp=20;
  await store.save(state);
  final previous=await backup.readAsString();
  await store.save(state);
  expect(await backup.readAsString(),previous);
  expect((await store.load()).totalExp,20);
  expect(await store.hasBackup(),true);
  await store.restoreBackup();
  expect((await store.load()).totalExp,10);
  expect(await backup.readAsString(),previous);
  expect(await directory.list().any((e)=>e.path.contains('.recovery-')),true);
 });
 test('empty or malformed primary is not silently replaced',() async {
  final state=AppStateData.initial();
  await store.save(state);
  state.totalExp=20;
  await store.save(state);
  final previous=await backup.readAsString();
  for(final invalid in ['', '{}', '{broken']){
   await primary.writeAsString(invalid);
   await expectLater(store.load(),throwsFormatException);
   await expectLater(store.save(state),throwsFormatException);
   expect(await primary.readAsString(),invalid);
   expect(await backup.readAsString(),previous);
  }
  await store.restoreBackup();
  expect((await store.load()).totalExp,0);
 });
 test('missing primary with backup requires explicit recovery',() async {
  final state=AppStateData.initial()..totalExp=10;
  await store.save(state);
  state.totalExp=20;
  await store.save(state);
  await primary.delete();
  await expectLater(store.load(),throwsStateError);
  await expectLater(store.save(state),throwsStateError);
  await store.restoreBackup();
  expect((await store.load()).totalExp,10);
 });
 test('concurrent saves serialize snapshots in request order',() async {
  final state=AppStateData.initial()..totalExp=10;
  final first=store.save(state);
  state.totalExp=20;
  final second=store.save(state);
  await Future.wait([first,second]);
  expect((await store.load()).totalExp,20);
  await store.restoreBackup();
  expect((await store.load()).totalExp,10);
 });
}
