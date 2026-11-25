import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/screens/abyss_summon_screen.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_summon.dart';
import 'package:level_me/world/abyss_summon_transaction.dart';

class _Store extends LocalStore {
 String? data;
 bool failCommit=false;
 @override Future<AppStateData> load() async=>data==null?AppStateData.initial():AppStateData.fromJson(jsonDecode(data!) as Map<String,dynamic>);
 @override Future<void> save(AppStateData state) async {
  if(failCommit&&state.summon.sequence>0&&state.summon.pending==null)throw StateError('save failure');
  data=jsonEncode(state.toJson());
 }
}
class _Random implements Random {
 int calls=0;
 @override int nextInt(int max){calls++;return 0;}
 @override double nextDouble()=>0.5;
 @override bool nextBool()=>false;
}

void main(){
 testWidgets('未整備の本番プールは操作不可で券を消費しない',(tester) async {
  final c=AppController(_Store());
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.summonTickets=20;
  await tester.pumpWidget(MaterialApp(home:AbyssSummonScreen(controller:c)));
  expect(find.text('排出マスター未整備'),findsNWidgets(2));
  final single=tester.widget<FilledButton>(find.widgetWithText(FilledButton,'単発召喚（1券）'));
  expect(single.onPressed,isNull);
  expect(c.state.world.summonTickets,20);
  expect(c.state.summon.sequence,0);
  await tester.tap(find.text('魔遺物召喚'));
  await tester.pump();
  expect(find.widgetWithText(FilledButton,'単発召喚（5券）'),findsOneWidget);
  await tester.tap(find.text('物資召喚'));
  await tester.pump();
  expect(find.text('召喚券不足'),findsNWidgets(2));
 });
 testWidgets('確定保存に失敗しても保留結果を公開せず同一取引を再開する',(tester) async {
  final store=_Store();
  final random=_Random();
  final defs=[for(final rarity in EquipmentRarity.values.take(2))EquipmentDefinition(id:'equipment:test_${rarity.name}',name:'試験装備',slot:EquipmentSlot.ring,rarity:rarity)];
  final catalog=EquipmentCatalog(defs);
  final pool=SummonCatalog([for(final def in defs)SummonEntry(pool:SummonPool.equipment,masterId:def.id,rarity:def.rarity)]);
  final c=AppController(store,equipmentCatalog:catalog,summonCatalog:pool,summonRandom:random);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.summonTickets=2;
  await tester.pumpWidget(MaterialApp(home:AbyssSummonScreen(controller:c)));
  store.failCommit=true;
  await tester.tap(find.widgetWithText(FilledButton,'単発召喚（1券）'));
  await tester.pumpAndSettle();
  expect(c.state.summon.pending,isNotNull);
  expect(c.state.summon.latest,isNull);
  expect(c.state.world.summonTickets,2);
  expect(find.text('試験装備'),findsNothing);
  expect(random.calls,2);
  final chip=tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip,'物資召喚'));
  expect(chip.onSelected,isNull);
  store.failCommit=false;
  await tester.tap(find.widgetWithText(FilledButton,'保留中の召喚を再開'));
  await tester.pumpAndSettle();
  expect(c.state.summon.pending,isNull);
  expect(c.state.summon.latest!.rewards.single.masterId,'equipment:test_n');
  expect(c.state.world.summonTickets,1);
  expect(c.state.inventory.equipment.length,1);
  expect(random.calls,2);
  await tester.scrollUntilVisible(find.text('試験装備'),300,scrollable:find.byType(Scrollable).first);
  expect(find.text('試験装備'),findsOneWidget);
 });
}
