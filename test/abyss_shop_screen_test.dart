import 'dart:async';
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
 testWidgets('魔晶石支払の保存失敗・再入場・残高更新と戦闘中拒否',(tester) async {
  final store=_Store();
  const crystalOffer=ShopOffer(id:'shop:alloy',materialId:'item:alloy',currency:ShopCurrency.magicCrystals,price:3,quantity:1);
  final c=AppController(store,shopCatalog:ShopCatalog(const [crystalOffer]));
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.magicCrystals=6;
  await tester.pumpWidget(MaterialApp(home:AbyssShopScreen(controller:c)));
  await tester.tap(find.widgetWithText(FilledButton,'購入'));
  await tester.pumpAndSettle();
  store.fail=true;
  await tester.tap(find.text('購入を確定'));
  await tester.pumpAndSettle();
  expect(find.textContaining('購入できませんでした'),findsOneWidget);
  expect(c.state.world.magicCrystals,6);
  expect(c.state.inventory.stacks,isEmpty);
  store.fail=false;
  store.gate=Completer<void>();
  final pending=c.purchaseWorldMaterial(crystalOffer.id,0,expectedGeneration:c.restoreGeneration);
  await tester.pumpWidget(MaterialApp(home:AbyssShopScreen(key:const ValueKey('reentry'),controller:c)));
  expect(find.text('所持品処理中'),findsWidgets);
  expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'購入')).onPressed,isNull);
  expect(find.text('魔晶石：6'),findsOneWidget);
  store.gate!.complete();
  await pending;
  store.gate=null;
  await tester.pumpAndSettle();
  expect(find.text('魔晶石：3'),findsOneWidget);
  expect(c.state.inventory.stacks['item:alloy'],1);
  await c.startWorldBattle('p01_main');
  await tester.pumpAndSettle();
  expect(find.text('戦闘中は購入できません'),findsOneWidget);
  expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'購入')).onPressed,isNull);
 });
 testWidgets('確認中に取引番号が変化した場合は確定を拒否する',(tester) async {
  final c=AppController(_Store(),shopCatalog:ShopCatalog(const [offer]));
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.gold=20;
  await tester.pumpWidget(MaterialApp(home:AbyssShopScreen(controller:c)));
  await tester.tap(find.widgetWithText(FilledButton,'購入'));
  await tester.pumpAndSettle();
  await c.purchaseWorldMaterial(offer.id,0,expectedGeneration:c.restoreGeneration);
  await tester.tap(find.text('購入を確定'));
  await tester.pumpAndSettle();
  expect(c.state.world.gold,10);
  expect(c.state.world.shopSequence,1);
  expect(c.state.inventory.stacks['item:iron'],2);
  expect(find.textContaining('購入できませんでした'),findsOneWidget);
 });
}
