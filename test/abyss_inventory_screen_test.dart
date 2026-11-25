import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/screens/abyss_inventory_screen.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_dismantle.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/world_catalog.dart';

class _Store extends LocalStore {
 String? data;
 Completer<void>? gate;
 bool fail=false;
 @override Future<AppStateData> load() async=>data==null?AppStateData.initial():AppStateData.fromJson(jsonDecode(data!) as Map<String,dynamic>);
 @override Future<void> save(AppStateData state) async {
  if(gate!=null)await gate!.future;
  if(fail)throw StateError('Simulated save failure');
  data=jsonEncode(state.toJson());
 }
}
void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:ring',name:'試験指輪',slot:EquipmentSlot.ring,rarity:EquipmentRarity.n)]);
 final policy=DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.n,materialId:'item:iron',quantity:1)]);
 testWidgets('本番無効の分解と検索・お気に入り・素材一覧',(tester) async {
  final c=AppController(_Store(),equipmentCatalog:catalog);
  addTearDown(c.dispose);
  await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  c.state.inventory.addStack('item:iron',3);
  await tester.pumpWidget(MaterialApp(home:AbyssInventoryScreen(controller:c)));
  expect(find.text('分解報酬未承認'),findsOneWidget);
  expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'分解')).onPressed,isNull);
  await tester.tap(find.widgetWithText(OutlinedButton,'お気に入り登録'));
  await tester.pumpAndSettle();
  expect(c.state.inventory.equipment[item.id]!.favorite,true);
  expect(find.text('お気に入り保護中'),findsOneWidget);
  await tester.enterText(find.byType(TextField),'不明');
  await tester.pumpAndSettle();
  expect(find.text('該当する装備なし'),findsOneWidget);
  await tester.enterText(find.byType(TextField),'');
  await tester.tap(find.text('素材・物資'));
  await tester.pumpAndSettle();
  expect(find.text('× 3'),findsOneWidget);
 });
 testWidgets('分解確認の取消・確定と保存失敗時の装備維持',(tester) async {
  final store=_Store();
  final c=AppController(store,equipmentCatalog:catalog,dismantlePolicy:policy);
  addTearDown(c.dispose);
  await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  await tester.pumpWidget(MaterialApp(home:AbyssInventoryScreen(controller:c)));
  await tester.tap(find.widgetWithText(FilledButton,'分解'));
  await tester.pumpAndSettle();
  expect(find.text('装備を分解しますか？'),findsOneWidget);
  expect(find.textContaining('この操作は取り消せません'),findsOneWidget);
  await tester.tap(find.text('キャンセル'));
  await tester.pumpAndSettle();
  expect(c.state.inventory.equipment.containsKey(item.id),true);
  store.fail=true;
  await tester.tap(find.widgetWithText(FilledButton,'分解'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('分解を確定'));
  await tester.pumpAndSettle();
  expect(c.state.inventory.equipment.containsKey(item.id),true);
  expect(c.state.inventory.stacks,isEmpty);
  expect(find.textContaining('分解できませんでした'),findsOneWidget);
  store.fail=false;
  await tester.tap(find.widgetWithText(FilledButton,'分解'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('分解を確定'));
  await tester.pumpAndSettle();
  expect(c.state.inventory.equipment,isEmpty);
  expect(c.state.inventory.stacks['item:iron'],1);
 });
 testWidgets('保存中に画面を再生成しても分解・保護操作を再実行できない',(tester) async {
  final store=_Store();
  final c=AppController(store,equipmentCatalog:catalog,dismantlePolicy:policy);
  addTearDown(c.dispose);
  await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  store.gate=Completer<void>();
  final pending=c.dismantleWorldItem(item.id,0);
  await tester.pumpWidget(MaterialApp(home:AbyssInventoryScreen(controller:c)));
  expect(c.inventoryBusy,true);
  expect(find.text('所持品処理中'),findsWidgets);
  expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'分解')).onPressed,isNull);
  expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton,'お気に入り登録')).onPressed,isNull);
  expect(c.state.inventory.equipment.containsKey(item.id),true);
  await tester.pumpWidget(MaterialApp(home:AbyssInventoryScreen(key:const ValueKey('reentry'),controller:c)));
  expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'分解')).onPressed,isNull);
  store.gate!.complete();
  await pending;
  await tester.pumpAndSettle();
  expect(c.inventoryBusy,false);
  expect(c.state.inventory.stacks['item:iron'],1);
  expect(find.text('該当する装備なし'),findsOneWidget);
 });
}
