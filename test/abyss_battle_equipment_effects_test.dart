import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/world_catalog.dart';

import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_equipment_skill_master.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';

class _Rolls implements Random {
 _Rolls(this.values);
 final List<double> values;
 int calls=0;
 @override double nextDouble()=>values[calls++];
 @override bool nextBool()=>false;
 @override int nextInt(int max)=>0;
}

void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const stats=WorldStats(hp:1000,physical:100,magic:100,defense:100,physicalMax:100,magicMax:100,crit:0.1);
 const now=1700000000000;
 const spec=ActiveSkillSpec(id:'skill:test',name:'試験攻撃',powerPercent:150,physicalCost:5,cooldown:2);
 const enemy=WorldEncounter('p01_main',1,'test','test',100000,101,100,0,main:true);
 WorldState battle(BattleEquipmentEffects? effects,{Map<BattleBuff,int>? buffs,Map<BattleStatus,int>? statuses,WorldEncounter encounter=enemy}){
  final base=effects?.apply(stats)??stats;
  return WorldState(hp:base.hp,physical:100,magic:100,sequence:1,hpAt:now,energyAt:now,lifespan:BigInt.from(100),
   battle:WorldBattle(id:1,encounterId:encounter.id,stats:base,enemyHp:encounter.hp,encounterSnapshot:encounter,executionVersion:effects==null?3:4,equipmentEffects:effects,activeSkills:const [spec],buffs:buffs,statuses:statuses));
 }
 test('RV-191: 通常物理・魔法・能動攻撃の会心と消費、実反撃',(){
  for(final command in [WorldCommand.heavyClaw,WorldCommand.magic,null]){
   final random=_Rolls([0.999999,0.5,0.5]);
   final engine=WorldEngine(random:random);
   final w=battle(BattleEquipmentEffects(physical:10000,magic:20000,critical:7000,evasion:5000,reduction:7000,discount:4000),
    buffs:{BattleBuff.critical:3,BattleBuff.evasion:2,BattleBuff.energyDiscount:3});
   final b=w.battle!;
   if(command==null){
    engine.actActiveSkill(w,spec.id,1,1,now);
   }else{
    engine.act(w,command,1,1,now);
   }
   final expected=command==WorldCommand.magic?270:command==WorldCommand.heavyClaw?270:225;
   expect(b.enemyHp,enemy.hp-expected);
   expect(b.log.any((l)=>l.contains('会心！')),true);
   expect(w.physical,command==WorldCommand.magic?100:command==null?97:95);
   expect(w.magic,command==WorldCommand.magic?97:100);
   expect(w.hp,985); // 防御100で50、70%軽減後15。
   expect(w.lifespan,BigInt.from(100));
   expect(random.calls,3); // 会心、威力、回避（0.5は被弾）。
  }
 });
 test('RV-191: 回避50%境界・毒除外・最小1・旧版行動',(){
  for(final roll in [0.499999,0.5]){
   final random=_Rolls([roll]);
   final engine=WorldEngine(random:random);
   final w=battle(BattleEquipmentEffects(evasion:4500,reduction:7000),buffs:{BattleBuff.evasion:2},statuses:{BattleStatus.poison:3});
   engine.act(w,WorldCommand.guard,1,1,now);
   expect(w.hp,roll<0.5?950:943); // 毒50は軽減されず、反撃25→7。
   expect(random.calls,1);
   expect(w.battle!.log.any((l)=>l.contains('反撃を回避')),roll<0.5);
  }
  const weak=WorldEncounter('p01_main',1,'test','test',100000,1,100,0,main:true);
  final random=_Rolls([]);
  final w=battle(BattleEquipmentEffects(reduction:7000),encounter:weak);
  WorldEngine(random:random).act(w,WorldCommand.guard,1,1,now);
  expect(w.hp,999);expect(random.calls,0);
  final legacyRandom=_Rolls([0.5,0.5]);
  final legacy=battle(null);
  WorldEngine(random:legacyRandom).act(legacy,WorldCommand.magic,1,1,now);
  expect(legacy.battle!.enemyHp,enemy.hp-60);expect(legacy.magic,94);
  expect(legacy.hp,950);expect(legacyRandom.calls,2);
 });
 test('RV-191: Controller装着履歴・実ファイル再起動・不一致復元拒否',() async {
  final dir=await Directory.systemTemp.createTemp('equipment-battle-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=LocalStore(directory:dir);
  final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:sword',name:'test',slot:EquipmentSlot.hands,rarity:EquipmentRarity.r)]);
  final master=EquipmentSkillMaster(const [
   EquipmentSkillMasterEntry(id:'equipment_skill:attack',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.physicalPercent,perLevel:1000),
   EquipmentSkillMasterEntry(id:'equipment_skill:extra',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.extraAttackChance,perLevel:100),
  ]);
  AppController controller(LocalStore s)=>AppController(s,equipmentCatalog:catalog,equipmentSkillMaster:master,clockMs:()=>now);
  final c=controller(store);addTearDown(c.dispose);await c.initialize();
  final inv=c.state.inventory;inv.activateEquipmentSkills(7);
  inv.addStack('item:iron',10);
  EquipmentInstance add(String skill){
   final item=inv.addEquipment('equipment:sword',EquipmentSlot.hands,EquipmentRarity.r);
   for(var i=0;i<5;i++){
    inv.enhanceWithMaterial(item.id,i,'item:iron',1,skillGrant:i==4?StoredEquipmentSkill(milestone:5,skillId:skill,level:2):null);
   }
   return item;
  }
  final unsupported=add('equipment_skill:extra'),supported=add('equipment_skill:attack');
  inv.equip(unsupported.id);
  await store.save(c.state);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=await primary.readAsString();
  await expectLater(c.startWorldBattle('p01_main'),throwsStateError);
  expect(await primary.readAsString(),before);
  c.state.inventory.equip(supported.id);
  await c.startWorldBattle('p01_main');
  final snapshot=c.state.world.battle!;
  expect(snapshot.executionVersion,4);expect(snapshot.equipmentEffects!.physical,2000);
  final restarted=controller(LocalStore(directory:dir));addTearDown(restarted.dispose);await restarted.initialize();
  expect(restarted.state.world.battle!.toJson(),snapshot.toJson());
  final expected=WorldState.fromJson(jsonDecode(jsonEncode(restarted.state.world.toJson())) as Map<String,dynamic>);
  WorldEngine().act(expected,WorldCommand.guard,snapshot.id,1,now);
  await restarted.worldCommand(WorldCommand.guard,snapshot.id,1,expectedGeneration:restarted.restoreGeneration);
  expect(restarted.state.world.toJson(),expected.toJson());
  final bytes=await primary.readAsString();
  final altered=jsonDecode(bytes) as Map<String,dynamic>;
  altered['world']['battle']['equipmentEffects']['physical']=2001;
  await File('${primary.path}.bak').writeAsString(jsonEncode(altered));
  await expectLater(restarted.restoreBackup(),throwsFormatException);
  expect(await primary.readAsString(),bytes);
 });
 test('装備補正と版4snapshotの往復、版3互換',(){
  final engine=WorldEngine(seedRandom:Random(7));
  final w=WorldState();
  final effects=BattleEquipmentEffects(physical:30000,magic:10000,defense:5000,critical:10000,evasion:5000,reduction:7000,discount:5000);
  engine.start(w,stats,'p01_main',1000000,equipmentEffects:effects);
  final b=w.battle!;
  expect(b.executionVersion,4);
  expect(b.stats.physical,400);expect(b.stats.magic,200);expect(b.stats.defense,150);
  expect(engine.energyCost(w,WorldCommand.heavyClaw),5);
  expect(engine.energyCost(w,WorldCommand.claw),2);
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  expect(restored.battle!.equipmentEffects!.sameAs(effects),true);
  expect(restored.battle!.stats.toJson(),b.stats.toJson());
  expect(engine.energyCost(restored,WorldCommand.heavyClaw),5);
  final legacy=WorldState();engine.start(legacy,stats,'p01_main',1000000);
  expect(legacy.battle!.executionVersion,3);
  expect(engine.energyCost(legacy,WorldCommand.heavyClaw),9);
  expect(WorldState.fromJson(legacy.toJson()).battle!.equipmentEffects,isNull);
 });
 test('版4不正上限・欠落・旧版への混入を拒否',(){
  final engine=WorldEngine(seedRandom:Random(7));
  final w=WorldState();engine.start(w,stats,'p01_main',1000000,equipmentEffects:BattleEquipmentEffects());
  final b=w.battle!;
  expect(()=>WorldBattle.fromJson(b.toJson()..remove('equipmentEffects')),throwsFormatException);
  expect(()=>WorldBattle.fromJson(b.toJson()..['executionVersion']=3),throwsFormatException);
  for(final entry in {'physical':30001,'magic':30001,'defense':30001,'critical':10001,'evasion':5001,'reduction':7001,'discount':5001}.entries){
   final raw=b.toJson();
   (raw['equipmentEffects'] as Map)[entry.key]=entry.value;
   expect(()=>WorldBattle.fromJson(raw),throwsFormatException);
  }
 });
}
