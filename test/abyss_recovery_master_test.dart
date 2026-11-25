import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/screens/abyss_inventory_screen.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_consumable.dart';
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
 Map<String,dynamic> raw()=>jsonDecode(File(AbyssMaster.assetPath).readAsStringSync()) as Map<String,dynamic>;
 const item=RecoveryItem(id:'item:hp_test',name:'試験回復薬',target:RecoveryTarget.hp,percent:20);
 final catalog=ConsumableCatalog(const [item]);
 test('実マスターの回復候補9種は召喚マスター有効時も非公開',(){
  final root=raw();
  expect(root['recoveryEnabled'],false);
  expect((root['recovery'] as List).length,9);
  for(final enabled in [false,true]){
   root['enabled']=enabled;
   final master=AbyssMaster.fromJson(jsonEncode(root));
   expect(master.recovery.items,isEmpty);
   for(final row in root['recovery'] as List){
    expect(master.supply(row['id'] as String),isNull);
   }
  }
 });
 test('回復候補の素材ID衝突・重複・区分・割合・無断有効化を拒否',(){
  for(final change in <void Function(Map<String,dynamic>)>[
   (root){root['recoveryEnabled']=true;},
   (root){(root['recovery'] as List).first['id']='item:iron';},
   (root){final rows=root['recovery'] as List;rows.add(rows.first);},
   (root){(root['recovery'] as List).first['category']='material';},
   (root){(root['recovery'] as List).first['percent']=101;},
  ]){
   final root=raw();
   change(root);
   expect(()=>AbyssMaster.fromJson(jsonEncode(root)),throwsFormatException);
  }
 });
 test('極端な最大値でも回復量の乗算があふれない',(){
  final s=AppStateData.initial();
  s.world.hp=0;
  s.inventory.addStack(item.id,1);
  const maximum=0x7fffffffffffffff;
  const stats=WorldStats(hp:maximum,physical:1,magic:1,defense:0,physicalMax:1,magicMax:1,crit:0);
  final before=jsonEncode(s.toJson());
  expect(catalog.preview(world:s.world,stats:stats,inventory:s.inventory,id:item.id,expectedSequence:0),maximum~/5);
  expect(jsonEncode(s.toJson()),before);
 });
 testWidgets('素材と回復品の区別、確認取消・確定・満タン拒否',(tester) async {
  final c=AppController(_Store(),consumableCatalog:catalog);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.hp=80;
  c.state.world.hpAt=DateTime.now().millisecondsSinceEpoch;
  c.state.inventory.addStack(item.id,2);
  c.state.inventory.addStack('item:iron',1);
  await tester.pumpWidget(MaterialApp(home:AbyssInventoryScreen(controller:c)));
  await tester.tap(find.text('素材・物資'));
  await tester.pumpAndSettle();
  expect(find.widgetWithText(FilledButton,'使用'),findsOneWidget);
  await tester.tap(find.widgetWithText(FilledButton,'使用'));
  await tester.pumpAndSettle();
  expect(find.text('回復アイテムを使用しますか？'),findsOneWidget);
  await tester.tap(find.text('キャンセル'));
  await tester.pumpAndSettle();
  expect(c.state.world.hp,80);
  await tester.tap(find.widgetWithText(FilledButton,'使用'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('使用を確定'));
  await tester.pumpAndSettle();
  expect(c.state.world.hp,100);
  expect(c.state.inventory.stacks[item.id],1);
  expect(c.state.inventory.stacks['item:iron'],1);
  expect(find.text('回復不要'),findsOneWidget);
  expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton,'使用')).onPressed,isNull);
 });
}
