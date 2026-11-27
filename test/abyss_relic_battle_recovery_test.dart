import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';
import 'package:level_me/world/abyss_equipment_skill_pool.dart';
import 'package:level_me/world/abyss_relic_skill_master.dart';
import 'package:level_me/world/abyss_relic_trigger_runtime.dart';

RelicEffectSnapshot recovery({int chance=10000,int heal=2500,int magic=4,int? limit=2,bool unsupported=false}){
 final effects=[RelicEffect.battleStartHeal,RelicEffect.turnEndMagicRecovery,if(unsupported)RelicEffect.statusCleanse];
 final master=RelicSkillMaster(rules:[
  for(final e in effects)RelicEffectRule(effect:e,stacking:RelicStacking.additive,chanceCapBps:10000,magnitudeCap:e.maximumMagnitude,maxUses:e==RelicEffect.battleStartHeal?1:limit),
 ],skills:[
  for(final e in effects)RelicSkillDefinition(id:'equipment_relic_skill:${e.name}',name:e.name,rarity:EquipmentSkillRarity.common,effect:e,chanceBpsByLevel:List.filled(10,chance),magnitudeByLevel:List.filled(10,e==RelicEffect.battleStartHeal?heal:e==RelicEffect.turnEndMagicRecovery?magic:0)),
 ]);
 return RelicEffectSnapshot.resolve(master,[for(final e in effects)RelicSkillContribution(skillId:'equipment_relic_skill:${e.name}',level:1)]);
}

void main(){
 const now=1700000000000;
 const stats=WorldStats(hp:101,physical:100,magic:100,defense:100,physicalMax:100,magicMax:100,crit:0);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 WorldState world({int hp=50,int magic=80})=>WorldState(hp:hp,physical:100,magic:magic,hpAt:now,energyAt:now);
 WorldState clone(WorldState w)=>WorldState.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String,dynamic>);
 WorldEngine engine()=>WorldEngine(seedRandom:Random(7));
 void start(WorldEngine e,WorldState w,{RelicEffectSnapshot? effects})=>e.start(w,stats,'p01_main',now,trialRelicEffects:effects??recovery());
 void guard(WorldEngine e,WorldState w)=>e.act(w,WorldCommand.guard,w.battle!.id,w.battle!.turn,now);

 test('生命の残響・魔力循環の回復量、回数、再起動で開始再発動なし',(){
  final e=engine(),w=world();start(e,w);
  expect(w.hp,75);expect(w.battle!.executionVersion,11);
  expect(w.battle!.relicUses,{RelicEffect.battleStartHeal:1});
  final rng=w.battle!.rngState;
  guard(e,w);expect(w.magic,84);expect(w.battle!.rngState,rng);
  final restored=clone(w);expect(restored.toJson(),w.toJson());
  guard(e,restored);expect(restored.magic,88);
  guard(e,restored);expect(restored.magic,88);
  expect(restored.battle!.relicUses,{RelicEffect.battleStartHeal:1,RelicEffect.turnEndMagicRecovery:2});
  expect(restored.battle!.turn,4);
 });
 test('満タンは抽選しない・回復量上限と最低1',(){
  final e=engine(),full=world(hp:101,magic:100);
  start(e,full,effects:recovery(chance:5000));
  final rng=full.battle!.rngState;
  expect(full.battle!.relicUses,isEmpty);
  guard(e,full);expect(full.battle!.rngState,rng);expect(full.battle!.relicUses,isEmpty);
  final capped=world(hp:100,magic:99);
  start(e,capped,effects:recovery(heal:10000));
  expect(capped.hp,101);guard(e,capped);expect(capped.magic,100);
  final one=world(hp:50);start(e,one,effects:recovery(heal:1));expect(one.hp,51);
 });
 test('確率発動のRNGと回数を復元し同じ操作を再現',(){
  final e=engine(),w=world();start(e,w,effects:recovery(chance:5000,limit:null));
  final other=clone(w),old=w.battle!.rngState;
  guard(e,w);guard(engine(),other);
  expect(w.battle!.rngState,isNot(old));expect(other.toJson(),w.toJson());
  final before=jsonEncode(w.toJson());
  expect(()=>e.act(w,WorldCommand.guard,w.battle!.id,w.battle!.turn-1,now),throwsStateError);
  expect(jsonEncode(w.toJson()),before);
 });
 test('勝利・敗北・撤退ではターン終了回復なし',(){
  final e=engine(),win=world();start(e,win);
  e.act(win,WorldCommand.claw,win.battle!.id,1,now);
  expect(win.battle,isNull);expect(win.magic,80);
  final lose=world(hp:1);start(e,lose,effects:recovery(heal:1));
  lose.hp=1;guard(e,lose);expect(lose.battle,isNull);expect(lose.magic,80);
  final retreat=world();start(e,retreat);
  e.act(retreat,WorldCommand.retreat,retreat.battle!.id,1,now);
  expect(retreat.battle,isNull);expect(retreat.magic,80);
 });
 test('版11の欠落・旧版混入・不成立回数/イベント・未接続効果を拒否',(){
  final e=engine(),w=world();start(e,w);
  Map<String,dynamic> raw()=>jsonDecode(jsonEncode(w.battle!.toJson())) as Map<String,dynamic>;
  for(final mutate in <void Function(Map<String,dynamic>)>[
   (j)=>j.remove('relicRecovery'),
   (j)=>j['executionVersion']=8,
   (j)=>j['relicRecovery']['lastEvent']=2,
   (j)=>j['relicRecovery']['effects']['turnEndMagicRecovery']['uses']=1,
   (j)=>j['relicRecovery']['effects']['battleStartHeal']['uses']=2,
   (j)=>j['relicRecovery']['effects']['battleStartHeal']['chanceBps']=10001,
   (j)=>j['relicRecovery']['effects']['statusCleanse']=j['relicRecovery']['effects']['battleStartHeal'],
   (j)=>j['exAttacks']=[],
  ]){final j=raw();mutate(j);expect(()=>WorldBattle.fromJson(j),throwsFormatException);}
  final old=world();e.start(old,stats,'p01_main',now);
  expect(old.battle!.executionVersion,3);expect(old.battle!.toJson().containsKey('relicRecovery'),false);
  expect(clone(old).toJson(),old.toJson());
  final rejected=world(),before=jsonEncode(rejected.toJson());
  expect(()=>start(e,rejected,effects:recovery(unsupported:true)),throwsStateError);
  expect(jsonEncode(rejected.toJson()),before);
 });
}
