import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/screens/abyss_shop_screen.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_dismantle.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_shop.dart';
import 'package:level_me/world/world_catalog.dart';

class _Store extends LocalStore {
 String? data;
 @override Future<AppStateData> load() async=>data==null?AppStateData.initial():AppStateData.fromJson(jsonDecode(data!) as Map<String,dynamic>);
 @override Future<void> save(AppStateData state) async {data=jsonEncode(state.toJson());}
}

void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const offer=ShopOffer(id:'shop:iron',materialId:'item:iron',currency:ShopCurrency.gold,price:10,quantity:2);
 testWidgets('未承認商品は購入できない',(tester) async {
  final c=AppController(_Store());
  addTearDown(c.dispose);
  await c.initialize();
  await tester.pumpWidget(MaterialApp(home:AbyssShopScreen(controller:c)));
  expect(find.text('販売商品は未承認です'),findsOneWidget);
  expect(find.widgetWithText(FilledButton,'購入'),findsNothing);
 });
 testWidgets('購入確認の取消と確定・残高不足',(tester) async {
  final c=AppController(_Store(),shopCatalog:ShopCatalog(const [offer]));
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.gold=10;
  await tester.pumpWidget(MaterialApp(home:AbyssShopScreen(controller:c)));
  await tester.tap(find.widgetWithText(FilledButton,'購入'));
  await tester.pumpAndSettle();
  expect(find.text('購入を確認'),findsOneWidget);
  await tester.tap(find.text('キャンセル'));
  await tester.pumpAndSettle();
  expect(c.state.world.gold,10);
  await tester.tap(find.widgetWithText(FilledButton,'購入'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('購入を確定'));
  await tester.pumpAndSettle();
  expect(c.state.world.gold,0);
  expect(c.state.inventory.stacks['item:iron'],2);
  expect(find.text('所持G：0'),findsOneWidget);
  expect(find.text('通貨残高不足'),findsOneWidget);
 });
 test('魔晶石のみの分解報酬は一括保存される',() async {
  final store=_Store();
  final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:ring',name:'指輪',slot:EquipmentSlot.ring,rarity:EquipmentRarity.n)]);
  final c=AppController(store,equipmentCatalog:catalog,dismantlePolicy:DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.n,materialId:'',quantity:0,magicCrystals:3)]));
  addTearDown(c.dispose);
  await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  await c.dismantleWorldItem(item.id,0);
  expect(c.state.world.magicCrystals,3);
  expect(c.state.inventory.stacks,isEmpty);
  expect(c.state.inventory.equipment,isEmpty);
  expect((await store.load()).world.magicCrystals,3);
  await expectLater(c.dismantleWorldItem(item.id,0),throwsStateError);
  expect(c.state.world.magicCrystals,3);
 });
}
