import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/screens/abyss_forge_screen.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_enhancement.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Store extends LocalStore {
 String? data;
 @override Future<AppStateData> load() async=>data==null?AppStateData.initial():AppStateData.fromJson(jsonDecode(data!) as Map<String,dynamic>);
 @override Future<void> save(AppStateData state) async {data=jsonEncode(state.toJson());}
}

void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const scaling=EnhancementScaling.proposed();
 final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:ring',name:'試験指輪',slot:EquipmentSlot.ring,rarity:EquipmentRarity.n,physical:1,magic:20,defense:3)]);
 final policy=EnhancementPolicy(const [EnhancementRecipe(rarity:EquipmentRarity.n,materialId:'item:iron',quantity:1,gold:10)]);
 test('強化補正は装備単位で切り捨て、基本性能と未装着装備に影響しない',(){
  final base=WorldStats.fromRanks(level:1,fitness:1,intelligence:1,discipline:1,creativity:1);
  final inv=AbyssInventory();
  final item=inv.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  for(var i=0;i<20;i++){inv.enhance(item.id,i);}
  expect(catalog.apply(base,inv,scaling:scaling).toJson(),base.toJson());
  inv.equip(item.id);
  final result=catalog.apply(base,inv,scaling:scaling);
  expect(result.physical,base.physical+2);
  expect(result.magic,base.magic+40);
  expect(result.defense,base.defense+6);
  expect(result.hp,base.hp);
  expect(result.physicalMax,base.physicalMax);
  expect(result.magicMax,base.magicMax);
  expect(result.crit,base.crit);
  expect(catalog.apply(base,inv).magic,base.magic+20);
  expect(scaling.apply(1,19),1);
  expect(scaling.apply(0,20),0);
  expect(scaling.apply(20,1),21);
 });
 test('強化済み装備の性能を次の戦闘に固定する',() async {
  final c=AppController(_Store(),equipmentCatalog:catalog,enhancementPolicy:policy,enhancementScaling:scaling);
  addTearDown(c.dispose);
  await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  c.state.world.gold=10;
  c.state.inventory.addStack('item:iron',1);
  await c.equipWorldItem(item.id);
  final before=c.worldStats.magic;
  await c.enhanceWorldItem(item.id,0);
  expect(c.worldStats.magic,before+1);
  await c.startWorldBattle('p01_main');
  expect(c.state.world.battle!.stats.magic,before+1);
  await expectLater(c.enhanceWorldItem(item.id,1),throwsStateError);
  expect(c.state.world.battle!.stats.magic,before+1);
 });
 test('マスター構成時に存在しない素材・異なる希少度・費用上限を拒否する',(){
  final raw=jsonDecode(File(AbyssMaster.assetPath).readAsStringSync()) as Map<String,dynamic>;
  final master=AbyssMaster.fromJson(jsonEncode(raw..['enabled']=true));
  for(final id in ['item:missing','item:alloy']){
   final c=AppController(_Store(),enhancementPolicy:EnhancementPolicy([EnhancementRecipe(rarity:EquipmentRarity.n,materialId:id,quantity:1,gold:10)]));
   addTearDown(c.dispose);
   expect(()=>c.configureAbyssMaster(master),throwsFormatException);
   expect(c.hasAbyssMaster,false);
  }
  final valid=AppController(_Store(),enhancementPolicy:policy);
  addTearDown(valid.dispose);
  valid.configureAbyssMaster(master);
  expect(valid.hasAbyssMaster,true);
  expect(()=>EnhancementPolicy(const [EnhancementRecipe(rarity:EquipmentRarity.n,materialId:'item:iron',quantity:1,gold:1000001)]),throwsFormatException);
 });
 testWidgets('無効レシピの鍛造画面では強化操作不可',(tester) async {
  final c=AppController(_Store(),equipmentCatalog:catalog);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  await tester.pumpWidget(MaterialApp(home:AbyssForgeScreen(controller:c)));
  expect(find.text('強化レシピ未承認'),findsOneWidget);
  expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'強化 +1')).onPressed,isNull);
 });
 testWidgets('有効なテストレシピで強化後に表示と資産を更新する',(tester) async {
  final c=AppController(_Store(),equipmentCatalog:catalog,enhancementPolicy:policy,enhancementScaling:scaling);
  addTearDown(c.dispose);
  await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  c.state.world.gold=10;
  c.state.inventory.addStack('item:iron',1);
  await tester.pumpWidget(MaterialApp(home:AbyssForgeScreen(controller:c)));
  expect(find.text('魔攻補正 20 → 21'),findsOneWidget);
  await tester.tap(find.widgetWithText(FilledButton,'強化 +1'));
  await tester.pumpAndSettle();
  expect(find.text('試験指輪 +1'),findsOneWidget);
  expect(find.text('所持G：0'),findsOneWidget);
  expect(find.text('魔攻補正 21 → 22'),findsOneWidget);
  expect(c.state.inventory.equipment[item.id]!.enhancement,1);
  expect(c.state.inventory.stacks,isEmpty);
  expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'強化 +2')).onPressed,isNull);
 });
}
