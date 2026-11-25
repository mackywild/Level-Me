import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/achievement.dart';
import '../models/achievement_catalog.dart';
import '../models/app_state.dart';
import '../models/quest.dart';
import '../models/stat_type.dart';
import '../services/level_calculator.dart';
import '../services/local_store.dart';
import '../services/portable_backup.dart';
import '../world/world_engine.dart';
import '../world/abyss_inventory.dart';
import '../world/abyss_equipment.dart';
import '../world/abyss_enhancement.dart';
import '../world/abyss_dismantle.dart';
import '../world/abyss_master.dart';
import '../world/abyss_summon.dart';
import '../world/abyss_summon_transaction.dart';
class AppController extends ChangeNotifier {
 AppController(this._store,{PortableBackup? portableBackup,EquipmentCatalog? equipmentCatalog,SummonCatalog? summonCatalog,Random? summonRandom,Future<AbyssMaster> Function()? loadAbyssMaster,EnhancementPolicy? enhancementPolicy,DismantlePolicy? dismantlePolicy,this.enhancementScaling=const EnhancementScaling.disabled()}):_dismantlePolicy=dismantlePolicy??DismantlePolicy.production,_enhancementPolicy=enhancementPolicy??EnhancementPolicy.production,_loadAbyssMaster=loadAbyssMaster,_summonRandom=summonRandom,_portableBackup=portableBackup,_equipmentCatalog=equipmentCatalog??EquipmentCatalog.production {
  _summonEngine=SummonEngine(catalog:summonCatalog??SummonCatalog.production,equipmentCatalog:this.equipmentCatalog,random:summonRandom);
  _store.validatePlayer=_validateEquipment;
  _portableBackup?.validatePlayer=_validateEquipment;
 }
 void _validateEquipment(AppStateData state){
  equipmentCatalog.validateLoadout(state.inventory);
  _summonEngine.validatePending(state.world,state.summon);
 }
 EquipmentCatalog _equipmentCatalog;
 EquipmentCatalog get equipmentCatalog=>_equipmentCatalog;
 late SummonEngine _summonEngine;
 final Future<AbyssMaster> Function()? _loadAbyssMaster;
 final Random? _summonRandom;
 Future<void>? _masterLoading;
 AbyssMaster? _abyssMaster;
 Future<void> _ensureAbyssMaster() async {
  final loader=_loadAbyssMaster;
  if(loader==null||hasAbyssMaster)return;
  final loading=_masterLoading??=() async {configureAbyssMaster(await loader());}();
  try {await loading;} finally {if(identical(_masterLoading,loading))_masterLoading=null;}
 }
 bool get hasAbyssMaster=>_abyssMaster!=null;
 void configureAbyssMaster(AbyssMaster master){
  if(_ready||_summonBusy||_abyssMaster!=null)throw StateError('Cannot replace master while active');
  _enhancementPolicy.validateMaterials((recipe){
   final material=master.supply(recipe.materialId);
   return material!=null&&material.category=='material'&&material.rarity==recipe.rarity;
  });
  _dismantlePolicy.validateMaterials((recipe){
   final material=master.supply(recipe.materialId);
   return material!=null&&material.category=='material'&&material.rarity==recipe.rarity;
  });
  _abyssMaster=master;
  _equipmentCatalog=master.equipment;
  _summonEngine=SummonEngine(catalog:master.summon,equipmentCatalog:master.equipment,random:_summonRandom);
 }
 String summonRewardName(String id)=>equipmentCatalog.find(id)?.name??_abyssMaster?.supply(id)?.name??id;
 EquipmentRarity get summonHighestUnlocked=>_summonEngine.highestUnlocked(_state.world);
 List<int> get summonWeights=>const SummonPolicy().effectiveWeights(summonHighestUnlocked);
 List<SummonRate> summonRates(SummonPool pool)=>_summonEngine.rates(_state.world,pool);
 String? summonUnavailable(SummonPool pool,int count){
  if(!_ready)return '初期化中';
  if(_summonBusy)return '召喚処理中';
  final pending=_state.summon.pending;
  if(_state.world.battle!=null)return '戦闘中は召喚できません';
  if(pending!=null&&(pending.pool!=pool||pending.rewards.length!=count))return '保留中の召喚を先に確定してください';
  if(count!=1&&count!=10)return '召喚回数が不正です';
  try {
   _summonEngine.validateRequest(world:_state.world,state:_state.summon,pool:pool,count:count,expectedSequence:_state.summon.sequence);
   return null;
  } on StateError catch(error){
   return switch(error.message){
    'Insufficient tickets'=>'召喚券不足',
    'Summon pool incomplete'=>'排出マスター未整備',
    'Summon equipment master mismatch'=>'排出マスター不整合',
    'Pending summon master mismatch'=>'保留中の召喚とマスターが不整合',
    _=>'召喚できません',
   };
  }
 }

