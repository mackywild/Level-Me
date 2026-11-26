import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/world_catalog.dart';

class _Rolls implements Random {
 _Rolls(this.values);
 final List<double> values;
 int calls=0;
 @override double nextDouble()=>values[calls++];
 @override bool nextBool()=>false;
 @override int nextInt(int max)=>0;
}
void main(){
 const now=1700000000000;
 const stats=WorldStats(hp:1000,physical:120,magic:120,defense:100,physicalMax:100,magicMax:100,crit:0.1);
 const enemy=WorldEncounter('p01_main',1,'test','test',10000,100,100,0,main:true);
 const spec=ActiveSkillSpec(id:'skill:test',name:'試験攻撃',powerPercent:200,physicalCost:5,cooldown:2,hits:2);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 WorldState battle({int hp=10000,int extra=5000,int penetration=5000})=>WorldState(hp:1000,physical:100,magic:100,sequence:1,hpAt:now,energyAt:now,lifespan:BigInt.from(100),battle:WorldBattle(id:1,encounterId:enemy.id,stats:stats,enemyHp:hp,encounterSnapshot:enemy,executionVersion:5,equipmentEffects:BattleEquipmentEffects(extraAttack:extra,penetration:penetration),lifeRewardPercent:100,activeSkills:const [spec]));
 test('物理・魔法・多段能動攻撃から一度だけ追撃、独立会心・無消費',(){
  for(final command in [WorldCommand.claw,WorldCommand.magic,null]){
   final rolls=_Rolls([0.5,0.5,if(command==null)...[0.5,0.5],0.499999,0.05,0.5]);
   final engine=WorldEngine(random:rolls);
   final w=battle();
   if(command==null){engine.actActiveSkill(w,spec.id,1,1,now);}
   else{engine.act(w,command,1,1,now);}
   final mainDamage=command==null?320:command==WorldCommand.magic?96:80;
   expect(w.battle!.enemyHp,10000-mainDamage-60);
   expect(w.battle!.log.where((l)=>l.startsWith('追加攻撃')).length,1);
   expect(w.battle!.log.any((l)=>l.startsWith('追加攻撃')&&l.contains('会心！')),true);
   expect(w.physical,command==null?95:command==WorldCommand.claw?96:100);
   expect(w.magic,command==WorldCommand.magic?94:100);
   expect(w.lifespan,BigInt.from(100));expect(rolls.calls,command==null?7:5);
  }
 });
 test('発動境界・非攻撃・撃破後・効果なしは不要な乱数を消費しない',(){
  final rolls=_Rolls([0.5,0.5,0.5]);
  final w=battle();WorldEngine(random:rolls).act(w,WorldCommand.claw,1,1,now);
  expect(w.battle!.enemyHp,9920);expect(rolls.calls,3);
  final guard=_Rolls([]);WorldEngine(random:guard).act(battle(),WorldCommand.guard,1,1,now);expect(guard.calls,0);
  final kill=_Rolls([0.5,0.5]);final target=battle(hp:1);
  WorldEngine(random:kill).act(target,WorldCommand.claw,1,1,now);expect(target.battle,isNull);expect(kill.calls,2);
  final zero=_Rolls([0.5,0.5]);final noExtra=battle(extra:0,penetration:0);
  WorldEngine(random:zero).act(noExtra,WorldCommand.claw,1,1,now);expect(noExtra.battle!.enemyHp,9940);expect(zero.calls,2);
 });
 test('版5保存往復・上限・版4への混入拒否',(){
  final w=battle();final raw=jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>;
  final restored=WorldState.fromJson(raw);
  expect(restored.battle!.equipmentEffects!.extraAttack,5000);
  expect(restored.battle!.equipmentEffects!.penetration,5000);
  final first=WorldState.fromJson(raw),second=WorldState.fromJson(raw);
  WorldEngine().act(first,WorldCommand.claw,1,1,now);WorldEngine().act(second,WorldCommand.claw,1,1,now);
  expect(first.toJson(),second.toJson());
  final b=w.battle!;
  expect(()=>WorldBattle.fromJson(b.toJson()..['executionVersion']=4),throwsFormatException);
  for(final key in ['penetration','extraAttack']){
   final invalid=b.toJson();(invalid['equipmentEffects'] as Map)[key]=5001;
   expect(()=>WorldBattle.fromJson(invalid),throwsFormatException);
  }
 });
}
