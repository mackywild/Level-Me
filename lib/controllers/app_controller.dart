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
 Future<void> initialize() async{_state=await _store.load();_ready=true;notifyListeners();}
 Future<void> addQuest({required String title,required List<QuestReward> rewards,QuestCadence cadence=QuestCadence.oneTime}) async {
  if(title.trim().isEmpty||rewards.isEmpty||rewards.any((r)=>r.exp<=0))return;
  _state.quests.insert(0,Quest(id:DateTime.now().microsecondsSinceEpoch.toString(),title:title.trim(),rewards:rewards,createdAt:DateTime.now(),cadence:cadence));
  await _persist();
 }
 Future<void> completeQuest(Quest quest) async{
  final index=_state.quests.indexWhere((q)=>q.id==quest.id);
  if(index<0)return;
  final current=_state.quests[index],now=DateTime.now();
  if(current.isDoneAt(now))return;
  _state.quests[index]=current.completed(now);
  _state.completionCount++;
  _grantRewards(current.rewards);
  final damage=current.totalExp.clamp(1,100);
  final killed=_state.boss.hp<=damage;
  _state.boss=_state.boss.damage(damage);
  if(killed)_grantRewards([QuestReward(stat:StatType.discipline,exp:_state.boss.rewardExp)]);
  _markTodayActive();
  _checkAchievements();
  await _persist();
 }
 Future<void> unlockAchievement({required String title,required String description,required StatType stat,required int exp}) async{
  if(title.trim().isEmpty||exp<=0)return;
  final now=DateTime.now();
  _state.achievements.insert(0,Achievement(id:now.microsecondsSinceEpoch.toString(),title:title.trim(),description:description,stat:stat,exp:exp,unlockedAt:now));
  _grantRewards([QuestReward(stat:stat,exp:exp)]);
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
 void _markTodayActive(){final key=_dateKey(DateTime.now());if(!_state.activeDates.contains(key))_state.activeDates.add(key);}
 String _dateKey(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
 Future<void> _persist() async{await _store.save(_state);notifyListeners();}
}