 bool _summonBusy=false;
 bool get summonBusy=>_summonBusy;
 Future<SummonReceipt> summonWorldItems(SummonPool pool,int count,int expectedSequence) async {
  if(_summonBusy)throw StateError('Summon in progress');
  _summonBusy=true;
  notifyListeners();
  try {
   return await _transaction(() async {
    if(!_ready)throw StateError('Player not ready');
    final prepared=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
    final alreadyPrepared=prepared.summon.pending!=null;
    _summonEngine.prepare(world:prepared.world,state:prepared.summon,pool:pool,count:count,expectedSequence:expectedSequence);
    if(!alreadyPrepared)await _store.save(prepared);
    _state=prepared;
    final working=AppStateData.fromJson(jsonDecode(jsonEncode(prepared.toJson())) as Map<String,dynamic>);
    final receipt=_summonEngine.commit(world:working.world,inventory:working.inventory,state:working.summon);
    await _store.save(working);
    _state=working;
    return receipt;
   },keepPublishedState:true);
  } finally {
   _summonBusy=false;
   notifyListeners();
  }
 }
 final DismantlePolicy _dismantlePolicy;
 Future<void> setWorldEquipmentFavorite(String id,bool favorite)=>_transaction(() async {
  if(!_ready||_state.world.battle!=null)throw StateError('Equipment protection unavailable');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  working.inventory.setFavorite(id,favorite);
  await _store.save(working);
  _state=working;
  notifyListeners();
 },keepPublishedState:true);
 Future<DismantleRecipe> dismantleWorldItem(String id,int expectedLevel)=>_transaction(() async {
  if(!_ready)throw StateError('Player not ready');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final reward=_dismantlePolicy.dismantle(world:working.world,inventory:working.inventory,catalog:equipmentCatalog,id:id,expectedLevel:expectedLevel);
  await _store.save(working);
  _state=working;
  notifyListeners();
  return reward;
 },keepPublishedState:true);
 final EnhancementPolicy _enhancementPolicy;
 final EnhancementScaling enhancementScaling;
 EnhancementRecipe? enhancementRecipe(EquipmentRarity rarity)=>_enhancementPolicy.recipe(rarity);
 String? enhancementUnavailable(String id,int expectedLevel){
  if(!_ready)return '初期化中';
  try {
   _enhancementPolicy.validate(world:_state.world,inventory:_state.inventory,catalog:equipmentCatalog,id:id,expectedLevel:expectedLevel);
   return null;
  } on StateError catch(error){
   return switch(error.message){
    'Enhancement unavailable in battle'=>'戦闘中は強化できません',
    'Enhancement limit reached'=>'最大強化済み',
    'Enhancement recipe unavailable'=>'強化レシピ未承認',
    'Insufficient gold'=>'G不足',
    'Insufficient materials'=>'素材不足',
    _=>'強化できません',
   };
  }
 }
 Future<EquipmentInstance> enhanceWorldItem(String id,int expectedLevel)=>_transaction(() async {
  if(!_ready)throw StateError('Player not ready');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final result=_enhancementPolicy.enhance(world:working.world,inventory:working.inventory,catalog:equipmentCatalog,id:id,expectedLevel:expectedLevel);
  await _store.save(working);
  _state=working;
  notifyListeners();
  return result;
 },keepPublishedState:true);
 final PortableBackup? _portableBackup;
 final LocalStore _store;
 final WorldEngine worldEngine=WorldEngine();
 WorldStats get worldStats=>equipmentCatalog.apply(WorldStats.fromRanks(level:LevelCalculator.fromTotalExp(_state.totalExp).level,fitness:LevelCalculator.statRankFromExp(_state.stats[StatType.fitness]??0),intelligence:LevelCalculator.statRankFromExp(_state.stats[StatType.intelligence]??0),discipline:LevelCalculator.statRankFromExp(_state.stats[StatType.discipline]??0),creativity:LevelCalculator.statRankFromExp(_state.stats[StatType.creativity]??0)),_state.inventory,scaling:enhancementScaling);
 int get _nowMs=>DateTime.now().millisecondsSinceEpoch;
 Future<void> startWorldBattle(String id)=>_transaction(() async {
  if(!_ready)throw StateError('Player not ready');
  worldEngine.start(_state.world,worldStats,id,_nowMs);
  await _persist();
 });
 Future<void> worldCommand(WorldCommand command,int battleId,int turn)=>_transaction(() async {
  if(!_ready)throw StateError('Player not ready');
  worldEngine.act(_state.world,command,battleId,turn,_nowMs);
  worldEngine.refresh(_state.world,worldStats,_nowMs);
  await _persist();
 });
 Future<void> equipWorldItem(String id)=>_transaction(() async {
  if(!_ready||_state.world.battle!=null)throw StateError('Equipment change unavailable');
  final item=_state.inventory.equipment[id];
  if(item==null)throw StateError('Equipment not owned');
  equipmentCatalog.require(item);
  _state.inventory.equip(id);
  await _persist();
 });
 Future<void> unequipWorldItem(EquipmentSlot slot)=>_transaction(() async {
  if(!_ready||_state.world.battle!=null)throw StateError('Equipment change unavailable');
  _state.inventory.unequip(slot);
  await _persist();
 });
 AppStateData _state=AppStateData.initial();
 bool _ready=false;
 Future<void> _queue=Future<void>.value();
 Future<T> _transaction<T>(Future<T> Function() action,{bool keepPublishedState=false}) {
  final result=_queue.then((_) async {
   final snapshot=jsonEncode(_state.toJson());
   try {return await action();} catch (_) {
    if(!keepPublishedState)_state=AppStateData.fromJson(jsonDecode(snapshot) as Map<String,dynamic>);
    notifyListeners();
    rethrow;
   }
  });
  _queue=result.then<void>((_) {},onError:(Object e,StackTrace st){});
  return result;
 }
 Future<void> saveSession(String questId, Map<String,dynamic> session)=>_transaction(() async {
  final id=session['sessionId'];
  if(id!=null&&_state.sessionHistory.any((h)=>h['sessionId']==id))return;
  _state.sessions[questId]=session;
  await _persist();
 });
 Map<String,dynamic>? sessionFor(String questId){final value=_state.sessions[questId];return value is Map?Map<String,dynamic>.from(value):null;}

