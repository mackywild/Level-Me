import 'dart:io';
import 'dart:convert';
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
  primary=File('${directory.path}/level_me_state_v2.json');
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
 test('v0.3 migration leaves original file intact and ignores later old writes',() async {
  final legacy=File('${directory.path}/${LocalStore.legacyFileName}');
  final old=AppStateData.initial()..totalExp=55;
  final raw=jsonEncode(old.toJson()..remove('world'));
  await legacy.writeAsString(raw);
  final migrated=await store.load();
  expect(migrated.totalExp,55);
  migrated.world.gold=100;
  await store.save(migrated);
  expect(await legacy.readAsString(),raw);
  old.totalExp=99;
  await legacy.writeAsString(jsonEncode(old.toJson()..remove('world')));
  expect((await store.load()).world.gold,100);
  expect((await store.load()).totalExp,55);
 });
 test('interrupted migration before marker retries from unchanged legacy data',() async {
  final legacy=File('${directory.path}/${LocalStore.legacyFileName}');
  final raw=jsonEncode((AppStateData.initial()..totalExp=55).toJson()..remove('world'));
  await legacy.writeAsString(raw);
  final staged=File('${primary.path}${LocalStore.initialSuffix}');
  await staged.writeAsString('{partial');
  final restarted=LocalStore(directory:directory);
  final recovered=await restarted.load();
  expect(recovered.totalExp,55);
  await restarted.save(recovered);
  expect((await restarted.load()).totalExp,55);
  expect(await legacy.readAsString(),raw);
  expect(await staged.exists(),false);
  expect(await File('${primary.path}${LocalStore.markerSuffix}').exists(),true);
 });
 test('interrupted initial publication after marker promotes complete staging',() async {
  final legacy=File('${directory.path}/${LocalStore.legacyFileName}');
  await legacy.writeAsString(jsonEncode((AppStateData.initial()..totalExp=55).toJson()..remove('world')));
  final staged=File('${primary.path}${LocalStore.initialSuffix}');
  final state=AppStateData.initial()..totalExp=80;
  state.world.gold=40;
  await staged.writeAsString(jsonEncode(state.toJson()),flush:true);
  await File('${primary.path}${LocalStore.markerSuffix}').writeAsString('v2',flush:true);
  final restarted=LocalStore(directory:directory);
  expect((await restarted.load()).totalExp,80);
  expect((await restarted.load()).world.gold,40);
  expect(await primary.exists(),true);
  expect(await staged.exists(),false);
 });
 test('established v2 missing must not fall back to legacy',() async {
  final legacy=File('${directory.path}/${LocalStore.legacyFileName}');
  await legacy.writeAsString(jsonEncode((AppStateData.initial()..totalExp=55).toJson()..remove('world')));
  final state=AppStateData.initial()..totalExp=80;
  await store.save(state);
  await primary.delete();
  final restarted=LocalStore(directory:directory);
  await expectLater(restarted.load(),throwsStateError);
  await expectLater(restarted.save(state),throwsStateError);
  expect(await primary.exists(),false);
  expect(await restarted.hasBackup(),false);
 });
 test('regular recovery evidence blocks automatic legacy migration',() async {
  final legacy=File('${directory.path}/${LocalStore.legacyFileName}');
  await legacy.writeAsString(jsonEncode(AppStateData.initial().toJson()..remove('world')));
  final staged=File('${primary.path}${LocalStore.initialSuffix}');
  await staged.writeAsString('partial');
  final regular=File('${primary.path}.tmp');
  await regular.writeAsString('unfinished regular save');
  await expectLater(store.load(),throwsStateError);
  expect(await regular.readAsString(),'unfinished regular save');
  expect(await staged.readAsString(),'partial');
 });
 test('invalid committed staging is preserved and never replaced by legacy',() async {
  final legacy=File('${directory.path}/${LocalStore.legacyFileName}');
  await legacy.writeAsString(jsonEncode(AppStateData.initial().toJson()..remove('world')));
  final staged=File('${primary.path}${LocalStore.initialSuffix}');
  await staged.writeAsString('{partial');
  await File('${primary.path}${LocalStore.markerSuffix}').writeAsString('v2');
  await expectLater(store.load(),throwsFormatException);
  expect(await staged.readAsString(),'{partial');
  expect(await primary.exists(),false);
 });
 test('fresh install retries incomplete initial write before marker',() async {
  final staged=File('${primary.path}${LocalStore.initialSuffix}');
  await staged.writeAsString('partial');
  final state=await store.load();
  expect(state.totalExp,0);
  await store.save(state);
  expect(await primary.exists(),true);
  expect(await staged.exists(),false);
 });
}
