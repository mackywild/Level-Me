import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/achievement.dart';
import 'package:level_me/models/achievement_catalog.dart';
import 'package:level_me/models/boss.dart';
import 'package:level_me/models/quest.dart';
import 'package:level_me/models/stat_type.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/reward_arithmetic.dart';
import 'package:level_me/world/world_catalog.dart';

class _Roll implements Random {
 _Roll(this.value);
 int value;
 @override int nextInt(int max)=>value;
 @override double nextDouble()=>0.5;
 @override bool nextBool()=>false;
}

void main(){
 const limit=0x7fffffffffffffff,now=1700000000000;
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 late Directory dir;
 late LocalStore store;
 late AppController c;
 late _Roll roll;
 setUp(() async{
  dir=await Directory.systemTemp.createTemp('quest-reward-boundary-');
  addTearDown(()=>dir.delete(recursive:true));
  store=LocalStore(directory:dir);
  roll=_Roll(99);
  c=AppController(store,clockMs:()=>now,legacyRewardRandom:roll);
  addTearDown(c.dispose);
  await c.initialize();
 });
 void alreadyAwarded(){
  for(final rule in achievementCatalog){
   c.state.achievements.add(Achievement(id:rule.id,title:rule.title,description:rule.description,stat:rule.stat,exp:rule.reward,unlockedAt:DateTime.fromMillisecondsSinceEpoch(now)));
  }
 }
 Future<Quest> quest(List<QuestReward> rewards) async{
  await c.addQuest(title:'境界試験',rewards:rewards);
  return c.state.quests.first;
 }
 Future<void> reject(Future<dynamic> Function() operation) async{
  await store.save(c.state);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final backup=File('${primary.path}.bak');
  final bytes=await primary.readAsString(),before=jsonEncode(c.state.toJson());
  final previous=await backup.exists()?await backup.readAsString():null;
  await expectLater(operation(),throwsStateError);
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  expect(await backup.exists()?await backup.readAsString():null,previous);
 }
 Boss boss({int hp=1,int defeats=0})=>Boss(id:'shadow',title:'試験',description:'境界',maxHp:300,hp:hp,rewardExp:80,defeats:defeats);
 test('整数境界・上限付き回復・時間EXPの従来丸め',(){
  expect(RewardArithmetic.add(limit-1,1),limit);
  expect(()=>RewardArithmetic.add(limit,1),throwsStateError);
  expect(()=>RewardArithmetic.add(-1,1),throwsStateError);
  expect(RewardArithmetic.cappedAdd(limit-1,limit,limit),limit);
  expect(RewardArithmetic.cappedAdd(limit,60,9999),9999);
  for(var exp=1;exp<=50;exp++){
   for(var multiplier=1;multiplier<=120;multiplier++){
    expect(RewardArithmetic.timedExp(exp,multiplier),max(1,(exp*multiplier/25).round()));
   }
  }
  expect(RewardArithmetic.timedExp(limit,25),limit);
  expect(()=>RewardArithmetic.timedExp(limit,26),throwsStateError);
  expect(()=>RewardArithmetic.timedExp(0,25),throwsStateError);
 });
 test('総EXP・属性EXPの上限ちょうどを許可し再起動後の二重付与を防ぐ',() async{
  alreadyAwarded();
  final q=await quest(const [QuestReward(stat:StatType.social,exp:1)]);
  c.state.totalExp=limit-1;
  c.state.stats[StatType.social]=limit-1;
  c.state.attackEnergy=9999;
  c.state.gachaTickets=limit-1;
  await store.save(c.state);
  await c.completeQuest(q);
  expect(c.state.totalExp,limit);
  expect(c.state.stats[StatType.social],limit);
  expect(c.state.attackEnergy,9999);
  expect(c.state.gachaTickets,limit);
  final restored=AppController(LocalStore(directory:dir),clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.totalExp,limit);
  final before=jsonEncode(restored.state.toJson());
  await restored.completeQuest(q);
  expect(jsonEncode(restored.state.toJson()),before);
 });
 test('複数報酬の総EXPまたは同一属性の超過は全件取り消す',() async{
  alreadyAwarded();
  final q=await quest(const [QuestReward(stat:StatType.social,exp:1),QuestReward(stat:StatType.social,exp:2)]);
  c.state.totalExp=limit-2;
  await reject(()=>c.completeQuest(q));
  c.state.totalExp=0;
  c.state.stats[StatType.social]=limit-2;
  await reject(()=>c.completeQuest(q));
  c.state.stats[StatType.social]=0;
  await c.completeQuest(q);
  expect(c.state.totalExp,3);
  expect(c.state.stats[StatType.social],3);
 });
 test('時間倍率超過・件数・券・最大HP超過はセッション含め非確定',() async{
  alreadyAwarded();
  final timed=await quest(const [QuestReward(stat:StatType.social,exp:limit)]);
  await c.saveSession(timed.id,{'sessionId':'timed','seconds':7200});
  await reject(()=>c.completeQuest(timed,activeSeconds:7200,sessionId:'timed',reviewIds:['A1']));
  final q=await quest(const [QuestReward(stat:StatType.fitness,exp:1)]);
  c.state.completionCount=limit;
  await reject(()=>c.completeQuest(q));
  c.state.completionCount=0;
  c.state.gachaTickets=limit;
  await reject(()=>c.completeQuest(q));
  c.state.gachaTickets=0;
  c.state.maxPlayerHp=limit-1;
  await reject(()=>c.completeQuest(q));
  c.state.maxPlayerHp=limit-2;
  await c.completeQuest(q);
  expect(c.state.maxPlayerHp,limit);
  expect(c.state.completionCount,1);
 });
 test('称号の追加EXP超過は称号もクエストも保存せず、手動称号も取り消す',() async{
  final q=await quest(const [QuestReward(stat:StatType.social,exp:1)]);
  c.state.totalExp=limit-1;
  await reject(()=>c.completeQuest(q));
  expect(c.state.achievements,isEmpty);
  await reject(()=>c.unlockAchievement(title:'境界称号',description:'試験',stat:StatType.social,exp:2));
  expect(c.state.achievements,isEmpty);
 });
 test('旧ボスのGと討伐回数は超過拒否、非致死時の巨大討伐数も安全',() async{
  alreadyAwarded();
  c.state.attackEnergy=25;
  c.state.boss=boss(defeats:limit);
  await reject(()=>c.attackBoss());
  c.state.boss=boss(defeats:limit-1);
  c.state.world.gold=limit-79;
  await reject(()=>c.attackBoss());
  c.state.world.gold=limit-80;
  await c.attackBoss();
  expect(c.state.world.gold,limit);
  expect(c.state.boss.defeats,limit);
  expect(c.state.attackEnergy,0);
  c.state.attackEnergy=25;
  c.state.boss=boss(hp:300,defeats:limit);
  final hit=await c.attackBoss();
  expect(hit!.defeated,false);
  expect(hit.counterDamage,28);
  expect(c.state.boss.defeats,limit);
 });
 test('旧ガチャのG超過時は券を返し、上限ちょうどとエネルギー飽和を許可',() async{
  c.state.gachaTickets=2;
  c.state.world.gold=limit-49;
  await reject(()=>c.drawBattleReward());
  c.state.world.gold=limit-50;
  await c.drawBattleReward();
  expect(c.state.world.gold,limit);
  expect(c.state.gachaTickets,1);
  roll.value=0;
  c.state.attackEnergy=limit;
  await c.drawBattleReward();
  expect(c.state.attackEnergy,9999);
  expect(c.state.gachaTickets,0);
 });
}