 AppStateData get state=>_state;
 bool get ready=>_ready;
 Future<void> initialize() async {
  _ready=false;
  await _ensureAbyssMaster();
  await _portableBackup?.resumePendingRestore();
  final loaded=await _store.load();
  _validateEquipment(loaded);
  _state=loaded;
  _recoverForNewDay();
  worldEngine.refresh(_state.world,worldStats,_nowMs);
  await _store.save(_state);
  _ready=true;
  notifyListeners();
 }
 Future<String> exportPortableBackup()=>_transaction(() async {
  if(!_ready)throw StateError('Player not ready');
  final backup=_portableBackup;
  if(backup==null)throw StateError('Backup unavailable');
  return backup.export();
 });
 Future<void> importPortableBackup(String raw) async {
  await _ensureAbyssMaster();
  PortableBackup.validate(raw,validatePlayer:_validateEquipment);
  final backup=_portableBackup;
  if(backup==null)throw StateError('Backup unavailable');
  await _transaction(() async {
   await backup.restore(raw);
   _ready=false;
   await initialize();
  });
 }
 Future<bool> hasBackup() async {
  // 起動失敗画面の確認処理で暗黙にマスターを再読込しない。
  if(_loadAbyssMaster!=null&&!hasAbyssMaster)return false;
  return _store.hasBackup();
 }
 Future<void> restoreBackup() async {
  await _ensureAbyssMaster();
  await _transaction(() async {
   await _store.restoreBackup();
   await initialize();
  });
 }
 Future<void> addQuest({required String title,required List<QuestReward> rewards,QuestCadence cadence=QuestCadence.oneTime,List<String> reviewQuestionIds=const []}) => _transaction(() async {
  if(title.trim().isEmpty||rewards.isEmpty||rewards.any((r)=>r.exp<=0))throw ArgumentError('Invalid quest');
  if(reviewQuestionIds.isEmpty&&title.trim().startsWith('基本情報：見直し'))throw ArgumentError('Reserved title');
  _state.quests.insert(0,Quest(id:DateTime.now().microsecondsSinceEpoch.toString(),title:title.trim(),rewards:rewards,createdAt:DateTime.now(),cadence:cadence,reviewQuestionIds:List.of(reviewQuestionIds)));
  await _persist();
 });
 bool canManageQuest(Quest q)=>!q.id.startsWith('starter-')&&q.reviewQuestionIds.isEmpty&&!q.title.startsWith('基本情報：見直し');
 Future<void> editQuest(String id,{required String title,required List<QuestReward> rewards,required QuestCadence cadence})=>_transaction(() async {
  final index=_state.quests.indexWhere((q)=>q.id==id);
  if(index<0)throw StateError('Quest not found');
  final q=_state.quests[index];
  if(!canManageQuest(q)||q.archived)throw StateError('Protected quest');
  if(title.trim().isEmpty||title.startsWith('基本情報：見直し')||rewards.isEmpty||rewards.any((r)=>r.exp<1||r.exp>50)||rewards.map((r)=>r.stat).toSet().length!=rewards.length)throw ArgumentError('Invalid quest');
  if((q.completedAt!=null||q.completionKeys.isNotEmpty)&&q.cadence!=cadence)throw StateError('Cannot change cadence after completion');
  _state.quests[index]=Quest(id:q.id,title:title.trim(),rewards:List.of(rewards),createdAt:q.createdAt,completedAt:q.completedAt,cadence:cadence,completionKeys:q.completionKeys,reviewQuestionIds:q.reviewQuestionIds);
  await _persist();
 });
 Future<void> archiveQuest(String id)=>_transaction(() async {
  final index=_state.quests.indexWhere((q)=>q.id==id);
  if(index<0)throw StateError('Quest not found');
  final q=_state.quests[index];
  if(!canManageQuest(q)||_state.sessions.containsKey(id))throw StateError('Protected or active quest');
  _state.quests[index]=Quest.fromJson({...q.toJson(),'archived':true});
  await _persist();
 });
 Future<void> restoreQuest(String id)=>_transaction(() async {
  final index=_state.quests.indexWhere((q)=>q.id==id);
  if(index<0)throw StateError('Quest not found');
  final q=_state.quests[index];
  if(!canManageQuest(q))throw StateError('Protected quest');
  _state.quests[index]=Quest.fromJson({...q.toJson(),'archived':false});
  await _persist();
 });
 Future<void> refreshDay() => _transaction(() async {
  if (!_ready) return;
  final newDay=_state.lastRecoveryDate != _dateKey(DateTime.now());
  if(newDay)_recoverForNewDay();
  final changed=worldEngine.refresh(_state.world,worldStats,_nowMs);
  if(newDay||changed)await _persist();
 });
 Future<void> completeQuest(Quest quest, {int? activeSeconds, List<String> reviewIds = const [], String? sessionId}) => _transaction(() async {
  if(sessionId!=null&&_state.sessionHistory.any((h)=>h['sessionId']==sessionId))return;
  if(activeSeconds!=null && activeSeconds<60)throw ArgumentError('Minimum session duration is 60 seconds');
  final index=_state.quests.indexWhere((q)=>q.id==quest.id);
  if(index<0)return;
  final current=_state.quests[index],now=DateTime.now();
  if(current.archived)throw StateError('Archived quest');
  if((current.id=='starter-study'||current.id=='starter-workout'||current.reviewQuestionIds.isNotEmpty)&&activeSeconds==null)throw ArgumentError('Timed session required');
  if(current.isDoneAt(now)){
   if(activeSeconds!=null){
    _state.sessionHistory.add({'questId':current.id,'sessionId':?sessionId,'seconds':activeSeconds,'finishedAt':now.toIso8601String(),'rewarded':false});
    _state.sessions.remove(current.id);
    _addReview(current,now,reviewIds);
    _rewardWorldEffort(current,activeSeconds,false);
    await _persist();
   }
   return;
  }
  if(activeSeconds!=null){
   _state.sessionHistory.add({'questId':current.id,'sessionId':?sessionId,'seconds':activeSeconds,'finishedAt':now.toIso8601String(),'rewarded':true});
   _state.sessions.remove(current.id);
  }
  _state.quests[index]=current.completed(now);
  _recoverForNewDay();
  _state.completionCount++;
  final beforeLevel=LevelCalculator.fromTotalExp(_state.totalExp).level;
  final multiplier = activeSeconds == null ? 1 : (activeSeconds ~/ 60).clamp(1, 120);
  final rewards = activeSeconds == null ? current.rewards : current.rewards.map((r) => QuestReward(stat:r.stat, exp:max(1, (r.exp * multiplier / 25).round()))).toList();
  _addReview(current,now,reviewIds);
  _grantRewards(rewards);
  _state.attackEnergy=(_state.attackEnergy+rewards.fold<int>(0,(sum,r)=>sum+r.exp)).clamp(0,9999);
  _state.gachaTickets++;
  if(current.rewards.any((r)=>r.stat==StatType.fitness)){
   _state.maxPlayerHp+=2;
   _state.playerHp=(_state.playerHp+20).clamp(0,_state.maxPlayerHp);
  }
  _markTodayActive();
  _checkAchievements();
  _healOnLevelUp(beforeLevel);
  _rewardWorldEffort(current,activeSeconds,LevelCalculator.fromTotalExp(_state.totalExp).level>beforeLevel);
  await _persist();
 });
 void _rewardWorldEffort(Quest current,int? activeSeconds,bool levelUp){
  final study=current.id=='starter-study'||current.reviewQuestionIds.isNotEmpty;
  final workout=current.id=='starter-workout';
  final seconds=activeSeconds==null?0:min(7200,activeSeconds);
  final physical=study?0:workout?max(1,seconds~/120):5;
  final magic=workout?0:study?max(1,seconds~/100):5;
  worldEngine.rewardEffort(_state.world,worldStats,_nowMs,physical:physical,magic:magic,levelUp:levelUp);
 }
 void _addReview(Quest current,DateTime now,List<String> ids){
  final unique=ids.toSet().toList()..sort();
  if(unique.isEmpty)return;
  if(_state.quests.any((q)=>!q.isDoneAt(now)&&q.reviewQuestionIds.length==unique.length&&q.reviewQuestionIds.toSet().containsAll(unique)))return;
  _state.quests.insert(0,Quest(id:'review-${current.id}-${now.microsecondsSinceEpoch}',title:'基本情報：見直し（対象 ${unique.length}問）',rewards:const [QuestReward(stat:StatType.intelligence,exp:10),QuestReward(stat:StatType.discipline,exp:3)],createdAt:now,reviewQuestionIds:unique));
 }
 Future<void> unlockAchievement({required String title,required String description,required StatType stat,required int exp}) => _transaction(() async{
  if(title.trim().isEmpty||exp<=0)return;
  final now=DateTime.now();
  _state.achievements.insert(0,Achievement(id:now.microsecondsSinceEpoch.toString(),title:title.trim(),description:description,stat:stat,exp:exp,unlockedAt:now));
  final beforeLevel=LevelCalculator.fromTotalExp(_state.totalExp).level;
  _grantRewards([QuestReward(stat:stat,exp:exp)]);
  _healOnLevelUp(beforeLevel);
  _markTodayActive();
  _checkAchievements();
  _healOnLevelUp(beforeLevel);
  await _persist();
 });
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
 void _checkAchievements({bool battleOnly=false}){
  for(var pass=0;pass<achievementCatalog.length;pass++){
   var awarded=false;
   for(final rule in achievementCatalog){
    if(battleOnly&&rule.metric!='bosses')continue;
    if(_state.achievements.any((a)=>a.id==rule.id)||achievementMetric(rule)<rule.target)continue;
    _state.achievements.insert(0,Achievement(id:rule.id,title:rule.title,description:rule.description,stat:rule.stat,exp:rule.reward,unlockedAt:DateTime.now()));
    if(rule.reward>0)_grantRewards([QuestReward(stat:rule.stat,exp:rule.reward)]);awarded=true;
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
 Future<BattleResult?> attackBoss({bool magic=false}) => _transaction(() async{
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
   _state.world.gold+=80;
  }else{
   counterDamage=8+(_state.boss.defeats*2).clamp(0,20);
   _state.playerHp=max(0,_state.playerHp-counterDamage);
  }
  _checkAchievements(battleOnly:true);
  await _persist();
  return BattleResult(damage:damage,counterDamage:counterDamage,defeated:defeated,playerKnockedOut:_state.playerHp==0);
 });
 Future<String?> drawBattleReward() => _transaction(() async{
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
   _state.world.gold+=50;
   reward='ゴールド +50 G';
  }
  await _persist();
  return reward;
 });
 void _markTodayActive(){final key=_dateKey(DateTime.now());if(!_state.activeDates.contains(key))_state.activeDates.add(key);}
 String _dateKey(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
 Future<void> _persist() async{await _store.save(_state);notifyListeners();}
}

class BattleResult {
 const BattleResult({required this.damage,required this.counterDamage,required this.defeated,required this.playerKnockedOut});
 final int damage,counterDamage;
 final bool defeated,playerKnockedOut;
}
