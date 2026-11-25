import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';
import 'package:level_me/world/abyss_enhancement.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/world_catalog.dart';

class _DelayedStore extends LocalStore {
 _DelayedStore(Directory directory):super(directory:directory);
 Completer<void>? gate;
 Completer<void>? entered;
 bool fail=false;
 @override Future<void> save(AppStateData state) async {
  if(gate!=null){
   entered!.complete();
   await gate!.future;
  }
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}

void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:ring',name:'試験指輪',slot:EquipmentSlot.ring,rarity:EquipmentRarity.n,magic:5)]);
 final policy=EnhancementPolicy(const [EnhancementRecipe(rarity:EquipmentRarity.n,materialId:'item:iron',quantity:2,gold:10)]);
 test('強化レシピの不正値・重複を拒否する',(){
  expect(()=>EnhancementPolicy(const [EnhancementRecipe(rarity:EquipmentRarity.n,materialId:'item:iron',quantity:0,gold:10)]),throwsFormatException);
  expect(()=>EnhancementPolicy(const [EnhancementRecipe(rarity:EquipmentRarity.n,materialId:'equipment:ring',quantity:2,gold:10)]),throwsFormatException);
  final recipe=policy.recipe(EquipmentRarity.n)!;
  expect(()=>EnhancementPolicy([recipe,recipe]),throwsFormatException);
 });
 test('本番無効・素材不足・G不足・戦闘中・不正個体・上限は資産不変',(){
  final s=AppStateData.initial();
  final item=s.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  s.world.gold=10;
  s.inventory.addStack('item:iron',2);
  void reject(EnhancementPolicy p,String id,int level){
   final before=jsonEncode(s.toJson());
   expect(()=>p.enhance(world:s.world,inventory:s.inventory,catalog:catalog,id:id,expectedLevel:level),throwsStateError);
   expect(jsonEncode(s.toJson()),before);
  }
  reject(EnhancementPolicy.production,item.id,0);
  reject(policy,'missing',0);
  reject(policy,item.id,1);
  s.world.gold=9;
  reject(policy,item.id,0);
  s.world.gold=10;
  s.inventory.removeStack('item:iron',1);
  reject(policy,item.id,0);
  s.inventory.addStack('item:iron',1);
  final unknown=s.inventory.addEquipment('equipment:missing',EquipmentSlot.ring,EquipmentRarity.n);
  reject(policy,unknown.id,0);
  for(var i=0;i<20;i++){s.inventory.enhance(item.id,i);}
  reject(policy,item.id,20);
 });
 test('保存完了まで資産を公開せず失敗時は維持し再試行で一度だけ強化する',() async {
  final dir=await Directory.systemTemp.createTemp('abyss-enhance-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_DelayedStore(dir);
  final backup=PortableBackup(directory:dir);
  final c=AppController(store,portableBackup:backup,equipmentCatalog:catalog,enhancementPolicy:policy);
  addTearDown(c.dispose);
  await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:ring',EquipmentSlot.ring,EquipmentRarity.n);
  c.state.inventory.equip(item.id);
  c.state.inventory.addStack('item:iron',4);
  c.state.world.gold=20;
  await store.save(c.state);
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${PortableBackup.playerName}');
  final bytes=await primary.readAsString();
  store.gate=Completer<void>();
  store.entered=Completer<void>();
  store.fail=true;
  final failure=expectLater(c.enhanceWorldItem(item.id,0),throwsStateError);
  await store.entered!.future;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.gate!.complete();
  await failure;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.gate=null;
  store.fail=false;
  final first=c.enhanceWorldItem(item.id,0);
  final second=expectLater(c.enhanceWorldItem(item.id,0),throwsStateError);
  expect((await first).enhancement,1);
  await second;
  expect(c.state.world.gold,10);
  expect(c.state.inventory.stacks['item:iron'],2);
  expect(c.state.inventory.equipped[EquipmentSlot.ring],item.id);
  expect(c.state.inventory.equipment[item.id]!.enhancement,1);
  final saved=await store.load();
  expect(saved.inventory.toJson(),c.state.inventory.toJson());
  final exported=await c.exportPortableBackup();
  await c.enhanceWorldItem(item.id,1);
  expect(c.state.inventory.stacks.containsKey('item:iron'),false);
  expect(c.state.inventory.discovered.contains('item:iron'),true);
  await c.importPortableBackup(exported);
  expect(c.state.inventory.toJson(),saved.inventory.toJson());
  expect(c.state.world.gold,10);
  await c.startWorldBattle('p01_main');
  final battleBefore=jsonEncode(c.state.toJson());
  await expectLater(c.enhanceWorldItem(item.id,1),throwsStateError);
  expect(jsonEncode(c.state.toJson()),battleBefore);
 });
}
