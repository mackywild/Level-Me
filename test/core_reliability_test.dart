import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:level_me/world/world_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/models/stat_type.dart';
import 'package:level_me/models/quest.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_summon.dart';
import 'package:level_me/world/abyss_summon_transaction.dart';

class _ZeroRandom implements Random {
 int calls=0;
 @override int nextInt(int max){calls++;return 0;}
 @override double nextDouble()=>0;
 @override bool nextBool()=>false;
}
class MemoryStore extends LocalStore {
 String? data;
 bool fail=false;
 @override Future<AppStateData> load() async=>data==null?AppStateData.initial():AppStateData.fromJson(jsonDecode(data!) as Map<String,dynamic>);
 @override Future<void> save(AppStateData state) async {
  if(fail)throw StateError('simulated disk failure');
  data=jsonEncode(state.toJson());
 }
}
void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 late MemoryStore store;
 late AppController controller;
 setUp(() async {store=MemoryStore();controller=AppController(store);await controller.initialize();});
 tearDown(()=>controller.dispose());
 test('25 minutes preserves baseline and duplicate claim only records time',() async {
  final q=controller.state.quests.first;
  await controller.completeQuest(q,activeSeconds:1500);
  expect(controller.state.stats[StatType.intelligence],20);
  final exp=controller.state.totalExp;
  await controller.completeQuest(q,activeSeconds:1500);
  expect(controller.state.totalExp,exp);
  expect(controller.state.sessionHistory.length,2);
  expect(controller.state.sessionHistory.last['rewarded'],false);
 });
 test('failure restores state and allows retry',() async {
  final q=controller.state.quests.first;
  store.fail=true;
  await expectLater(controller.completeQuest(q,activeSeconds:1500),throwsStateError);
  expect(controller.state.totalExp,0);
  expect(controller.state.completionCount,0);
  expect(controller.state.sessionHistory,isEmpty);
  store.fail=false;
  await controller.completeQuest(q,activeSeconds:1500);
  expect(controller.state.completionCount,1);
 });
 test('session survives reload and is cleared on finish',() async {
  final q=controller.state.quests.first;
  await controller.saveSession(q.id,{'seconds':120,'incorrect':['A1']});
  final restored=AppController(store);
  await restored.initialize();
  expect(restored.sessionFor(q.id)?['seconds'],120);
  await restored.completeQuest(q,activeSeconds:120,reviewIds:['A1']);
  expect(restored.sessionFor(q.id),isNull);
  expect(restored.state.quests.where((q)=>q.reviewQuestionIds.contains('A1')).length,1);
  restored.dispose();
 });
 test('timed quest rejects instant completion',() async {
  await expectLater(controller.completeQuest(controller.state.quests.first),throwsArgumentError);
  expect(controller.state.completionCount,0);
 });
 test('quest editing and archiving preserve awarded EXP and completion',() async {
  await controller.addQuest(title:'Project',cadence:QuestCadence.daily,rewards:const [QuestReward(stat:StatType.creativity,exp:20),QuestReward(stat:StatType.intelligence,exp:10)]);
  final q=controller.state.quests.first;
  await controller.completeQuest(q);
  final exp=controller.state.totalExp;
  await controller.editQuest(q.id,title:'Project revised',cadence:QuestCadence.daily,rewards:const [QuestReward(stat:StatType.creativity,exp:30)]);
  expect(controller.state.quests.first.isCompleted,true);
  await controller.archiveQuest(q.id);
  expect(controller.state.quests.first.archived,true);
  await expectLater(controller.completeQuest(q),throwsStateError);
  await controller.restoreQuest(q.id);
  expect(controller.state.quests.first.archived,false);
  await controller.completeQuest(q);
  expect(controller.state.totalExp,exp);
 });
 test('cadence cannot change after claim',() async {
  await controller.addQuest(title:'Daily',cadence:QuestCadence.daily,rewards:const [QuestReward(stat:StatType.social,exp:10)]);
  final q=controller.state.quests.first;
  await controller.completeQuest(q);
  await expectLater(controller.editQuest(q.id,title:q.title,rewards:q.rewards,cadence:QuestCadence.oneTime),throwsStateError);
 });
 test('starter quests cannot be archived',() async {
  await expectLater(controller.archiveQuest('starter-study'),throwsStateError);
 });
 test('legacy state accepts missing session fields',(){
  final json=AppStateData.initial().toJson()..remove('sessions')..remove('sessionHistory');
  final restored=AppStateData.fromJson(json);
  expect(restored.sessions,isEmpty);
  expect(restored.sessionHistory,isEmpty);
 });
 test('world victory persists rewards without granting daily EXP',() async {
  final exp=controller.state.totalExp;
  await controller.startWorldBattle('p01_main');
  final battle=controller.state.world.battle!;
  await controller.worldCommand(WorldCommand.claw,battle.id,battle.turn);
  expect(controller.state.world.cleared,contains('p01_main'));
  expect(controller.state.world.summonTickets,3);
  expect(controller.state.totalExp,exp);
  await expectLater(controller.worldCommand(WorldCommand.claw,battle.id,1),throwsStateError);
  final restored=AppController(store);
  await restored.initialize();
  expect(restored.state.world.summonTickets,3);
  expect(restored.state.totalExp,exp);
  restored.dispose();
 });
 test('failed world save rolls back battle turn and currency',() async {
  await controller.startWorldBattle('p01_main');
  final battle=controller.state.world.battle!;
  store.fail=true;
  await expectLater(controller.worldCommand(WorldCommand.claw,battle.id,battle.turn),throwsStateError);
  expect(controller.state.world.battle!.enemyHp,10);
  expect(controller.state.world.battle!.turn,1);
  expect(controller.state.world.gold,0);
  expect(controller.state.world.cleared,isEmpty);
  store.fail=false;
  await controller.worldCommand(WorldCommand.claw,battle.id,1);
  expect(controller.state.world.gold,40);
 });
 test('same-day extra study restores energy but not EXP; replay is ignored',() async {
  final q=controller.state.quests.first;
  await controller.completeQuest(q,activeSeconds:1500,sessionId:'study1');
  final exp=controller.state.totalExp;
  controller.state.world.magic=0;
  await controller.completeQuest(q,activeSeconds:1500,sessionId:'study2');
  expect(controller.state.world.magic,15);
  expect(controller.state.totalExp,exp);
  await controller.completeQuest(q,activeSeconds:1500,sessionId:'study2');
  expect(controller.state.world.magic,15);
  expect(controller.state.sessionHistory.length,2);
 });
 test('same-day extra workout restores physical energy only',() async {
  final q=controller.state.quests.firstWhere((q)=>q.id=='starter-workout');
  await controller.completeQuest(q,activeSeconds:1800,sessionId:'workout1');
  final exp=controller.state.totalExp;
  controller.state.world.physical=0;
  controller.state.world.magic=0;
  await controller.completeQuest(q,activeSeconds:1800,sessionId:'workout2');
  expect(controller.state.world.physical,15);
  expect(controller.state.world.magic,0);
  expect(controller.state.totalExp,exp);
 });
 test('legacy battle and gacha do not award ability EXP',() async {
  controller.state.attackEnergy=1000;
  controller.state.stats[StatType.fitness]=100000;
  controller.state.gachaTickets=40;
  final exp=controller.state.totalExp;
  final result=await controller.attackBoss();
  expect(result!.defeated,true);
  expect(controller.state.world.gold,80);
  expect(controller.state.totalExp,exp);
  for(var i=0;i<40;i++){await controller.drawBattleReward();}
  expect(controller.state.totalExp,exp);
  expect(controller.state.gachaTickets,0);
 });
 test('equipment changes persist, affect battle snapshot, and rollback on save failure',() async {
  final catalog=EquipmentCatalog(const [
   EquipmentDefinition(id:'equipment:test_ring',name:'Test ring',slot:EquipmentSlot.ring,rarity:EquipmentRarity.r,physical:5),
   EquipmentDefinition(id:'equipment:test_ring2',name:'Test ring 2',slot:EquipmentSlot.ring,rarity:EquipmentRarity.r,physical:8),
  ]);
  final c=AppController(store,equipmentCatalog:catalog);
  addTearDown(c.dispose);
  await c.initialize();
  final base=c.worldStats.physical;
  final first=c.state.inventory.addEquipment('equipment:test_ring',EquipmentSlot.ring,EquipmentRarity.r);
  final second=c.state.inventory.addEquipment('equipment:test_ring2',EquipmentSlot.ring,EquipmentRarity.r);
  await c.equipWorldItem(first.id);
  expect(c.worldStats.physical,base+5);
  store.fail=true;
  await expectLater(c.equipWorldItem(second.id),throwsStateError);
  expect(c.state.inventory.equipped[EquipmentSlot.ring],first.id);
  expect(c.worldStats.physical,base+5);
  store.fail=false;
  await c.equipWorldItem(second.id);
  expect(c.worldStats.physical,base+8);
  expect((await store.load()).inventory.equipped[EquipmentSlot.ring],second.id);
  await c.startWorldBattle('p01_main');
  final battle=c.state.world.battle!;
  expect(battle.stats.physical,base+8);
  await expectLater(c.unequipWorldItem(EquipmentSlot.ring),throwsStateError);
  await expectLater(c.equipWorldItem(first.id),throwsStateError);
  await c.worldCommand(WorldCommand.retreat,battle.id,battle.turn);
  store.fail=true;
  await expectLater(c.unequipWorldItem(EquipmentSlot.ring),throwsStateError);
  expect(c.state.inventory.equipped[EquipmentSlot.ring],second.id);
  expect(c.worldStats.physical,base+8);
  store.fail=false;
  await c.unequipWorldItem(EquipmentSlot.ring);
  expect(c.worldStats.physical,base);
  expect((await store.load()).inventory.equipped,isEmpty);
 });
 test('loadout legacy default and invalid references',(){
  final inv=AbyssInventory();
  final item=inv.addEquipment('equipment:test_ring',EquipmentSlot.ring,EquipmentRarity.r);
  inv.equip(item.id);
  expect(AbyssInventory.fromJson(inv.toJson()..remove('equipped')).equipped,isEmpty);
  expect(()=>AbyssInventory.fromJson(inv.toJson()..['equipped']={'head':item.id}),throwsFormatException);
  expect(()=>AbyssInventory.fromJson(inv.toJson()..['equipped']={'ring':'eq_99'}),throwsFormatException);
  expect(()=>inv.equip('eq_99'),throwsStateError);
 });
 test('equip rejects missing or mismatched catalog entries without changing state',() async {
  final catalog=EquipmentCatalog(const [
   EquipmentDefinition(id:'equipment:ring',name:'Ring',slot:EquipmentSlot.ring,rarity:EquipmentRarity.r),
  ]);
  final c=AppController(store,equipmentCatalog:catalog);
  addTearDown(c.dispose);
  await c.initialize();
  final valid=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.r);
  final missing=c.state.inventory.addEquipment('equipment:missing',EquipmentSlot.ring,EquipmentRarity.r);
  final wrongSlot=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.head,EquipmentRarity.r);
  final wrongRarity=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.sr);
  await c.equipWorldItem(valid.id);
  final snapshot=jsonEncode(c.state.toJson());
  final persisted=store.data;
  for(final item in [missing,wrongSlot,wrongRarity]){
   await expectLater(c.equipWorldItem(item.id),throwsStateError);
   expect(jsonEncode(c.state.toJson()),snapshot);
   expect(store.data,persisted);
   expect(c.ready,true);
  }
 });
 test('summon persists receipt, equipment, pool counters and tickets; stale request rejected',() async {
  final defs=[for(final rarity in EquipmentRarity.values.take(4))EquipmentDefinition(id:'equipment:ring_${rarity.name}',name:'Test ring',slot:EquipmentSlot.ring,rarity:rarity)];
  final catalog=EquipmentCatalog(defs);
  final pool=SummonCatalog([
   for(final def in defs)SummonEntry(pool:SummonPool.equipment,masterId:def.id,rarity:def.rarity),
   for(final rarity in EquipmentRarity.values.take(4))SummonEntry(pool:SummonPool.supplies,masterId:'item:test_${rarity.name}',rarity:rarity),
  ]);
  final c=AppController(store,equipmentCatalog:catalog,summonCatalog:pool,summonRandom:_ZeroRandom());
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.cleared.addAll(['p01_main','p12_main']);
  c.state.world.summonTickets=20;
  c.state.world.supplyTickets=2;
  final receipt=await c.summonWorldItems(SummonPool.equipment,10,0);
  expect(receipt.sequence,1);
  expect(receipt.rewards.map((e)=>e.rarity).toList(),[...List.filled(9,EquipmentRarity.n),EquipmentRarity.sr]);
  expect(receipt.rewards.map((e)=>e.instanceId).toSet().length,10);
  expect(c.state.world.summonTickets,10);
  expect(c.state.summon.misses(SummonPool.equipment)[EquipmentRarity.ssr],10);
  expect(c.state.summon.misses(SummonPool.supplies),isEmpty);
  final loaded=await store.load();
  expect(loaded.inventory.equipment.length,10);
  expect(loaded.summon.latest!.toJson(),receipt.toJson());
  expect(loaded.world.summonTickets,10);
  final restarted=AppController(store,equipmentCatalog:catalog,summonCatalog:pool,summonRandom:_ZeroRandom());
  addTearDown(restarted.dispose);
  await restarted.initialize();
  final before=jsonEncode(restarted.state.toJson());
  await expectLater(restarted.summonWorldItems(SummonPool.equipment,10,0),throwsStateError);
  expect(jsonEncode(restarted.state.toJson()),before);
  await restarted.summonWorldItems(SummonPool.supplies,1,1);
  expect(restarted.state.world.supplyTickets,1);
  expect(restarted.state.world.summonTickets,10);
  expect(restarted.state.inventory.stacks['item:test_n'],1);
  expect(restarted.state.summon.misses(SummonPool.supplies)[EquipmentRarity.ssr],1);
  expect(restarted.state.summon.misses(SummonPool.equipment)[EquipmentRarity.ssr],10);
 });
 test('summon save failure rolls back receipt counters items and tickets',() async {
  final defs=[for(final rarity in EquipmentRarity.values.take(2))EquipmentDefinition(id:'equipment:relic_${rarity.name}',name:'Test relic',slot:EquipmentSlot.relic,rarity:rarity)];
  final catalog=EquipmentCatalog(defs);
  final pool=SummonCatalog([for(final def in defs)SummonEntry(pool:SummonPool.relic,masterId:def.id,rarity:def.rarity)]);
  final c=AppController(store,equipmentCatalog:catalog,summonCatalog:pool,summonRandom:_ZeroRandom());
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.summonTickets=5;
  final before=jsonEncode(c.state.toJson());
  final disk=store.data;
  store.fail=true;
  await expectLater(c.summonWorldItems(SummonPool.relic,1,0),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);
  expect(store.data,disk);
  store.fail=false;
  final receipt=await c.summonWorldItems(SummonPool.relic,1,0);
  expect(receipt.rewards.single.instanceId,'eq_1');
  expect(c.state.world.summonTickets,0);
  expect(c.state.summon.sequence,1);
 });
 test('empty production pool rejects without consuming any resource',() async {
  controller.state.world.summonTickets=10;
  final before=jsonEncode(controller.state.toJson());
  await expectLater(controller.summonWorldItems(SummonPool.equipment,1,0),throwsStateError);
  expect(jsonEncode(controller.state.toJson()),before);
 });
 test('concurrent and invalid summons never draw twice or mutate rejected state',() async {
  final defs=[for(final rarity in EquipmentRarity.values.take(2))EquipmentDefinition(id:'equipment:ring_${rarity.name}',name:'Ring',slot:EquipmentSlot.ring,rarity:rarity)];
  final catalog=EquipmentCatalog(defs);
  final pool=SummonCatalog([
   for(final def in defs)SummonEntry(pool:SummonPool.equipment,masterId:def.id,rarity:def.rarity),
   const SummonEntry(pool:SummonPool.relic,masterId:'equipment:ring_n',rarity:EquipmentRarity.n),
   const SummonEntry(pool:SummonPool.supplies,masterId:'item:test_n',rarity:EquipmentRarity.n),
  ]);
  final random=_ZeroRandom();
  final c=AppController(store,equipmentCatalog:catalog,summonCatalog:pool,summonRandom:random);
  addTearDown(c.dispose);
  await c.initialize();
  Future<void> reject(SummonPool pool) async {
   final before=jsonEncode(c.state.toJson());
   final calls=random.calls;
   await expectLater(c.summonWorldItems(pool,1,c.state.summon.sequence),throwsStateError);
   expect(jsonEncode(c.state.toJson()),before);
   expect(random.calls,calls);
  }
  await reject(SummonPool.equipment);
  c.state.world.summonTickets=20;
  c.state.world.supplyTickets=20;
  await reject(SummonPool.relic);
  await reject(SummonPool.supplies);
  await c.startWorldBattle('p01_main');
  await reject(SummonPool.equipment);
  final battle=c.state.world.battle!;
  await c.worldCommand(WorldCommand.retreat,battle.id,battle.turn);
  final first=c.summonWorldItems(SummonPool.equipment,1,0);
  final second=c.summonWorldItems(SummonPool.equipment,1,0);
  final rejected=expectLater(second,throwsStateError);
  await first;
  await rejected;
  expect(random.calls,2);
  expect(c.state.world.summonTickets,19);
  expect(c.state.inventory.equipment.length,1);
 });
 test('receipt rejects invalid instance IDs and pool mismatches',(){
  Map<String,dynamic> raw(String pool,String master,String? id)=>{'sequence':1,'pool':pool,'rewards':[{'masterId':master,'rarity':'n','instanceId':id}]};
  for(final id in [null,'eq_0','eq_01','invalid']){
   expect(()=>SummonReceipt.fromJson(raw('equipment','equipment:ring_n',id)),throwsFormatException);
  }
  expect(()=>SummonReceipt.fromJson(raw('supplies','item:potion','eq_1')),throwsFormatException);
  expect(()=>SummonReceipt.fromJson(raw('equipment','item:potion','eq_1')),throwsFormatException);
  final duplicate=raw('equipment','equipment:ring_n','eq_1');
  duplicate['rewards']=List.filled(10,(duplicate['rewards'] as List).first);
  expect(()=>SummonReceipt.fromJson(duplicate),throwsFormatException);
  expect(SummonReceipt.fromJson(raw('equipment','equipment:ring_n','eq_1')).rewards.single.instanceId,'eq_1');
 });
}
