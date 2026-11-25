import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:level_me/main.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_summon.dart';
import 'package:level_me/world/world_engine.dart';

class _CountingRandom implements Random {
 int calls=0;
 @override int nextInt(int max){calls++;return 0;}
 @override double nextDouble()=>0.5;
 @override bool nextBool()=>false;
}

void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 Map<String,dynamic> source()=>jsonDecode(File(AbyssMaster.assetPath).readAsStringSync()) as Map<String,dynamic>;
 test('同梱マスターは承認前のため排出無効',(){
  final json=source();
  expect(json['enabled'],false);
  expect((json['equipment'] as List).length,24);
  expect((json['supplies'] as List).length,8);
  final master=AbyssMaster.fromJson(jsonEncode(json));
  expect(master.enabled,false);
  expect(master.equipment.find('equipment:cloth_cap'),isNull);
  expect(master.supply('item:iron'),isNull);
  for(final pool in SummonPool.values){
   for(final rarity in EquipmentRarity.values){
    expect(master.summon.entries(pool,rarity),isEmpty);
   }
  }
 });
 test('承認後のマスターは序章の全プールに必要な希少度を備える',(){
  final master=AbyssMaster.fromJson(jsonEncode(source()..['enabled']=true));
  expect(master.enabled,true);
  expect(master.equipment.find('equipment:cloth_cap')!.defense,1);
  expect(master.supply('item:iron')!.name,'鉄');
  for(final pool in SummonPool.values){
   for(final rarity in EquipmentRarity.values.take(4)){
    expect(master.summon.entries(pool,rarity),isNotEmpty);
   }
  }
 });
 test('不正な排出参照・部位・素材種別・重複・性能を拒否する',(){
  final invalid=source();
  (invalid['summon'] as List).add({'pool':'supplies','masterId':'item:unknown'});
  expect(()=>AbyssMaster.fromJson(jsonEncode(invalid)),throwsFormatException);
  final wrong=source();
  (wrong['summon'] as List).first['pool']='relic';
  expect(()=>AbyssMaster.fromJson(jsonEncode(wrong)),throwsFormatException);
  final special=source();
  (special['supplies'] as List).first['category']='power';
  expect(()=>AbyssMaster.fromJson(jsonEncode(special)),throwsFormatException);
  final duplicate=source();
  (duplicate['summon'] as List).add((duplicate['summon'] as List).first);
  expect(()=>AbyssMaster.fromJson(jsonEncode(duplicate)),throwsFormatException);
  final negative=source();
  (negative['equipment'] as List).first['defense']=-1;
  expect(()=>AbyssMaster.fromJson(jsonEncode(negative)),throwsFormatException);
 });
 test('承認フラグを立てても不完全なプールは拒否される',(){
  final json=source()..['enabled']=true;
  (json['summon'] as List).removeWhere((e)=>e['pool']=='relic');
  expect(()=>AbyssMaster.fromJson(jsonEncode(json)),throwsFormatException);
 });
 test('未承認でもプール欠落・手部武器・UR以上を拒否する',(){
  final missing=source();
  (missing['summon'] as List).removeWhere((e)=>e['pool']=='relic');
  expect(()=>AbyssMaster.fromJson(jsonEncode(missing)),throwsFormatException);
  final weapon=source();
  (weapon['equipment'] as List).first['slot']='hands';
  expect(()=>AbyssMaster.fromJson(jsonEncode(weapon)),throwsFormatException);
  final high=source();
  (high['equipment'] as List).first['rarity']='ur';
  expect(()=>AbyssMaster.fromJson(jsonEncode(high)),throwsFormatException);
  final supply=source();
  (supply['supplies'] as List).first['rarity']='ur';
  expect(()=>AbyssMaster.fromJson(jsonEncode(supply)),throwsFormatException);
 });
 test('同梱アセットを本番ローダーで読み込める',() async {
  expect(await rootBundle.loadString(AbyssMaster.assetPath),isNotEmpty);
  final master=await loadProductionMasters();
  expect(master.enabled,false);
  expect(master.skills.definitions,isEmpty);
  final raw=source();
  expect(raw['skillEnabled'],false);
  final rows=(raw['skills'] as List).cast<Map<String,dynamic>>();
  expect(rows.length,42);
  expect(rows.map((row)=>row['id']).toSet().length,42);
  expect(rows.map((row)=>row['id']),containsAll(ActiveSkillSpec.reservedEffects.keys));
  expect(rows.every((row)=>!row.containsKey('execution')),true);
  expect(AbyssMaster.fromJson(jsonEncode(raw..['enabled']=true)).skills.definitions,isEmpty);
 });
 test('RV-142: 非公開候補もID・名前・重複・family・kind・予約IDを検証する',(){
  void reject(void Function(List<Map<String,dynamic>>) change){
   final raw=source();
   change((raw['skills'] as List).cast<Map<String,dynamic>>());
   expect(()=>AbyssMaster.fromJson(jsonEncode(raw)),throwsFormatException);
  }
  for(final bad in [
   {'id':'bad'},{'id':'skill:'},{'id':'skill:test '},{'id':1},
   {'name':'  '},{'name':null},{'family':'unknown'},{'kind':'passive'},
  ]){
   reject((rows)=>rows.first.addAll(bad));
  }
  reject((rows)=>rows.add({...rows.first}));
  for(final id in ActiveSkillSpec.reservedEffects.keys){
   reject((rows)=>rows.singleWhere((row)=>row['id']==id).addAll({'family':'predation','kind':'passive'}));
  }
  final enabled=source()..['skillEnabled']=true;
  expect(()=>AbyssMaster.fromJson(jsonEncode(enabled)),throwsFormatException);
 });
 test('無効マスターは全プールを拒否し有効マスターは名称付きで付与する',() async {
  final dir=await Directory.systemTemp.createTemp('abyss-master-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=LocalStore(directory:dir);
  final random=_CountingRandom();
  final disabled=AppController(store,loadAbyssMaster:() async=>AbyssMaster.fromJson(jsonEncode(source())),summonRandom:random);
  addTearDown(disabled.dispose);
  await disabled.initialize();
  disabled.state.world.summonTickets=20;
  disabled.state.world.supplyTickets=10;
  await store.save(disabled.state);
  final before=jsonEncode(disabled.state.toJson());
  for(final pool in SummonPool.values){
   expect(disabled.summonUnavailable(pool,1),'排出マスター未整備');
   await expectLater(disabled.summonWorldItems(pool,1,0),throwsStateError);
   expect(jsonEncode(disabled.state.toJson()),before);
  }
  expect(random.calls,0);
  expect(()=>disabled.configureAbyssMaster(AbyssMaster.fromJson(jsonEncode(source()))),throwsStateError);
  final enabled=AppController(store,loadAbyssMaster:() async=>AbyssMaster.fromJson(jsonEncode(source()..['enabled']=true)),summonRandom:random);
  addTearDown(enabled.dispose);
  await enabled.initialize();
  for(final pool in SummonPool.values){
   expect(enabled.summonUnavailable(pool,1),isNull);
   final receipt=await enabled.summonWorldItems(pool,1,enabled.state.summon.sequence);
   expect(enabled.summonRewardName(receipt.rewards.single.masterId),isNot(receipt.rewards.single.masterId));
  }
  expect(enabled.state.world.summonTickets,14);
  expect(enabled.state.world.supplyTickets,9);
  expect(enabled.state.inventory.equipment.length,2);
  expect(enabled.state.inventory.stacks['item:iron'],1);
  expect(random.calls,6);
 });
 test('マスター読込失敗時は起動・両復元とも原本を保護し再試行できる',() async {
  final dir=await Directory.systemTemp.createTemp('abyss-master-recovery-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=LocalStore(directory:dir);
  final backup=PortableBackup(directory:dir);
  final initial=AppStateData.initial();
  await store.save(initial);
  initial.world.gold=10;
  await store.save(initial);
  final exported=await backup.export();
  Future<Map<String,String>> snapshot() async=>{for(final entry in await dir.list().toList())if(entry is File)entry.path:await entry.readAsString()};
  final original=await snapshot();
  bool fail=true;
  int loads=0;
  final c=AppController(store,portableBackup:backup,loadAbyssMaster:() async {
   loads++;
   if(fail)throw const FormatException('Invalid asset');
   return AbyssMaster.fromJson(jsonEncode(source()));
  });
  addTearDown(c.dispose);
  await expectLater(c.initialize(),throwsFormatException);
  expect(c.ready,false);
  expect(c.hasAbyssMaster,false);
  expect(await c.hasBackup(),false);
  await expectLater(c.restoreBackup(),throwsFormatException);
  await expectLater(c.importPortableBackup(exported),throwsFormatException);
  expect(await snapshot(),original);
  expect(loads,3);
  fail=false;
  await c.initialize();
  expect(c.ready,true);
  expect(c.hasAbyssMaster,true);
  expect(loads,4);
  await c.importPortableBackup(exported);
  expect(c.ready,true);
  expect(loads,4);
  await c.restoreBackup();
  expect(c.ready,true);
  expect(loads,4);
 });
 test('個別排出確率は現在の希少度確率を候補数で等分する',() async {
  final dir=await Directory.systemTemp.createTemp('abyss-rates-');
  addTearDown(()=>dir.delete(recursive:true));
  final random=_CountingRandom();
  final c=AppController(LocalStore(directory:dir),loadAbyssMaster:() async=>AbyssMaster.fromJson(jsonEncode(source()..['enabled']=true)),summonRandom:random);
  addTearDown(c.dispose);
  await c.initialize();
  for(final stage in ['', 'p01_main','p12_main']){
   if(stage.isNotEmpty)c.state.world.cleared.add(stage);
   for(final pool in SummonPool.values){
    final rates=c.summonRates(pool);
    expect(rates.fold<double>(0,(sum,r)=>sum+r.percent),closeTo(100,0.0000001));
    for(final rarity in EquipmentRarity.values){
     final group=rates.where((r)=>r.entry.rarity==rarity).toList();
     if(rarity.index>c.summonHighestUnlocked.index){
      expect(group,isEmpty);
     }else{
      expect(group,isNotEmpty);
      for(final rate in group){
       expect(rate.candidateCount,group.length);
       expect(rate.percent,closeTo(c.summonWeights[rarity.index]/100/group.length,0.0000001));
      }
     }
    }
   }
  }
  expect(random.calls,0);
  expect(c.state.summon.sequence,0);
  expect(c.state.inventory.equipment,isEmpty);
 });
}
