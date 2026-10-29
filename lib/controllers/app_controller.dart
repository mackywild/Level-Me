import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/achievement.dart';
import '../models/achievement_catalog.dart';
import '../models/app_state.dart';
import '../models/quest.dart';
import '../models/stat_type.dart';
import '../services/level_calculator.dart';
import '../services/local_store.dart';
class AppController extends ChangeNotifier {
 AppController(this._store);
 final LocalStore _store;
 AppStateData _state=AppStateData.initial();
 bool _ready=false;
 AppStateData get state=>_state;
 bool get ready=>_ready;
 Future<void> initialize() async{_state=await _store.load();_recoverForNewDay();_ready=true;await _persist();}
 Future<void> addQuest({required String title,required List<QuestReward> rewards,QuestCadence cadence=QuestCadence.oneTime,List<String> reviewQuestionIds=const []}) async {
  if(title.trim().isEmpty||rewards.isEmpty||rewards.any((r)=>r.exp<=0))return;
  _state.quests.insert(0,Quest(id:DateTime.now().microsecondsSinceEpoch.toString(),title:title.trim(),rewards:rewards,createdAt:DateTime.now(),cadence:cadence,reviewQuestionIds:List.of(reviewQuestionIds)));
  await _persist();
 }
 Future<void> completeQuest(Quest quest) async{
  final index=_state.quests.indexWhere((q)=>q.id==quest.id);
  if(index<0)return;
  final current=_state.quests[index],now=DateTime.now();
  if(current.isDoneAt(now))return;
  _state.quests[index]=current.completed(now);
  _recoverForNewDay();
  _state.completionCount++;
  final beforeLevel=LevelCalculator.fromTotalExp(_state.totalExp).level;
  _grantRewards(current.rewards);
  _state.attackEnergy=(_state.attackEnergy+current.totalExp).clamp(0,9999);
  _state.gachaTickets++;
  if(current.rewards.any((r)=>r.stat==StatType.fitness)){
   _state.maxPlayerHp+=2;
   _state.playerHp=(_state.playerHp+20).clamp(0,_state.maxPlayerHp);
  }
  _healOnLevelUp(beforeLevel);
  _markTodayActive();
  _checkAchievements();
  await _persist();
 }
 Future<void> unlockAchievement({required String title,required String description,required StatType stat,required int exp}) async{
  if(title.trim().isEmpty||exp<=0)return;
  final now=DateTime.now();
  _state.achievements.insert(0,Achievement(id:now.microsecondsSinceEpoch.toString(),title:title.trim(),description:description,stat:stat,exp:exp,unlockedAt:now));
  final beforeLevel=LevelCalculator.fromTotalExp(_state.totalExp).level;
  _grantRewards([QuestReward(stat:stat,exp:exp)]);
  _healOnLevelUp(beforeLevel);
  _markTodayActive();
  _checkAchievements();
  await _persist();
 }
 int get currentStreak{
  final dates=_state.activeDates.toSet();
  if(dates.isEmpty)return 0;
  var cursor=DateTime.now();cursor=DateTime(cursor.year,cursor.month,cursor.day);
  if(!dates.contains(_dateKey(cursor)))cursor=cursor.subtract(const Duration(days:1));
  var streak=0;
  while(dates.contains(_dateKey(cursor))){streak++;cursor=cursor.subtract(const Duration(days:1));}
  return streak;
 }
 int achievementMetric(AchievementRule rule)=>switch(rule.metric){
  'quests'=>_state.completionCount,'bosses'=>_state.boss.defeats,
  'streak'=>currentStreak,'level'=>LevelCalculator.fromTotalExp(_state.totalExp).level,
  _=>_state.stats[StatType.values.byName(rule.metric)]??0,
 };
 void _checkAchievements(){
  for(var pass=0;pass<achievementCatalog.length;pass++){
   var awarded=false;
   for(final rule in achievementCatalog){
    if(_state.achievements.any((a)=>a.id==rule.id)||achievementMetric(rule)<rule.target)continue;
    _state.achievements.insert(0,Achievement(id:rule.id,title:rule.title,description:rule.description,stat:rule.stat,exp:rule.reward,unlockedAt:DateTime.now()));
    _grantRewards([QuestReward(stat:rule.stat,exp:rule.reward)]);awarded=true;
   }
   if(!awarded)break;
  }
 }
 void _grantRewards(List<QuestReward> rewards){
  for(final r in rewards){_state.stats[r.stat]=(_state.stats[r.stat]??0)+r.exp;_state.totalExp+=r.exp;}
 }
 void _recoverForNewDay(){
  final today=_dateKey(DateTime.now());
  if(_state.lastRecoveryDate!=today){
   _state.lastRecoveryDate=today;
   _state.playerHp=_state.maxPlayerHp;
  }
 }
 void _healOnLevelUp(int previousLevel){
  final level=LevelCalculator.fromTotalExp(_state.totalExp).level;
  if(level>previousLevel){_state.playerHp=_state.maxPlayerHp;}
  _state.lastKnownLevel=level;
 }
 Future<BattleResult?> attackBoss({bool magic=false}) async{
  _recoverForNewDay();
  if(_state.playerHp<=0||_state.attackEnergy<=0){await _persist();return null;}
  final energy=min(_state.attackEnergy,magic?35:25);
  _state.attackEnergy-=energy;
  final power=_state.stats[magic?StatType.intelligence:StatType.fitness]??0;
  final damage=max(1,energy+sqrt(power).floor()*(magic?3:2));
  final defeated=_state.boss.hp<=damage;
  _state.boss=_state.boss.damage(damage);
  var counterDamage=0;
  if(defeated){
   _grantRewards([QuestReward(stat:StatType.discipline,exp:_state.boss.rewardExp)]);
  }else{
   counterDamage=8+(_state.boss.defeats*2).clamp(0,20);
   _state.playerHp=max(0,_state.playerHp-counterDamage);
  }
  _checkAchievements();
  await _persist();
  return BattleResult(damage:damage,counterDamage:counterDamage,defeated:defeated,playerKnockedOut:_state.playerHp==0);
 }
 Future<String?> drawBattleReward() async{
  if(_state.gachaTickets<=0)return null;
  _state.gachaTickets--;
  final roll=Random.secure().nextInt(100);
  String reward;
  if(roll<15){
   _state.attackEnergy=(_state.attackEnergy+60).clamp(0,9999);
   reward='大当たり！ 攻撃エネルギー +60';
  }else if(roll<50){
   _state.attackEnergy=(_state.attackEnergy+30).clamp(0,9999);
   reward='攻撃エネルギー +30';
  }else if(roll<80){
   _state.attackEnergy=(_state.attackEnergy+15).clamp(0,9999);
   reward='攻撃エネルギー +15';
  }else{
   final beforeLevel=LevelCalculator.fromTotalExp(_state.totalExp).level;
   _grantRewards([const QuestReward(stat:StatType.creativity,exp:10)]);
   _healOnLevelUp(beforeLevel);
   reward='創造力経験値 +10';
  }
  await _persist();
  return reward;
 }
 void _markTodayActive(){final key=_dateKey(DateTime.now());if(!_state.activeDates.contains(key))_state.activeDates.add(key);}
 String _dateKey(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
 Future<void> _persist() async{await _store.save(_state);notifyListeners();}
}

class BattleResult {
 const BattleResult({required this.damage,required this.counterDamage,required this.defeated,required this.playerKnockedOut});
 final int damage,counterDamage;
 final bool defeated,playerKnockedOut;
}
