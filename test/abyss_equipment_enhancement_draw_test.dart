import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_enhancement.dart';
import 'package:level_me/world/abyss_equipment_skill_master.dart';
import 'package:level_me/world/abyss_equipment_effects.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_equipment_enhancement_draw.dart';
import 'package:level_me/world/world_catalog.dart';

class _FailStore extends LocalStore {
 _FailStore(Directory dir):super(directory:dir);
 bool fail=false;
 @override Future<void> save(AppStateData state) async {
  if(fail)throw StateError('Simulated failure');
  await super.save(state);
 }
}
void main(){
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 final master=EquipmentSkillMaster(const [
  EquipmentSkillMasterEntry(id:'equipment_skill:a',rarity:EquipmentSkillRarity.common,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.physicalPercent,perLevel:100),
  EquipmentSkillMasterEntry(id:'equipment_skill:b',rarity:EquipmentSkillRarity.rare,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.magicPercent,perLevel:100),
 ]);
 final catalog=EquipmentCatalog(const [EquipmentDefinition(id:'equipment:sword',name:'test',slot:EquipmentSlot.hands,rarity:EquipmentRarity.gr)]);
 final policy=EnhancementPolicy(const [EnhancementRecipe(rarity:EquipmentRarity.gr,materialId:'item:iron',quantity:1,gold:2)]);
 test('RV-188: 実抽選の希少度・候補均等・Lv帯独立・個体と段階の相関',(){
  final entries=[
   for(final rarity in EquipmentSkillRarity.values)
    for(var i=0;i<2;i++)
     EquipmentSkillMasterEntry(id:'equipment_skill:${rarity.name}_$i',rarity:rarity,pool:EquipmentSkillPool.attack,effect:EquipmentEffect.physicalPercent,perLevel:100),
  ];
  final full=EquipmentSkillMaster(entries);
  final reversed=EquipmentSkillMaster(entries.reversed);
  const sampleCount=12000;
  const drawsPerSeed=3;
  const probabilities=[0.35,0.35,0.125,0.125,0.025,0.025];
  const bandProbabilities=[0.15,0.40,0.42,0.03];
  final counts=List.generate(6,(_)=>List.filled(4,0));
  final stagePairs=List.generate(6,(_)=>List.filled(6,0));
  final itemPairs=List.generate(6,(_)=>List.filled(6,0));
  final levelCounts=List.filled(10,0);
  int band(int level)=>level<=3?0:level<=6?1:level<=9?2:3;
  void closeCount(int actual,int total,double p){
   final expected=total*p;
   // 固定サンプルの回帰判定。統計的な完全独立を証明するものではない。
   expect((actual-expected).abs(),lessThanOrEqualTo(6*sqrt(total*p*(1-p))+3));
  }
  for(var seed=0;seed<sampleCount;seed++){
   final inv=AbyssInventory();inv.activateEquipmentSkills(seed);
   const items=[
    EquipmentInstance(id:'eq_1',masterId:'equipment:sword',slot:EquipmentSlot.hands,rarity:EquipmentRarity.gr,enhancement:2),
    EquipmentInstance(id:'eq_1',masterId:'equipment:sword',slot:EquipmentSlot.hands,rarity:EquipmentRarity.gr,enhancement:5),
    EquipmentInstance(id:'eq_2',masterId:'equipment:sword',slot:EquipmentSlot.hands,rarity:EquipmentRarity.gr,enhancement:2),
   ];
   final indices=<int>[];
   for(final item in items){
    final grant=EquipmentEnhancementDraw.prepare(inv,item,full)!;
    final index=entries.indexWhere((e)=>e.id==grant.skillId);
    expect(index,greaterThanOrEqualTo(0));
    counts[index][band(grant.level)]++;
    levelCounts[grant.level-1]++;
    indices.add(index);
    if(seed<20){
     expect(EquipmentEnhancementDraw.prepare(inv,item,reversed)!.toJson(),grant.toJson());
    }
   }
   stagePairs[indices[0]][indices[1]]++;
   itemPairs[indices[0]][indices[2]]++;
  }
  const total=sampleCount*drawsPerSeed;
  for(var i=0;i<6;i++){
   final count=counts[i].reduce((a,b)=>a+b);
   closeCount(count,total,probabilities[i]);
   for(var j=0;j<4;j++){
    closeCount(counts[i][j],count,bandProbabilities[j]);
   }
   for(var j=0;j<6;j++){
    closeCount(stagePairs[i][j],sampleCount,probabilities[i]*probabilities[j]);
    closeCount(itemPairs[i][j],sampleCount,probabilities[i]*probabilities[j]);
   }
  }
  for(var rarity=0;rarity<3;rarity++){
   final first=counts[rarity*2].reduce((a,b)=>a+b);
   final second=counts[rarity*2+1].reduce((a,b)=>a+b);
   closeCount(first+second,total,[0.70,0.25,0.05][rarity]);
   closeCount(first,first+second,0.5);
  }
  for(var i=0;i<10;i++){
   closeCount(levelCounts[i],total, i==9?0.03:bandProbabilities[i~/3]/3);
  }
 },timeout:const Timeout(Duration(minutes:2)));
 test('版2は全履歴を必須とし、新規個体は+0から記録',(){
  final inv=AbyssInventory();inv.activateEquipmentSkills(12);
  final item=inv.addEquipment('equipment:sword',EquipmentSlot.hands,EquipmentRarity.gr);
  expect(inv.equipmentSkillHistories[item.id]!.startEnhancement,0);
  expect(inv.toJson()['version'],2);
  final raw=inv.toJson();(raw['equipmentSkills'] as Map)['items']={};
  expect(()=>AbyssInventory.fromJson(raw),throwsFormatException);
  expect(()=>AbyssInventory.fromJson(inv.toJson()..remove('equipmentSkills')),throwsFormatException);
 });
 test('保存失敗・再起動・再試行で確定値を維持し一度だけ消費',() async {
  final dir=await Directory.systemTemp.createTemp('equipment-draw-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_FailStore(dir);
  AppController controller(LocalStore s)=>AppController(s,equipmentCatalog:catalog,enhancementPolicy:policy,equipmentSkillMaster:master,equipmentSkillSeedRandom:Random(7));
  final c=controller(store);addTearDown(c.dispose);await c.initialize();
  final item=c.state.inventory.addEquipment('equipment:sword',EquipmentSlot.hands,EquipmentRarity.gr);
  c.state.inventory.addStack('item:iron',10);c.state.world.gold=20;
  await store.save(c.state);
  await c.enhanceWorldItem(item.id,0);await c.enhanceWorldItem(item.id,1);
  final expected=EquipmentEnhancementDraw.prepare(c.state.inventory,c.state.inventory.equipment[item.id]!,master)!;
  final before=jsonEncode(c.state.toJson());store.fail=true;
  await expectLater(c.enhanceWorldItem(item.id,2),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);
  final restarted=controller(LocalStore(directory:dir));addTearDown(restarted.dispose);await restarted.initialize();
  final repeated=EquipmentEnhancementDraw.prepare(restarted.state.inventory,restarted.state.inventory.equipment[item.id]!,master)!;
  expect(repeated.toJson(),expected.toJson());
  await restarted.enhanceWorldItem(item.id,2);
  expect(restarted.state.inventory.equipmentSkillHistories[item.id]!.grants.single.toJson(),expected.toJson());
  expect(restarted.state.world.gold,14);expect(restarted.state.inventory.stacks['item:iron'],7);
  await expectLater(restarted.enhanceWorldItem(item.id,2),throwsStateError);
  expect(restarted.state.world.gold,14);
 });
}
