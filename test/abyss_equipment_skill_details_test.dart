import 'dart:convert';
import 'dart:io';
import 'package:level_me/screens/equipment_skill_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/screens/abyss_inventory_screen.dart';
import 'package:level_me/screens/abyss_forge_screen.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_equipment_skill_master.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/world_catalog.dart';

class _Store extends LocalStore {
 String? backup;
 @override Future<void> restoreBackup() async {data=backup;}
 String? data;
 int saves=0;
 @override Future<AppStateData> load() async=>data==null?AppStateData.initial():AppStateData.fromJson(jsonDecode(data!) as Map<String,dynamic>);
 @override Future<void> save(AppStateData state) async {saves++;data=jsonEncode(state.toJson());}
}
void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:sword',name:'試験剣',slot:EquipmentSlot.ring,rarity:EquipmentRarity.gr)]);
 final master=EquipmentSkillMaster(const [
  EquipmentSkillMasterEntry(id:'equipment_skill:extra',rarity:EquipmentSkillRarity.ultraRare,pool:EquipmentSkillPool.special,effect:EquipmentEffect.rewardPercent,perLevel:125),
 ]);
 testWidgets('所持品・鍛造で同じ確定履歴、旧枠、未解放と部分接続を表示し書き込まない',(tester) async {
  final store=_Store();
  final c=AppController(store,equipmentCatalog:catalog,equipmentSkillMaster:master);
  addTearDown(c.dispose);await c.initialize();
  final inv=c.state.inventory;
  final item=inv.addEquipment('equipment:sword',EquipmentSlot.ring,EquipmentRarity.gr);
  inv.addStack('item:iron',6);
  for(var i=0;i<5;i++){inv.enhanceWithMaterial(item.id,i,'item:iron',1);}
  inv.activateEquipmentSkills(7);
  inv.enhanceWithMaterial(item.id,5,'item:iron',1,skillGrant:const StoredEquipmentSkill(milestone:6,skillId:'equipment_skill:extra',level:7));
  final before=jsonEncode(c.state.toJson()),saves=store.saves;
  for(final screen in [AbyssInventoryScreen(controller:c),AbyssForgeScreen(controller:c)]){
   await tester.pumpWidget(MaterialApp(home:screen));
   await tester.ensureVisible(find.text('スキル詳細'));
   await tester.tap(find.text('スキル詳細'));await tester.pumpAndSettle();
   expect(find.text('装備スキル詳細'),findsOneWidget);
   expect(find.text('確定済み 1 / 6 枠'),findsOneWidget);
   expect(find.text('+3 旧枠・抽選対象外'),findsOneWidget);
   expect(find.text('+6 確定済み：Lv7'),findsOneWidget);
   expect(find.text('超希少 / 報酬補正 8.75%'),findsOneWidget);
   expect(find.text('報酬補正：G接続済み・素材ドロップ未接続'),findsOneWidget);
   expect(find.text('+9 未解放'),findsOneWidget);
   expect(find.text('未装着のため戦闘効果は適用されません'),findsOneWidget);
   await tester.tap(find.text('閉じる'));await tester.pumpAndSettle();
  }
  expect(jsonEncode(c.state.toJson()),before);expect(store.saves,saves);
 });
 testWidgets('RV-194: 同一IDの復元後は開いていた詳細を無効化する',(tester) async {
  final store=_Store();
  final c=AppController(store,equipmentCatalog:catalog,equipmentSkillMaster:master,clockMs:()=>1700000000000);
  addTearDown(c.dispose);await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:sword',EquipmentSlot.ring,EquipmentRarity.gr);
  await store.save(c.state);store.backup=store.data;
  await tester.pumpWidget(MaterialApp(home:AbyssInventoryScreen(controller:c)));
  await tester.ensureVisible(find.text('スキル詳細'));
  await tester.tap(find.text('スキル詳細'));await tester.pumpAndSettle();
  expect(tester.widget<EquipmentSkillDetails>(find.byType(EquipmentSkillDetails)).generation,0);
  await c.restoreBackup();await tester.pumpAndSettle();
  expect(c.state.inventory.equipment[item.id]!.masterId,item.masterId);
  expect(find.text('装備情報が更新されました。詳細を開き直してください。'),findsOneWidget);
  await tester.tap(find.text('閉じる'));await tester.pumpAndSettle();
  await tester.tap(find.text('スキル詳細'));await tester.pumpAndSettle();
  expect(find.text('確定済み 0 / 6 枠'),findsOneWidget);
  expect(tester.widget<EquipmentSkillDetails>(find.byType(EquipmentSkillDetails)).generation,1);
 });
 testWidgets('旧未導入装備は確定結果を作らない',(tester) async {
  final c=AppController(_Store(),equipmentCatalog:catalog);
  addTearDown(c.dispose);await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:sword',EquipmentSlot.ring,EquipmentRarity.gr);
  for(var i=0;i<3;i++){c.state.inventory.enhance(item.id,i);}
  await tester.pumpWidget(MaterialApp(home:AbyssInventoryScreen(controller:c)));
  await tester.ensureVisible(find.text('スキル詳細'));
  await tester.tap(find.text('スキル詳細'));await tester.pumpAndSettle();
  expect(find.text('装備スキル機能未有効化'),findsOneWidget);
  expect(find.text('+3 旧枠・抽選対象外'),findsOneWidget);
  expect(find.text('確定済み 0 / 6 枠'),findsOneWidget);
  expect(c.state.inventory.equipmentSkillHistories,isEmpty);
 });
}
