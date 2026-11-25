import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';
import 'package:level_me/world/abyss_dismantle.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/world_catalog.dart';

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
 final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:ring',name:'試験指輪',slot:EquipmentSlot.ring,rarity:EquipmentRarity.n)]);
 final policy=DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.n,materialId:'item:iron',quantity:1)]);
 test('保護・不一致・無効レシピ・強化済み・素材上限では資産不変',(){
  final s=AppStateData.initial();
  final item=s.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  void reject(DismantlePolicy p,String id,int level){
   final before=jsonEncode(s.toJson());
   expect(()=>p.dismantle(world:s.world,inventory:s.inventory,catalog:catalog,id:id,expectedLevel:level),throwsStateError);
   expect(jsonEncode(s.toJson()),before);
  }
  reject(DismantlePolicy.production,item.id,0);
  reject(policy,'missing',0);
  reject(policy,item.id,1);
  s.inventory.equip(item.id);
  reject(policy,item.id,0);
  s.inventory.unequip(item.slot);
  s.inventory.setFavorite(item.id,true);
  reject(policy,item.id,0);
  s.inventory.setFavorite(item.id,false);
  final wrong=s.inventory.addEquipment('equipment:ring',EquipmentSlot.head,EquipmentRarity.n);
  reject(policy,wrong.id,0);
  final wrongRarity=s.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.r);
  reject(policy,wrongRarity.id,0);
  s.inventory.addStack('item:iron',0x7fffffffffffffff);
  reject(policy,item.id,0);
  s.inventory.removeStack('item:iron',0x7fffffffffffffff);
  s.inventory.enhance(item.id,0);
  reject(policy,item.id,1);
 });
 test('不正レシピと本番素材参照の不一致を拒否する',(){
  expect(()=>DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.n,materialId:'item:iron',quantity:0)]),throwsFormatException);
  expect(()=>DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.n,materialId:'item:iron',quantity:1000001)]),throwsFormatException);
  final recipe=policy.recipe(EquipmentRarity.n)!;
  expect(()=>DismantlePolicy([recipe,recipe]),throwsFormatException);
  final raw=jsonDecode(File(AbyssMaster.assetPath).readAsStringSync()) as Map<String,dynamic>;
  final master=AbyssMaster.fromJson(jsonEncode(raw..['enabled']=true));
  for(final id in ['item:missing','item:alloy']){
   final c=AppController(LocalStore(),dismantlePolicy:DismantlePolicy([DismantleRecipe(rarity:EquipmentRarity.n,materialId:id,quantity:1)]));
   addTearDown(c.dispose);
   expect(()=>c.configureAbyssMaster(master),throwsFormatException);
   expect(c.hasAbyssMaster,false);
  }
  final valid=AppController(LocalStore(),dismantlePolicy:policy);
  addTearDown(valid.dispose);
  valid.configureAbyssMaster(master);
  expect(valid.hasAbyssMaster,true);
 });
 test('分解の保存前非公開・失敗・重複要求・再起動・復元・ID非再利用',() async {
  final dir=await Directory.systemTemp.createTemp('abyss-dismantle-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_DelayedStore(dir);
  final backup=PortableBackup(directory:dir);
  final c=AppController(store,portableBackup:backup,equipmentCatalog:catalog,dismantlePolicy:policy);
  addTearDown(c.dispose);
  await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  final keep=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  c.state.world.gold=10;
  await c.setWorldEquipmentFavorite(keep.id,true);
  await expectLater(c.dismantleWorldItem(keep.id,0),throwsStateError);
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${PortableBackup.playerName}');
  final bytes=await primary.readAsString();
  store.gate=Completer<void>();
  store.entered=Completer<void>();
  store.fail=true;
  final failure=expectLater(c.dismantleWorldItem(item.id,0),throwsStateError);
  await store.entered!.future;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.gate!.complete();
  await failure;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.gate=null;
  store.fail=false;
  final first=c.dismantleWorldItem(item.id,0);
  final duplicate=expectLater(c.dismantleWorldItem(item.id,0),throwsStateError);
  expect((await first).quantity,1);
  await duplicate;
  expect(c.state.inventory.equipment.containsKey(item.id),false);
  expect(c.state.inventory.equipment[keep.id]!.favorite,true);
  expect(c.state.inventory.stacks['item:iron'],1);
  expect(c.state.inventory.discovered,containsAll(['equipment:ring','item:iron']));
  expect(c.state.world.gold,10);
  final exported=await c.exportPortableBackup();
  final restarted=AppController(LocalStore(directory:dir),portableBackup:PortableBackup(directory:dir),equipmentCatalog:catalog,dismantlePolicy:policy);
  addTearDown(restarted.dispose);
  await restarted.initialize();
  await expectLater(restarted.dismantleWorldItem(item.id,0),throwsStateError);
  expect(restarted.state.inventory.stacks['item:iron'],1);
  await restarted.setWorldEquipmentFavorite(keep.id,false);
  await restarted.dismantleWorldItem(keep.id,0);
  expect(restarted.state.inventory.equipment,isEmpty);
  expect(restarted.state.inventory.discovered,contains('equipment:ring'));
  await restarted.importPortableBackup(exported);
  expect(restarted.state.inventory.equipment[keep.id]!.favorite,true);
  expect(restarted.state.inventory.stacks['item:iron'],1);
  final next=restarted.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  expect(next.id,'eq_3');
  await restarted.setWorldEquipmentFavorite(next.id,false);
  await restarted.startWorldBattle('p01_main');
  final battleBefore=jsonEncode(restarted.state.toJson());
  await expectLater(restarted.dismantleWorldItem(next.id,0),throwsStateError);
  await expectLater(restarted.setWorldEquipmentFavorite(next.id,true),throwsStateError);
  expect(jsonEncode(restarted.state.toJson()),battleBefore);
 });
 test('低レベル削除でも装着・お気に入り・強化済み装備を保護する',(){
  final inv=AbyssInventory();
  final item=inv.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  inv.equip(item.id);
  expect(()=>inv.removeEquipment(item.id,0),throwsStateError);
  inv.unequip(item.slot);
  inv.setFavorite(item.id,true);
  expect(()=>inv.removeEquipment(item.id,0),throwsStateError);
  inv.setFavorite(item.id,false);
  inv.enhance(item.id,0);
  expect(()=>inv.removeEquipment(item.id,1),throwsStateError);
  expect(inv.equipment[item.id]!.enhancement,1);
  expect(inv.discovered,contains(item.masterId));
 });
 test('併用報酬は保存失敗で全資産不変、再起動・復元後も一括保存される',() async {
  final dir=await Directory.systemTemp.createTemp('combined-reward-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_DelayedStore(dir);
  final combined=DismantlePolicy(const [DismantleRecipe(rarity:EquipmentRarity.n,materialId:'item:iron',quantity:2,magicCrystals:3)]);
  final c=AppController(store,portableBackup:PortableBackup(directory:dir),equipmentCatalog:catalog,dismantlePolicy:combined);
  addTearDown(c.dispose);
  await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  c.state.world.magicCrystals=4;
  c.state.inventory.addStack('item:iron',1);
  await store.save(c.state);
  final raw=await c.exportPortableBackup();
  final generation=c.restoreGeneration;
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final bytes=await primary.readAsString();
  store.gate=Completer<void>();
  store.entered=Completer<void>();
  store.fail=true;
  final failed=expectLater(c.dismantleWorldItem(item.id,0),throwsStateError);
  await store.entered!.future;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.gate!.complete();
  await failed;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.gate=null;
  store.fail=false;
  await c.setWorldEquipmentFavorite(item.id,true);
  await expectLater(c.dismantleWorldItem(item.id,0),throwsStateError);
  await c.setWorldEquipmentFavorite(item.id,false);
  await c.equipWorldItem(item.id);
  await expectLater(c.dismantleWorldItem(item.id,0),throwsStateError);
  await c.unequipWorldItem(item.slot);
  await c.dismantleWorldItem(item.id,0);
  final restarted=AppController(LocalStore(directory:dir),portableBackup:PortableBackup(directory:dir),equipmentCatalog:catalog,dismantlePolicy:combined);
  addTearDown(restarted.dispose);
  await restarted.initialize();
  expect(restarted.state.world.magicCrystals,7);
  expect(restarted.state.inventory.stacks['item:iron'],3);
  expect(restarted.state.inventory.equipment,isEmpty);
  await expectLater(restarted.dismantleWorldItem(item.id,0),throwsStateError);
  await c.importPortableBackup(raw);
  await expectLater(c.dismantleWorldItem(item.id,0,expectedGeneration:generation,expectedItem:item),throwsStateError);
  expect(c.state.world.magicCrystals,4);
  expect(c.state.inventory.stacks['item:iron'],1);
  expect(c.state.inventory.equipment.containsKey(item.id),true);
  await c.dismantleWorldItem(item.id,0,expectedGeneration:c.restoreGeneration,expectedItem:item);
  expect(c.state.world.magicCrystals,7);
 });
 test('併用報酬の各加算上限と不正レシピを拒否する',(){
  const reward=DismantleRecipe(rarity:EquipmentRarity.n,materialId:'item:iron',quantity:2,magicCrystals:3);
  final combined=DismantlePolicy(const [reward]);
  for(final crystalOverflow in [true,false]){
   final s=AppStateData.initial();
   final item=s.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
   if(crystalOverflow){s.world.magicCrystals=0x7fffffffffffffff;}else{s.inventory.addStack('item:iron',0x7fffffffffffffff);}
   final before=jsonEncode(s.toJson());
   expect(()=>combined.dismantle(world:s.world,inventory:s.inventory,catalog:catalog,id:item.id,expectedLevel:0),throwsStateError);
   expect(jsonEncode(s.toJson()),before);
  }
  for(final invalid in const [
   DismantleRecipe(rarity:EquipmentRarity.n,materialId:'',quantity:0,magicCrystals:-1),
   DismantleRecipe(rarity:EquipmentRarity.n,materialId:'',quantity:0,magicCrystals:1000001),
   DismantleRecipe(rarity:EquipmentRarity.n,materialId:'',quantity:0),
   DismantleRecipe(rarity:EquipmentRarity.n,materialId:'equipment:ring',quantity:1,magicCrystals:3),
  ]){
   expect(()=>DismantlePolicy([invalid]),throwsFormatException);
  }
 });
}
