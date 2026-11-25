import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_shop.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _DelayedStore extends LocalStore {
 _DelayedStore(Directory directory):super(directory:directory);
 Completer<void>? gate,entered;
 bool fail=false;
 @override Future<void> save(AppStateData state) async {
  if(gate!=null){entered!.complete();await gate!.future;}
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}
void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const gold=ShopOffer(id:'shop:iron',materialId:'item:iron',currency:ShopCurrency.gold,price:10,quantity:2);
 const crystals=ShopOffer(id:'shop:alloy',materialId:'item:alloy',currency:ShopCurrency.magicCrystals,price:3,quantity:1);
 final catalog=ShopCatalog(const [gold,crystals]);
 test('旧worldセーブは魔晶石・取引番号0で読み込み、不正値を拒否する',(){
  final old=WorldState(gold:50,summonTickets:3,supplyTickets:2).toJson()..remove('magicCrystals')..remove('shopSequence');
  final loaded=WorldState.fromJson(old);
  expect(loaded.magicCrystals,0);
  expect(loaded.shopSequence,0);
  expect(loaded.gold,50);
  expect(loaded.summonTickets,3);
  expect(loaded.supplyTickets,2);
  for(final key in ['magicCrystals','shopSequence']){
   expect(()=>WorldState.fromJson({...old,key:-1}),throwsFormatException);
   expect(()=>WorldState.fromJson({...old,key:null}),throwsA(isA<TypeError>()));
  }
 });
 test('不正価格・数量・重複・素材参照を拒否する',(){
  expect(()=>ShopCatalog(const [gold,gold]),throwsFormatException);
  expect(()=>ShopCatalog(const [ShopOffer(id:'shop:bad',materialId:'item:iron',currency:ShopCurrency.gold,price:0,quantity:1)]),throwsFormatException);
  expect(()=>ShopCatalog(const [ShopOffer(id:'shop:bad',materialId:'item:iron',currency:ShopCurrency.gold,price:1,quantity:1000001)]),throwsFormatException);
  final raw=jsonDecode(File(AbyssMaster.assetPath).readAsStringSync()) as Map<String,dynamic>;
  final master=AbyssMaster.fromJson(jsonEncode(raw..['enabled']=true));
  final c=AppController(LocalStore(),shopCatalog:ShopCatalog(const [ShopOffer(id:'shop:bad',materialId:'item:missing',currency:ShopCurrency.gold,price:1,quantity:1)]));
  addTearDown(c.dispose);
  expect(()=>c.configureAbyssMaster(master),throwsFormatException);
  expect(c.hasAbyssMaster,false);
  final valid=AppController(LocalStore(),shopCatalog:catalog);
  addTearDown(valid.dispose);
  valid.configureAbyssMaster(master);
  expect(valid.hasAbyssMaster,true);
 });
 test('無効商品・残高不足・古い番号・オーバーフローでは資産不変',(){
  final s=AppStateData.initial();
  s.world.gold=10;
  s.world.magicCrystals=2;
  void reject(ShopCatalog shop,String id,int seq){
   final before=jsonEncode(s.toJson());
   expect(()=>shop.purchase(world:s.world,inventory:s.inventory,offerId:id,expectedSequence:seq),throwsStateError);
   expect(jsonEncode(s.toJson()),before);
  }
  reject(ShopCatalog.production,gold.id,0);
  reject(catalog,'shop:missing',0);
  reject(catalog,crystals.id,0);
  reject(catalog,gold.id,1);
  s.inventory.addStack('item:iron',0x7fffffffffffffff);
  reject(catalog,gold.id,0);
  s.inventory.removeStack('item:iron',0x7fffffffffffffff);
  s.world.shopSequence=0x7fffffffffffffff;
  reject(catalog,gold.id,s.world.shopSequence);
 });
 test('保存中非公開・保存失敗・競合・再起動・バックアップ復元',() async {
  final dir=await Directory.systemTemp.createTemp('abyss-shop-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_DelayedStore(dir);
  final c=AppController(store,portableBackup:PortableBackup(directory:dir),shopCatalog:catalog);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.world.gold=20;
  c.state.world.magicCrystals=6;
  c.state.world.summonTickets=5;
  c.state.world.supplyTickets=4;
  await store.save(c.state);
  final original=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${PortableBackup.playerName}');
  final bytes=await primary.readAsString();
  store.gate=Completer<void>();
  store.entered=Completer<void>();
  store.fail=true;
  final failed=expectLater(c.purchaseWorldMaterial(gold.id,0),throwsStateError);
  await store.entered!.future;
  expect(c.inventoryBusy,true);
  expect(jsonEncode(c.state.toJson()),original);
  expect(await primary.readAsString(),bytes);
  await expectLater(c.purchaseWorldMaterial(crystals.id,0),throwsStateError);
  store.gate!.complete();
  await failed;
  expect(c.inventoryBusy,false);
  expect(jsonEncode(c.state.toJson()),original);
  expect(await primary.readAsString(),bytes);
  store.gate=null;
  store.fail=false;
  await c.purchaseWorldMaterial(gold.id,0);
  expect(c.state.world.gold,10);
  expect(c.state.world.magicCrystals,6);
  expect(c.state.inventory.stacks['item:iron'],2);
  final restarted=AppController(LocalStore(directory:dir),portableBackup:PortableBackup(directory:dir),shopCatalog:catalog);
  addTearDown(restarted.dispose);
  await restarted.initialize();
  await expectLater(restarted.purchaseWorldMaterial(gold.id,0),throwsStateError);
  final exported=await restarted.exportPortableBackup();
  await restarted.purchaseWorldMaterial(crystals.id,1);
  expect(restarted.state.world.magicCrystals,3);
  expect(restarted.state.world.gold,10);
  expect(restarted.state.world.shopSequence,2);
  expect(restarted.state.inventory.stacks['item:alloy'],1);
  expect(restarted.state.world.summonTickets,5);
  expect(restarted.state.world.supplyTickets,4);
  await restarted.importPortableBackup(exported);
  expect(restarted.state.world.shopSequence,1);
  expect(restarted.state.world.magicCrystals,6);
  expect(restarted.state.inventory.stacks.containsKey('item:alloy'),false);
  await restarted.startWorldBattle('p01_main');
  final before=jsonEncode(restarted.state.toJson());
  await expectLater(restarted.purchaseWorldMaterial(crystals.id,1),throwsStateError);
  expect(jsonEncode(restarted.state.toJson()),before);
 });
}
