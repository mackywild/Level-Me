import 'achievement.dart';
import 'boss.dart';
import 'quest.dart';
import 'stat_type.dart';
import '../world/world_engine.dart';
import '../world/abyss_inventory.dart';
import '../world/abyss_skill.dart';
import '../world/abyss_summon_transaction.dart';
class AppStateData {
 AppStateData({required this.totalExp,required this.stats,required this.quests,required this.achievements,required this.activeDates,required this.boss,required this.completionCount,this.playerHp=100,this.maxPlayerHp=100,this.attackEnergy=0,this.gachaTickets=0,this.lastRecoveryDate='',this.lastKnownLevel=1, Map<String,dynamic>? sessions, List<Map<String,dynamic>>? sessionHistory,WorldState? world,AbyssInventory? inventory,SummonState? summon,SkillState? skills}):sessions=sessions??{},sessionHistory=sessionHistory??[],world=world??WorldState(),inventory=inventory??AbyssInventory(),summon=summon??SummonState(),skills=skills??SkillState();
 final WorldState world;
 final AbyssInventory inventory;
 final SummonState summon;
 final SkillState skills;
 int totalExp,completionCount;
 int playerHp,maxPlayerHp,attackEnergy,gachaTickets,lastKnownLevel;
 String lastRecoveryDate;
 final Map<String,dynamic> sessions;
 final List<Map<String,dynamic>> sessionHistory;
 final Map<StatType,int> stats;
 final List<Quest> quests;
 final List<Achievement> achievements;
 final List<String> activeDates;
 Boss boss;
 static Boss defaultBoss()=>const Boss(id:'shadow',title:'怠惰を喰らう影竜',description:'現実の行動で怠惰の影を討伐せよ',maxHp:300,hp:300,rewardExp:80,defeats:0);
 factory AppStateData.initial()=>AppStateData(totalExp:0,completionCount:0,
  stats:{for(final stat in StatType.values)stat:0},
  quests:[
   Quest(id:'starter-study',title:'基本情報技術者の勉強をする',rewards:const [QuestReward(stat:StatType.intelligence,exp:20),QuestReward(stat:StatType.discipline,exp:5)],createdAt:DateTime.now(),cadence:QuestCadence.daily),
   Quest(id:'starter-workout',title:'筋トレをする',rewards:const [QuestReward(stat:StatType.fitness,exp:15),QuestReward(stat:StatType.discipline,exp:5)],createdAt:DateTime.now(),cadence:QuestCadence.daily),
  ],achievements:[],activeDates:[],boss:defaultBoss());
 Map<String,dynamic> toJson()=>{'totalExp':totalExp,'completionCount':completionCount,
  'stats':{for(final entry in stats.entries)entry.key.name:entry.value},
  'quests':quests.map((e)=>e.toJson()).toList(),
  'achievements':achievements.map((e)=>e.toJson()).toList(),
  'activeDates':activeDates,'boss':boss.toJson(),
  'playerHp':playerHp,'maxPlayerHp':maxPlayerHp,'attackEnergy':attackEnergy,'gachaTickets':gachaTickets,
  'world':world.toJson(),'inventory':inventory.toJson(),'summon':summon.toJson(),'skills':skills.toJson(),'sessions':sessions,'sessionHistory':sessionHistory,'lastRecoveryDate':lastRecoveryDate,'lastKnownLevel':lastKnownLevel};
 factory AppStateData.fromJson(Map<String,dynamic> j) {
  if(j.containsKey('skills')&&j['skills'] is! Map<String,dynamic>)throw const FormatException('Invalid skills');
  final raw=j['stats'] as Map<String,dynamic>? ?? {};
  return AppStateData(totalExp:j['totalExp'] as int? ?? 0,
   world:j.containsKey('world')?WorldState.fromJson(j['world'] as Map<String,dynamic>):null,
   inventory:j.containsKey('inventory')?AbyssInventory.fromJson(j['inventory'] as Map<String,dynamic>):null,
   summon:j.containsKey('summon')?SummonState.fromJson(j['summon'] as Map<String,dynamic>):null,
   skills:j.containsKey('skills')?SkillState.fromJson(j['skills'] as Map<String,dynamic>):null,
   completionCount:j['completionCount'] as int? ?? 0,
   sessions:Map<String,dynamic>.from(j['sessions'] as Map? ?? {}),
   sessionHistory:(j['sessionHistory'] as List? ?? []).map((e)=>Map<String,dynamic>.from(e as Map)).toList(),
   playerHp:j['playerHp'] as int? ?? 100,maxPlayerHp:j['maxPlayerHp'] as int? ?? 100,
   attackEnergy:j['attackEnergy'] as int? ?? 0,gachaTickets:j['gachaTickets'] as int? ?? 0,
   lastRecoveryDate:j['lastRecoveryDate'] as String? ?? '',lastKnownLevel:j['lastKnownLevel'] as int? ?? 1,
   stats:{for(final stat in StatType.values)stat:raw[stat.name] as int? ?? 0},
   quests:(j['quests'] as List<dynamic>? ?? []).map((e)=>Quest.fromJson(e as Map<String,dynamic>)).toList(),
   achievements:(j['achievements'] as List<dynamic>? ?? []).map((e)=>Achievement.fromJson(e as Map<String,dynamic>)).toList(),
   activeDates:(j['activeDates'] as List<dynamic>? ?? []).cast<String>(),
   boss:j['boss'] is Map<String,dynamic>? Boss.fromJson(j['boss'] as Map<String,dynamic>):defaultBoss());
 }
}
