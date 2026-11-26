import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/world_catalog.dart';

void main(){
 const now=1700000000000;
 const stats=WorldStats(hp:100,physical:2,magic:2,defense:10,physicalMax:27,magicMax:38,crit:0);
 const spec=ActiveSkillSpec(id:'skill:test',name:'test',powerPercent:100,physicalCost:1,cooldown:5);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 test('最大HP・CD短縮を固定し実行、復元境界を検証',(){
  final engine=WorldEngine(seedRandom:Random(7));
  final w=WorldState(hp:50,hpAt:now,energyAt:now);
  engine.start(w,stats,'p01_main',now,activeSkills:const [spec],equipmentEffects:BattleEquipmentEffects(hp:30000,cooldown:5000));
  final b=w.battle!;
  expect(b.executionVersion,6);expect(b.stats.hp,400);expect(w.hp,50);
  engine.actActiveSkill(w,spec.id,b.id,1,now);
  expect(b.skillCooldowns[spec.id],3);
  final restored=WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
  expect(restored.battle!.stats.hp,400);
  expect(restored.battle!.skillCooldowns[spec.id],3);
  final invalid=b.toJson();(invalid['skillCooldowns'] as Map)[spec.id]=4;
  expect(()=>WorldBattle.fromJson(invalid),throwsFormatException);
  engine.act(restored,WorldCommand.guard,b.id,2,now);
  expect(restored.battle!.skillCooldowns[spec.id],2);
 });
 test('CD境界・固有権能除外・旧版形状',(){
  for(final cd in [0,1,2,3,5,20]){
   final s=ActiveSkillSpec(id:'skill:test',name:'test',powerPercent:100,physicalCost:1,cooldown:cd);
   expect(BattleEquipmentEffects.effectiveCooldown(s,5000),(cd+1)~/2);
   expect(BattleEquipmentEffects.effectiveCooldown(s,0),cd);
  }
  const fixed=ActiveSkillSpec(id:'skill:rewind',name:'test',powerPercent:0,physicalCost:0,cooldown:8,effect:ActiveSkillEffect.rewindHp,lifeCost:90);
  expect(BattleEquipmentEffects.effectiveCooldown(fixed,5000),8);
  final effects=BattleEquipmentEffects(hp:30000,cooldown:5000);
  expect(effects.toJson().length,7);expect(effects.toJson(extended:true).length,9);
  expect(effects.toJson(hpCooldown:true).length,11);
  expect(()=>BattleEquipmentEffects.fromJson(effects.toJson(hpCooldown:true),extended:true),throwsFormatException);
  expect(()=>BattleEquipmentEffects(hp:30001),throwsFormatException);
  expect(()=>BattleEquipmentEffects(cooldown:5001),throwsFormatException);
 });
}
