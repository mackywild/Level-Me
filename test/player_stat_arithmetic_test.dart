import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/models/stat_type.dart';
import 'package:level_me/services/level_calculator.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Store extends LocalStore {
 _Store(Directory dir):super(directory:dir);
 bool fail=false;
 @override Future<void> save(AppStateData state) async{
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}

void main(){
 const limit=0x7fffffffffffffff,now=1700000000000;
 const item=EquipmentDefinition(id:'equipment:test',name:'試験装備',slot:EquipmentSlot.head,rarity:EquipmentRarity.n,physical:10,magic:10,defense:10);
 const passive=SkillDefinition(id:'skill:test_stat',name:'試験常時',kind:SkillKind.passive,passiveBonus:PassiveStatBonus(physical:1,magic:1,defense:1));
 final equipment=EquipmentCatalog(const [item]),skills=SkillCatalog(const [passive]);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 WorldStats from({int level=1,int fitness=1,int intelligence=1,int discipline=1,int creativity=1})=>WorldStats.fromRanks(level:level,fitness:fitness,intelligence:intelligence,discipline:discipline,creativity:creativity);
 WorldStats base(int physical,int magic,int defense)=>WorldStats(hp:100,physical:physical,magic:magic,defense:defense,physicalMax:27,magicMax:38,crit:0.05);
 test('二分探索は従来のレベル境界・残EXP・必要EXPを維持する',(){
  var cumulative=0;
  for(var level=1;level<=1000;level++){
   final required=100+25*(level-1);
   for(final remaining in [0,required-1]){
    final progress=LevelCalculator.fromTotalExp(cumulative+remaining);
    expect(progress.level,level);
    expect(progress.expIntoLevel,remaining);
    expect(progress.expToNextLevel,required);
   }
   cumulative+=required;
  }
  expect(LevelCalculator.fromTotalExp(-1).level,1);
  expect(LevelCalculator.statRankFromExp(99),1);
  expect(LevelCalculator.statRankFromExp(100),2);
  expect(()=>LevelCalculator.statRankFromExp(-1),throwsRangeError);
  expect(()=>LevelCalculator.expRequiredForNextLevel(0),throwsRangeError);
  final last=1+(limit-100)~/25;
  expect(LevelCalculator.expRequiredForNextLevel(last),100+25*(last-1));
  expect(()=>LevelCalculator.expRequiredForNextLevel(last+1),throwsRangeError);
 });
 test('最大EXPでもレベルが正確に求まる',(){
  final p=LevelCalculator.fromTotalExp(limit);
  final n=BigInt.from(p.level-1);
  final used=BigInt.from(100)*n+BigInt.from(25)*n*(n-BigInt.one)~/BigInt.two;
  expect(used+BigInt.from(p.expIntoLevel),BigInt.from(limit));
  expect(p.expIntoLevel,inInclusiveRange(0,p.expToNextLevel-1));
  expect(p.expToNextLevel,100+25*(p.level-1));
  expect(LevelCalculator.statRankFromExp(limit),1+limit~/100);
 });
 test('通常能力式・平方根境界・不正ランク・乗算と加算の上限',(){
  for(final r in [1,2,3,4,9,10,25,100,1000]){
   final actual=from(level:r,fitness:r,intelligence:r,discipline:r,creativity:r);
   expect(actual.toJson(),{'hp':100+12*(r-1)+8*(r-1),'physical':40+8*(r-1)+3*(r-1),'magic':45+8*(r-1)+3*(r-1),'defense':10+5*(r-1)+2*(r-1),'physicalMax':25+sqrt(r).floor()*2,'magicMax':35+sqrt(r).floor()*3,'crit':min(0.5,0.05+0.005*(r-1))});
  }
  const root=100000000,square=root*root;
  expect(from(fitness:square-1,intelligence:square-1).physicalMax,25+(root-1)*2);
  expect(from(fitness:square,intelligence:square).magicMax,35+root*3);
  final last=1+(limit-100)~/12;
  expect(from(fitness:last).hp,100+12*(last-1));
  expect(()=>from(fitness:last+1),throwsStateError);
  expect(()=>from(level:limit),throwsStateError);
  expect(()=>from(fitness:limit),throwsStateError);
  expect(()=>from(intelligence:limit),throwsStateError);
  expect(()=>from(discipline:limit),throwsStateError);
  expect(()=>from(level:0),throwsStateError);
  expect(()=>from(fitness:0),throwsStateError);
  expect(()=>from(intelligence:-1),throwsStateError);
  expect(()=>from(discipline:0),throwsStateError);
  expect(()=>from(creativity:0),throwsStateError);
  expect(from(creativity:limit).crit,0.5);
  // 各項単独で表現可能でも、和が上限を超える場合は拒否する。
  expect(()=>from(fitness:last,level:2),throwsStateError);
 });
 test('強化率の中間積・切り捨て・上限を検証',(){
  const disabled=EnhancementScaling.disabled(),proposed=EnhancementScaling.proposed();
  expect(disabled.apply(limit,20),limit);
  expect(proposed.apply(7,1),7);
  expect(proposed.apply(7,20),14);
  expect(proposed.apply(limit~/2,20),limit-1);
  expect(()=>proposed.apply(limit~/2+1,20),throwsStateError);
  expect(()=>disabled.apply(-1,0),throwsStateError);
  expect(()=>proposed.apply(1,21),throwsRangeError);
 });
 test('装備から常時補正まで上限ちょうどは許可し1超過を拒否、原本不変',(){
  final inv=AbyssInventory(),owned=inv.addEquipment(item.id,item.slot,item.rarity);
  inv.equip(owned.id);
  final state=SkillState(),w=WorldState();
  skills.learn(w,state,passive.id);
  skills.equip(w,state,passive.id);
  final before=jsonEncode([inv.toJson(),state.toJson()]);
  final b=base(limit-11,limit-11,limit-11);
  final combined=skills.applyPassive(equipment.apply(b,inv),state);
  expect([combined.physical,combined.magic,combined.defense],[limit,limit,limit]);
  for(final invalid in [base(limit-9,45,10),base(40,limit-9,10),base(40,45,limit-9)]){
   expect(()=>equipment.apply(invalid,inv),throwsStateError);
  }
  for(final invalid in [base(limit-10,45,10),base(40,limit-10,10),base(40,45,limit-10)]){
   expect(()=>skills.applyPassive(equipment.apply(invalid,inv),state),throwsStateError);
  }
  expect(jsonEncode([inv.toJson(),state.toJson()]),before);
  expect(b.physical,limit-11);
 });
 test('実ファイル：巨大EXP・装備保存失敗・再試行・戦闘固定値と再起動',() async{
  final dir=await Directory.systemTemp.createTemp('stat-arithmetic-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,equipmentCatalog:equipment,skillCatalog:skills,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.totalExp=limit;
  c.state.stats[StatType.fitness]=limit;
  c.state.stats[StatType.intelligence]=limit;
  c.state.stats[StatType.discipline]=limit;
  final owned=c.state.inventory.addEquipment(item.id,item.slot,item.rarity);
  await store.save(c.state);
  final original=c.worldStats.toJson();
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final bytes=await primary.readAsString(),before=jsonEncode(c.state.toJson());
  store.fail=true;
  await expectLater(c.equipWorldItem(owned.id),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.fail=false;
  await c.equipWorldItem(owned.id);
  await c.learnWorldSkill(passive.id,expectedGeneration:c.restoreGeneration,expectedRevision:0);
  await c.equipWorldSkill(passive.id,expectedGeneration:c.restoreGeneration,expectedRevision:1);
  final boosted=c.worldStats.toJson();
  for(final key in ['physical','magic','defense']){expect(boosted[key],(original[key] as int)+11);}
  await c.startWorldBattle('p01_main');
  expect(c.state.world.battle!.stats.toJson(),boosted);
  final restored=AppController(LocalStore(directory:dir),equipmentCatalog:equipment,skillCatalog:skills,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.totalExp,limit);
  expect(restored.state.world.battle!.stats.toJson(),boosted);
  expect(restored.worldStats.toJson(),boosted);
  await restored.worldCommand(WorldCommand.retreat,restored.state.world.battle!.id,1,expectedGeneration:restored.restoreGeneration);
  await restored.unequipWorldItem(EquipmentSlot.head);
  expect(restored.worldStats.physical,(original['physical'] as int)+1);
 });
}
