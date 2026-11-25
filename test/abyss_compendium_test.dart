import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';
import 'package:level_me/screens/abyss_compendium_screen.dart';
import 'package:level_me/world/abyss_compendium.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/world_catalog.dart';
import 'helpers/memory_local_store.dart';

void main(){
 const now=1700000000000;
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final raw=File(AbyssMaster.assetPath).readAsStringSync();
 AbyssMaster master({required bool enabled}){
  final j=jsonDecode(raw) as Map<String,dynamic>;
  j['enabled']=enabled;
  return AbyssMaster.fromJson(jsonEncode(j));
 }
 test('発見記録と所持数は独立し、消費・分解後も発見を維持する',(){
  final catalog=CompendiumCatalog(const [
   CompendiumDefinition(id:'equipment:test',name:'試験装備',category:CompendiumCategory.equipment,rarity:EquipmentRarity.n,description:'試験'),
   CompendiumDefinition(id:'item:test',name:'試験物資',category:CompendiumCategory.material,rarity:EquipmentRarity.r,description:'試験'),
   CompendiumDefinition(id:'item:hidden',name:'秘密',category:CompendiumCategory.material,rarity:EquipmentRarity.ssr,description:'秘密性能'),
  ]);
  final inv=AbyssInventory();
  final a=inv.addEquipment('equipment:test',EquipmentSlot.head,EquipmentRarity.n);
  final b=inv.addEquipment('equipment:test',EquipmentSlot.head,EquipmentRarity.n);
  inv.addStack('item:test',3);
  inv.addStack('item:unknown',1);
  final before=jsonEncode(inv.toJson());
  final view=catalog.view(inv);
  expect(view.discoveredCount,2);
  expect(view.totalCount,3);
  expect(view.entries.first.owned,2);
  expect(view.entries[1].owned,3);
  expect(view.entries.last.definition,isNull);
  expect(view.entries.last.owned,0);
  expect(()=>view.entries.clear(),throwsUnsupportedError);
  expect(jsonEncode(inv.toJson()),before);
  inv.removeEquipment(a.id,0);
  inv.removeEquipment(b.id,0);
  inv.removeStack('item:test',3);
  final restored=AbyssInventory.fromJson(jsonDecode(jsonEncode(inv.toJson())) as Map<String,dynamic>);
  final after=catalog.view(restored);
  expect(after.discoveredCount,2);
  expect(after.entries.take(2).every((e)=>e.owned==0&&e.discovered),true);
 });
 test('公開済み装備と素材のみを母数とし、未承認・未知IDは集計しない',(){
  final inv=AbyssInventory();
  inv.addStack('item:iron',1);
  inv.addStack('item:purification',1);
  inv.addStack('item:buff_lethal_protection',1);
  inv.addStack('item:recovery_all',1);
  inv.addStack('item:unknown',1);
  expect(master(enabled:false).compendium.view(inv).totalCount,0);
  final view=master(enabled:true).compendium.view(inv);
  expect(view.totalCount,32);
  expect(view.discoveredCount,1);
  expect(view.entries.first.definition!.id,'item:iron');
  expect(view.entries.skip(1).every((e)=>e.definition==null),true);
 });
 test('実ファイル保存と再起動・外部バックアップ復元で発見記録を反映',() async{
  final dir=await Directory.systemTemp.createTemp('compendium-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=LocalStore(directory:dir);
  final c=AppController(store,portableBackup:PortableBackup(directory:dir),loadAbyssMaster:() async=>master(enabled:true),clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  final initial=await c.exportPortableBackup();
  c.state.inventory.addStack('item:iron',1);
  c.state.inventory.removeStack('item:iron',1);
  await store.save(c.state);
  final bytes=await File('${dir.path}/${LocalStore.fileName}').readAsString();
  expect(c.compendiumView.discoveredCount,1);
  expect(c.compendiumView.entries.first.owned,0);
  expect(await File('${dir.path}/${LocalStore.fileName}').readAsString(),bytes);
  final restored=AppController(LocalStore(directory:dir),portableBackup:PortableBackup(directory:dir),loadAbyssMaster:() async=>master(enabled:true),clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.compendiumView.discoveredCount,1);
  await restored.importPortableBackup(initial);
  expect(restored.compendiumView.discoveredCount,0);
 });
 testWidgets('匿名枠と検索結果から未発見情報を公開しない',(tester) async{
  final c=AppController(MemoryLocalStore(),loadAbyssMaster:() async=>master(enabled:true),clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.inventory.addStack('item:iron',1);
  c.state.inventory.removeStack('item:iron',1);
  await tester.pumpWidget(MaterialApp(home:AbyssCompendiumScreen(controller:c)));
  final ironCard=find.byKey(const ValueKey('item:iron'));
  final ironTitle=find.descendant(of:ironCard,matching:find.text('鉄'));
  expect(find.text('発見済み 1 / 32'),findsOneWidget);
  expect(ironCard,findsOneWidget);
  expect(ironTitle,findsOneWidget);
  expect(find.textContaining('現在未所持'),findsOneWidget);
  expect(find.text('布の頭巾'),findsNothing);
  expect(find.text('？？？'),findsWidgets);
  await tester.enterText(find.byKey(const ValueKey('compendium-search')),'cloth_cap');
  await tester.pumpAndSettle();
  expect(find.text('該当する図鑑項目なし'),findsOneWidget);
  expect(ironCard,findsNothing);
  expect(find.text('？？？'),findsNothing);
  await tester.enterText(find.byKey(const ValueKey('compendium-search')),'鉄');
  await tester.pumpAndSettle();
  expect(ironCard,findsOneWidget);
  expect(ironTitle,findsOneWidget);
  expect(find.text('？？？'),findsNothing);
  expect(find.text('該当する図鑑項目なし'),findsNothing);
  expect(find.text('発見済み 1 / 32'),findsOneWidget);
 });
}
