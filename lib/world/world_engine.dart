import 'dart:math';
import 'world_catalog.dart';

enum BattleBuff { attack, defense, regeneration, critical, evasion, energyDiscount, lethalProtection, regenerationSuppression }

extension BattleBuffRules on BattleBuff {
 int get percent=>switch(this){BattleBuff.attack=>25,BattleBuff.defense=>40,BattleBuff.regeneration=>5,BattleBuff.critical=>25,BattleBuff.evasion=>20,BattleBuff.energyDiscount=>30,BattleBuff.lethalProtection=>100,BattleBuff.regenerationSuppression=>50};
 int get duration=>switch(this){BattleBuff.regeneration=>5,BattleBuff.evasion=>2,BattleBuff.lethalProtection=>1,_=>3};
 String get label=>switch(this){BattleBuff.attack=>'攻撃強化',BattleBuff.defense=>'防御強化',BattleBuff.regeneration=>'継続回復',BattleBuff.critical=>'会心率上昇',BattleBuff.evasion=>'回避率上昇',BattleBuff.energyDiscount=>'エネルギー消費軽減',BattleBuff.lethalProtection=>'致死耐性',BattleBuff.regenerationSuppression=>'敵再生抑制'};
 bool get isCharge=>this==BattleBuff.lethalProtection;
 String get description=>isCharge?'致死ダメージ1回をHP1で耐える（戦闘終了まで）':'$label $percent% / $durationターン';
}

enum BattleStatus { poison }

extension BattleStatusRules on BattleStatus {
 int get duration=>3;
 String get label=>'毒';
}

enum WorldCommand { claw, heavyClaw, magic, guard, slow, retreat, accelerate, stopTime, compositeClaw }

class WorldStats {
 const WorldStats({required this.hp,required this.physical,required this.magic,required this.defense,required this.physicalMax,required this.magicMax,required this.crit});
 final int hp,physical,magic,defense,physicalMax,magicMax;
 final double crit;
 factory WorldStats.fromRanks({required int level,required int fitness,required int intelligence,required int discipline,required int creativity})=>WorldStats(
  hp:100+12*(fitness-1)+8*(level-1),
  physical:40+8*(fitness-1)+3*(level-1),
  magic:45+8*(intelligence-1)+3*(level-1),
  defense:10+5*(discipline-1)+2*(level-1),
  physicalMax:25+sqrt(fitness).floor()*2,
  magicMax:35+sqrt(intelligence).floor()*3,
  crit:min(0.5,0.05+0.005*(creativity-1)),
 );
 Map<String,dynamic> toJson()=>{'hp':hp,'physical':physical,'magic':magic,'defense':defense,'physicalMax':physicalMax,'magicMax':magicMax,'crit':crit};
 factory WorldStats.fromJson(Map<String,dynamic> j)=>WorldStats(hp:j['hp'] as int,physical:j['physical'] as int,magic:j['magic'] as int,defense:j['defense'] as int,physicalMax:j['physicalMax'] as int,magicMax:j['magicMax'] as int,crit:(j['crit'] as num).toDouble());
}

/// Version 1: Park–Miller PRNG. All arithmetic fits signed 64-bit.
class BattleRandom {
 static const version=1,modulus=2147483647;
 static int validate(Object? value){
  if(value is! int||value<1||value>=modulus)throw const FormatException('Invalid battle RNG state');
  return value;
 }
 static int legacySeed(int id,int turn)=>((BigInt.from(id)*BigInt.from(48271)+BigInt.from(turn))%BigInt.from(modulus-1)).toInt()+1;
 static double next(WorldBattle battle){
  battle._rngState=(battle._rngState*48271)%modulus;
  return (battle._rngState-1)/(modulus-1);
 }
}

/// 戦闘開始時に固定する、承認済み能動スキルの実行定義。
enum ActiveSkillEffect { physical, foresight, accelerationAttack, repairHp, timeCleanse, rewindHp }

class ActiveSkillSpec {
 const ActiveSkillSpec({required this.id,required this.name,required this.powerPercent,required this.physicalCost,required this.cooldown,this.hits=1,this.effect=ActiveSkillEffect.physical,this.lifeCost=0});
 final String id,name;
 final int powerPercent,physicalCost,cooldown,hits,lifeCost;
 final ActiveSkillEffect effect;
 void validate(){
  if(!id.startsWith('skill:')||id.length<=6||name.trim().isEmpty||cooldown<0||cooldown>20||!_validEffect)throw const FormatException('Invalid active skill spec');
 }
 /// 試験候補の回復割合。実行定義のIDと効果種別から固定する。
 int get repairPercent=>effect!=ActiveSkillEffect.repairHp?0:switch(id){
  'skill:wound_repair'=>10,
  'skill:body_repair'=>25,
  'skill:life_rewind'=>50,
  'skill:full_repair'=>100,
  _=>0,
 };
 bool get _validEffect=>switch(effect){
  ActiveSkillEffect.physical=>powerPercent>=1&&powerPercent<=500&&hits>=1&&hits<=10&&powerPercent*hits<=500&&physicalCost>=1&&physicalCost<=100&&lifeCost==0,
  ActiveSkillEffect.foresight=>powerPercent==0&&physicalCost==0&&hits==1&&lifeCost==14&&cooldown>=1,
  ActiveSkillEffect.accelerationAttack=>physicalCost==0&&cooldown>=1&&((id=='skill:speed_claw'&&powerPercent==250&&hits==1&&lifeCost==10)||(id=='skill:gale_claws'&&powerPercent==50&&hits==8&&lifeCost==45)),
  ActiveSkillEffect.repairHp=>powerPercent==0&&physicalCost==0&&hits==1&&cooldown>=1&&repairPercent>0&&lifeCost==(switch(repairPercent){10=>7,25=>21,50=>180,100=>365,_=>0}),
  ActiveSkillEffect.timeCleanse=>id=='skill:time_cleanse'&&powerPercent==0&&physicalCost==0&&hits==1&&lifeCost==30&&cooldown>=1,
  ActiveSkillEffect.rewindHp=>id=='skill:rewind'&&powerPercent==0&&physicalCost==0&&hits==1&&lifeCost==90&&cooldown==8,
 };
 Map<String,dynamic> toJson()=>{'id':id,'name':name,'powerPercent':powerPercent,'physicalCost':physicalCost,'cooldown':cooldown,'hits':hits,'effect':effect.name,'lifeCost':lifeCost};
 factory ActiveSkillSpec.fromJson(Map<String,dynamic> j){
  if(j['id'] is! String||j['name'] is! String||j['powerPercent'] is! int||j['physicalCost'] is! int||j['cooldown'] is! int)throw const FormatException('Invalid active skill spec');
  final hits=j.containsKey('hits')?j['hits']:1;
  if(hits is! int)throw const FormatException('Invalid skill hit count');
  final rawEffect=j.containsKey('effect')?j['effect']:'physical';
  final lifeCost=j.containsKey('lifeCost')?j['lifeCost']:0;
  final matches=ActiveSkillEffect.values.where((e)=>e.name==rawEffect);
  if(matches.isEmpty||lifeCost is! int)throw const FormatException('Invalid active skill effect');
  final spec=ActiveSkillSpec(effect:matches.single,lifeCost:lifeCost,hits:hits,id:j['id'] as String,name:j['name'] as String,powerPercent:j['powerPercent'] as int,physicalCost:j['physicalCost'] as int,cooldown:j['cooldown'] as int);
  spec.validate();
  return spec;
 }
}

/// 試験用の寿命報酬補正。装着効果を戦闘開始時に固定する。
enum LifeRewardBonus {
 timeAbsorption('skill:time_absorption',10),
 predatorInstinct('skill:predator_instinct',20);
 const LifeRewardBonus(this.skillId,this.percent);
 final String skillId;
 final int percent;
 static void validate(List<LifeRewardBonus> bonuses){
  if(bonuses.length>2||bonuses.toSet().length!=bonuses.length)throw const FormatException('Invalid life reward bonuses');
 }
 static BigInt reward(int base,List<LifeRewardBonus> bonuses){
  validate(bonuses);
  if(base<0)throw const FormatException('Invalid life reward');
  final percent=bonuses.fold<int>(100,(sum,b)=>sum+b.percent);
  return BigInt.from(base)*BigInt.from(percent)~/BigInt.from(100);
 }
}

class WorldBattle {
 WorldBattle({required this.id,required this.encounterId,required this.stats,required this.enemyHp,this.turn=1,this.slowTurns=0,this.acceleratedClaws=0,this.stopCooldown=0,this.energyRemainder=0,this.hpRemainder=0,List<String>? log,Map<BattleBuff,int>? buffs,Map<BattleStatus,int>? statuses,List<ActiveSkillSpec> activeSkills=const [],Map<String,int>? skillCooldowns,int? rngState,({int startHp,int? previousHp})? rewindHistory,List<LifeRewardBonus> lifeRewardBonuses=const []}):lifeRewardBonuses=List.unmodifiable(lifeRewardBonuses),_rewindHistory=rewindHistory,log=log??[],_buffs=Map.of(buffs??{}),_statuses=Map.of(statuses??{}),activeSkills=List.unmodifiable(activeSkills),_skillCooldowns=Map.of(skillCooldowns??{}),_rngState=BattleRandom.validate(rngState??BattleRandom.legacySeed(id,turn));
 final int id;
 final String encounterId;
 final WorldStats stats;
 final int energyRemainder,hpRemainder;
 int enemyHp,turn,slowTurns,acceleratedClaws,stopCooldown;
 final List<String> log;
 ({int startHp,int? previousHp})? _rewindHistory;
 int? get previousTurnHp=>_rewindHistory?.previousHp;
 int _rngState;
 int get rngState=>_rngState;
 final Map<BattleBuff,int> _buffs;
 final Map<BattleStatus,int> _statuses;
 final List<ActiveSkillSpec> activeSkills;
 final List<LifeRewardBonus> lifeRewardBonuses;
 final Map<String,int> _skillCooldowns;
 Map<String,int> get skillCooldowns=>Map.unmodifiable(_skillCooldowns);
 Map<BattleStatus,int> get statuses=>Map.unmodifiable(_statuses);
 Map<BattleBuff,int> get buffs=>Map.unmodifiable(_buffs);
 Map<String,dynamic> toJson()=>{'id':id,'encounterId':encounterId,'stats':stats.toJson(),'enemyHp':enemyHp,'turn':turn,'slowTurns':slowTurns,'acceleratedClaws':acceleratedClaws,'stopCooldown':stopCooldown,'energyRemainder':energyRemainder,'hpRemainder':hpRemainder,'log':log,'rngVersion':BattleRandom.version,'rngState':_rngState,'activeSkills':activeSkills.map((s)=>s.toJson()).toList(),'skillCooldowns':Map<String,int>.of(_skillCooldowns),if(lifeRewardBonuses.isNotEmpty)'lifeRewardBonuses':lifeRewardBonuses.map((b)=>b.name).toList(),if(_rewindHistory case final history?)'rewindHistory':{'turn':turn,'startHp':history.startHp,'previousHp':history.previousHp},'statuses':{for(final entry in _statuses.entries)entry.key.name:entry.value},'buffs':{for(final entry in _buffs.entries)entry.key.name:entry.value}};
 factory WorldBattle.fromJson(Map<String,dynamic> j)=>WorldBattle(id:j['id'] as int,encounterId:j['encounterId'] as String,stats:WorldStats.fromJson(j['stats'] as Map<String,dynamic>),enemyHp:j['enemyHp'] as int,turn:j['turn'] as int,slowTurns:j['slowTurns'] as int,acceleratedClaws:j['acceleratedClaws'] as int? ?? 0,stopCooldown:j['stopCooldown'] as int? ?? 0,energyRemainder:j['energyRemainder'] as int? ?? 0,hpRemainder:j['hpRemainder'] as int? ?? 0,log:List<String>.from(j['log'] as List),buffs:_decodeBuffs(j),statuses:_decodeStatuses(j),activeSkills:_decodeActiveSkills(j),skillCooldowns:_decodeSkillCooldowns(j),rngState:_decodeRng(j),rewindHistory:_decodeRewindHistory(j),lifeRewardBonuses:_decodeLifeRewardBonuses(j));
 static List<LifeRewardBonus> _decodeLifeRewardBonuses(Map<String,dynamic> j){
  if(!j.containsKey('lifeRewardBonuses'))return const [];
  final raw=j['lifeRewardBonuses'];
  if(raw is! List||raw.isEmpty||raw.length>2)throw const FormatException('Invalid life reward bonuses');
  final bonuses=<LifeRewardBonus>[];
  for(final value in raw){
   final matches=LifeRewardBonus.values.where((b)=>b.name==value);
   if(matches.isEmpty)throw const FormatException('Unknown life reward bonus');
   bonuses.add(matches.single);
  }
  LifeRewardBonus.validate(bonuses);
  return bonuses;
 }
 static ({int startHp,int? previousHp})? _decodeRewindHistory(Map<String,dynamic> j){
  final equipped=_decodeActiveSkills(j).any((s)=>s.effect==ActiveSkillEffect.rewindHp);
  if(!j.containsKey('rewindHistory')){
   if(equipped)throw const FormatException('Missing rewind history');
   return null;
  }
  final raw=j['rewindHistory'];
  if(!equipped||raw is! Map<String,dynamic>||raw.length!=3||!raw.containsKey('previousHp'))throw const FormatException('Invalid rewind history');
  final turn=j['turn'],maximum=WorldStats.fromJson(j['stats'] as Map<String,dynamic>).hp;
  final recordedTurn=raw['turn'],start=raw['startHp'],previous=raw['previousHp'];
  if(turn is! int||turn<1||recordedTurn is! int||recordedTurn!=turn||start is! int||start<1||start>maximum)throw const FormatException('Invalid rewind history');
  if(turn==1){
   if(previous!=null)throw const FormatException('Invalid first turn rewind history');
   return (startHp:start,previousHp:null);
  }
  if(previous is! int||previous<1||previous>maximum)throw const FormatException('Invalid previous turn HP');
  return (startHp:start,previousHp:previous);
 }
 static List<ActiveSkillSpec> _decodeActiveSkills(Map<String,dynamic> j){
  final raw=j.containsKey('activeSkills')?j['activeSkills']:const [];
  if(raw is! List||raw.length>6)throw const FormatException('Invalid active skill snapshot');
  final ids=<String>{};
  return raw.map((row){
   if(row is! Map<String,dynamic>)throw const FormatException('Invalid active skill snapshot');
   final spec=ActiveSkillSpec.fromJson(row);
   if(!ids.add(spec.id))throw const FormatException('Duplicate active skill snapshot');
   return spec;
  }).toList();
 }
 static Map<String,int> _decodeSkillCooldowns(Map<String,dynamic> j){
  final raw=j.containsKey('skillCooldowns')?j['skillCooldowns']:<String,dynamic>{};
  if(raw is! Map<String,dynamic>)throw const FormatException('Invalid skill cooldowns');
  final specs={for(final spec in _decodeActiveSkills(j))spec.id:spec};
  final result=<String,int>{};
  for(final entry in raw.entries){
   final spec=specs[entry.key],value=entry.value;
   if(spec==null||value is! int||value<1||value>spec.cooldown)throw const FormatException('Invalid skill cooldown');
   result[entry.key]=value;
  }
  return result;
 }
 static Map<BattleStatus,int> _decodeStatuses(Map<String,dynamic> j){
  if(!j.containsKey('statuses'))return {};
  final raw=j['statuses'];
  if(raw is! Map<String,dynamic>)throw const FormatException('Invalid battle statuses');
  final result=<BattleStatus,int>{};
  for(final entry in raw.entries){
   final matches=BattleStatus.values.where((kind)=>kind.name==entry.key);
   if(matches.isEmpty)throw const FormatException('Unknown battle status');
   final kind=matches.first,value=entry.value;
   if(value is! int||value<1||value>kind.duration)throw const FormatException('Invalid status duration');
   result[kind]=value;
  }
  return result;
 }
 static int? _decodeRng(Map<String,dynamic> j){
  if(!j.containsKey('rngVersion')&&!j.containsKey('rngState'))return null;
  if(j['rngVersion'] is! int||j['rngVersion']!=BattleRandom.version)throw const FormatException('Unsupported battle RNG version');
  return BattleRandom.validate(j['rngState']);
 }
 static Map<BattleBuff,int> _decodeBuffs(Map<String,dynamic> j){
  if(!j.containsKey('buffs'))return {};
  final raw=j['buffs'];
  if(raw is! Map<String,dynamic>)throw const FormatException('Invalid battle buffs');
  final result=<BattleBuff,int>{};
  for(final entry in raw.entries){
   final matches=BattleBuff.values.where((kind)=>kind.name==entry.key);
   if(matches.isEmpty)throw const FormatException('Unknown battle buff');
   final kind=matches.first,value=entry.value;
   if(value is! int||value<1||value>kind.duration)throw const FormatException('Invalid buff duration');
   result[kind]=value;
  }
  return result;
 }
}

class WorldState {
 WorldState({this.hp=100,this.physical=27,this.magic=38,this.gold=0,this.magicCrystals=0,this.shopSequence=0,this.itemUseSequence=0,this.summonTickets=0,this.supplyTickets=0,this.sequence=0,this.energyAt=0,this.hpAt=0,this.pendingPhysical=0,this.pendingMagic=0,this.pendingLevelUp=false,BigInt? lifespan,Set<String>? cleared,this.battle,this.lastResult='' }):lifespan=lifespan??BigInt.zero,cleared=cleared??{};
 int hp,physical,magic,gold,magicCrystals,shopSequence,itemUseSequence,summonTickets,supplyTickets,sequence,energyAt,hpAt,pendingPhysical,pendingMagic;
 bool pendingLevelUp;
 BigInt lifespan;
 final Set<String> cleared;
 WorldBattle? battle;
 String lastResult;
 Map<String,dynamic> toJson()=>{'version':1,'hp':hp,'physical':physical,'magic':magic,'gold':gold,'magicCrystals':magicCrystals,'shopSequence':shopSequence,'itemUseSequence':itemUseSequence,'summonTickets':summonTickets,'supplyTickets':supplyTickets,'sequence':sequence,'energyAt':energyAt,'hpAt':hpAt,'pendingPhysical':pendingPhysical,'pendingMagic':pendingMagic,'pendingLevelUp':pendingLevelUp,'lifespanDays':lifespan.toString(),'cleared':cleared.toList()..sort(),'battle':battle?.toJson(),'lastResult':lastResult};
 factory WorldState.fromJson(Map<String,dynamic> j){
  if(j['version']!=1)throw const FormatException('Unsupported world save version');
  final w=WorldState(hp:j['hp'] as int,physical:j['physical'] as int,magic:j['magic'] as int,gold:j['gold'] as int,magicCrystals:j.containsKey('magicCrystals')?j['magicCrystals'] as int:0,shopSequence:j.containsKey('shopSequence')?j['shopSequence'] as int:0,itemUseSequence:j.containsKey('itemUseSequence')?j['itemUseSequence'] as int:0,summonTickets:j['summonTickets'] as int,supplyTickets:j['supplyTickets'] as int,sequence:j['sequence'] as int,energyAt:j['energyAt'] as int,hpAt:j['hpAt'] as int,pendingPhysical:j['pendingPhysical'] as int? ?? 0,pendingMagic:j['pendingMagic'] as int? ?? 0,pendingLevelUp:j['pendingLevelUp'] as bool? ?? false,lifespan:BigInt.parse(j['lifespanDays'] as String),cleared:List<String>.from(j['cleared'] as List).toSet(),battle:j['battle']==null?null:WorldBattle.fromJson(j['battle'] as Map<String,dynamic>),lastResult:j['lastResult'] as String);
  if([w.hp,w.physical,w.magic,w.gold,w.magicCrystals,w.shopSequence,w.itemUseSequence,w.summonTickets,w.supplyTickets,w.sequence,w.energyAt,w.hpAt,w.pendingPhysical,w.pendingMagic].any((v)=>v<0)||w.lifespan<BigInt.zero)throw const FormatException('Negative world resource');
  if(w.battle!=null){final b=w.battle!;if((b.lifeRewardBonuses.isNotEmpty&&!w.cleared.contains(WorldCatalog.mainId(3)))||(b._rewindHistory!=null&&b._rewindHistory!.startHp!=w.hp)||b.id!=w.sequence||b.turn<1||b.enemyHp<1||b.enemyHp>WorldCatalog.byId(b.encounterId).hp||b.stats.hp<1||b.stats.physicalMax<1||b.stats.magicMax<1||b.stats.defense<0||b.stats.physical<1||b.stats.magic<1||!b.stats.crit.isFinite||b.stats.crit<0||b.stats.crit>1||w.hp<1||w.hp>b.stats.hp||w.physical>b.stats.physicalMax||w.magic>b.stats.magicMax||b.slowTurns<0||b.slowTurns>2||b.acceleratedClaws<0||b.acceleratedClaws>2||b.stopCooldown<0||b.stopCooldown>5||b.energyRemainder<0||b.energyRemainder>=WorldEngine.energyInterval||b.hpRemainder<0||b.hpRemainder>=WorldEngine.hpInterval)throw const FormatException('Invalid active battle');}
  return w;
 }
}

class WorldEngine {
 WorldEngine({Random? random,Random? seedRandom}):_testRandom=random,_seedRandom=seedRandom??Random.secure();
 // 既存の固定乱数ユニット試験専用。本番Controllerは指定しない。
 final Random? _testRandom;
 final Random _seedRandom;
 double _roll(WorldBattle battle)=>_testRandom?.nextDouble()??BattleRandom.next(battle);
 static const energyInterval=600000,hpInterval=1800000;
 bool isUnlocked(WorldState w,WorldEncounter e){
  if(e.main)return !w.cleared.contains(e.id)&&(e.stage==1||w.cleared.contains(WorldCatalog.mainId(e.stage-1)));
  return w.cleared.contains(WorldCatalog.mainId(e.stage));
 }
 bool refresh(WorldState w,WorldStats s,int now){
  if(w.battle!=null)return false;
  final before=[w.hp,w.physical,w.magic,w.energyAt,w.hpAt].join(',');
  if(w.energyAt==0){w.energyAt=now;w.physical=s.physicalMax;w.magic=s.magicMax;}
  if(now<w.energyAt)w.energyAt=now;
  if(w.hpAt==0){w.hpAt=now;w.hp=s.hp;}
  if(now<w.hpAt)w.hpAt=now;
  final ticks=(now-w.energyAt)~/energyInterval,heals=(now-w.hpAt)~/hpInterval;
  w.physical=min(s.physicalMax,w.physical+ticks);
  w.magic=min(s.magicMax,w.magic+ticks);
  w.hp=min(s.hp,w.hp+heals*max(1,(s.hp*0.05).floor()));
  w.energyAt+=ticks*energyInterval;
  w.hpAt+=heals*hpInterval;
  final pending=w.pendingPhysical>0||w.pendingMagic>0||w.pendingLevelUp;
  if(pending){
   w.physical=w.pendingLevelUp?s.physicalMax:min(s.physicalMax,w.physical+w.pendingPhysical);
   w.magic=w.pendingLevelUp?s.magicMax:min(s.magicMax,w.magic+w.pendingMagic);
   if(w.pendingLevelUp)w.hp=s.hp;
   w.pendingPhysical=0;w.pendingMagic=0;w.pendingLevelUp=false;
  }
  return pending||before!=[w.hp,w.physical,w.magic,w.energyAt,w.hpAt].join(',');
 }
 void rewardEffort(WorldState w,WorldStats s,int now,{required int physical,required int magic,required bool levelUp}){
  if(w.battle!=null){
   w.pendingPhysical=min(s.physicalMax,w.pendingPhysical+physical);
   w.pendingMagic=min(s.magicMax,w.pendingMagic+magic);
   w.pendingLevelUp=w.pendingLevelUp||levelUp;
   return;
  }
  refresh(w,s,now);
  w.physical=levelUp?s.physicalMax:min(s.physicalMax,w.physical+physical);
  w.magic=levelUp?s.magicMax:min(s.magicMax,w.magic+magic);
  if(levelUp)w.hp=s.hp;
 }
 void start(WorldState w,WorldStats s,String id,int now,{List<ActiveSkillSpec> activeSkills=const [],List<LifeRewardBonus> lifeRewardBonuses=const []}){
  LifeRewardBonus.validate(lifeRewardBonuses);
  if(lifeRewardBonuses.isNotEmpty&&!w.cleared.contains(WorldCatalog.mainId(3)))throw StateError('STAGE 03 clear required');
  if(activeSkills.length>6||activeSkills.map((s)=>s.id).toSet().length!=activeSkills.length)throw const FormatException('Invalid active skill snapshot');
  for(final spec in activeSkills){spec.validate();}
  if(w.battle!=null)throw StateError('A battle is already active');
  final e=WorldCatalog.byId(id);
  if(!isUnlocked(w,e))throw StateError('Encounter locked or completed');
  refresh(w,s,now);
  if(w.hp<=0)throw StateError('HP recovery required');
  if(w.sequence==0x7fffffffffffffff)throw StateError('Battle sequence overflow');
  final seed=_seedRandom.nextInt(BattleRandom.modulus-1)+1;
  w.sequence++;
  w.battle=WorldBattle(activeSkills:activeSkills,lifeRewardBonuses:lifeRewardBonuses,rewindHistory:activeSkills.any((s)=>s.effect==ActiveSkillEffect.rewindHp)?(startHp:w.hp,previousHp:null):null,rngState:seed,id:w.sequence,encounterId:id,stats:s,enemyHp:e.hp,energyRemainder:now-w.energyAt,hpRemainder:now-w.hpAt,log:['${e.enemy} が現れた。']);
  w.lastResult='';
 }
 /// 単一の消費計算を可否・実行・画面で共有する。寿命には適用しない。
 int energyCost(WorldState w,WorldCommand command){
  final base=switch(command){WorldCommand.claw=>4,WorldCommand.heavyClaw=>9,WorldCommand.magic=>6,_=>0};
  if(!(w.battle?.buffs.containsKey(BattleBuff.energyDiscount)??false))return base;
  return (base*(100-BattleBuff.energyDiscount.percent)+99)~/100;
 }
 String? unavailable(WorldState w,WorldCommand command){
  if(w.battle==null)return '戦闘中ではありません';
  return switch(command){
   WorldCommand.heavyClaw=>w.physical<energyCost(w,command)?'物理エネルギー不足':null,
   WorldCommand.magic=>w.magic<energyCost(w,command)?'魔法エネルギー不足':null,
   WorldCommand.slow=>!w.cleared.contains('p03_main')?'STAGE 03クリアで解放':w.lifespan<BigInt.from(3)?'寿命不足':w.battle!.slowTurns>0?'効果発動中':null,
   WorldCommand.accelerate=>!w.cleared.contains(WorldCatalog.mainId(6))?'STAGE 06クリアで解放':w.lifespan<BigInt.from(7)?'寿命不足':w.battle!.acceleratedClaws>0?'効果発動中':null,
   WorldCommand.stopTime=>!w.cleared.contains(WorldCatalog.mainId(12))?'STAGE 12クリアで解放':w.lifespan<BigInt.from(30)?'寿命不足':w.battle!.stopCooldown>0?'クールダウン中':null,
   WorldCommand.compositeClaw=>!w.cleared.contains(WorldCatalog.mainId(6))||!w.cleared.contains(WorldCatalog.mainId(12))?'STAGE 06・12クリアで解放':w.lifespan<BigInt.from(90)?'寿命不足':w.battle!.stopCooldown>0?'クールダウン中':null,
   _=>null,
  };
 }
 int damage(int attack,int defense,double multiplier,{double critical=1,double variance=1})=>max(1,(attack*multiplier*100/(100.0+defense)*critical*variance).floor());
 void act(WorldState w,WorldCommand command,int battleId,int expectedTurn,int now){
  final b=w.battle;
  if(b==null||b.id!=battleId||b.turn!=expectedTurn)throw StateError('Stale battle command');
  if(b.turn==0x7fffffffffffffff)throw StateError('Battle turn overflow');
  final unavailableReason=unavailable(w,command);
  if(unavailableReason!=null)throw StateError(unavailableReason);
  final e=WorldCatalog.byId(b.encounterId),s=b.stats;
  final attackBonus=b._buffs.containsKey(BattleBuff.attack)?1+BattleBuff.attack.percent/100:1.0;
  if(command==WorldCommand.retreat){_end(w,now,'撤退 — 消費済み資源は返還されません');return;}
  var dealt=0;
  var skipEnemy=false;
  final castingStop=command==WorldCommand.stopTime||command==WorldCommand.compositeClaw;
  final guarding=command==WorldCommand.guard;
  if(command==WorldCommand.slow){
   w.lifespan-=BigInt.from(3);
   if(e.timeResistant){b.log.add('時間遅延は無効化された。');}else{b.slowTurns=2;b.log.add('時間遅延 — 敵攻撃力30%低下');}
  }else if(command==WorldCommand.accelerate){
   w.lifespan-=BigInt.from(7);
   b.acceleratedClaws=2;
   b.log.add('自己加速 — 次の紅爪2回の威力2倍');
  }else if(command==WorldCommand.stopTime){
   w.lifespan-=BigInt.from(30);
   b.stopCooldown=5;
   skipEnemy=!e.timeResistant;
   b.log.add(skipEnemy?'時間停止 — 敵の行動停止':'時間停止は無効化された。');
  }else if(guarding){b.log.add('防御態勢');}
  else{
   final chance=b._buffs.containsKey(BattleBuff.critical)?min<double>(1.0,s.crit+BattleBuff.critical.percent/100):s.crit;
   final critical=_roll(b)<chance?1.5:1.0;
   final variance=0.95+_roll(b)*0.10;
   switch(command){
    case WorldCommand.claw:
     final cost=energyCost(w,command);
     final strong=w.physical>=cost;
     if(strong)w.physical-=cost;
     dealt=damage(s.physical,e.defense,(strong?1.0:0.25)*(b.acceleratedClaws>0?2.0:1.0)*attackBonus,critical:critical,variance:variance);
     if(b.acceleratedClaws>0)b.acceleratedClaws--;
    case WorldCommand.heavyClaw:
     w.physical-=energyCost(w,command);dealt=damage(s.physical,e.defense,1.8*attackBonus,critical:critical,variance:variance);
    case WorldCommand.compositeClaw:
     w.lifespan-=BigInt.from(90);
     b.stopCooldown=5;
     skipEnemy=!e.timeResistant;
     b.log.add(skipEnemy?'複合爪撃 — 時間停止・自己加速・爪撃':'複合爪撃 — 時間停止は無効化された。');
     dealt=damage(s.physical,e.defense,4.0*attackBonus,critical:critical,variance:variance);
    case WorldCommand.magic:
     w.magic-=energyCost(w,command);dealt=damage(s.magic,e.defense,1.2*attackBonus,critical:critical,variance:variance);
    default:break;
   }
   b.enemyHp=max(0,b.enemyHp-dealt);
   b.log.add('${critical>1?'会心！ ':''}$dealt ダメージ');
  }
  if(_victory(w,now))return;
  _finishTurn(w,now,skipEnemy:skipEnemy,guarding:guarding,castingStop:castingStop);
 }
 bool _victory(WorldState w,int now){
  final b=w.battle!,e=WorldCatalog.byId(w.battle!.encounterId);
  if(b.enemyHp==0){
   final life=LifeRewardBonus.reward(e.lifeDays,b.lifeRewardBonuses);
   final first=w.cleared.add(e.id);
   final gold=e.gold;
   w.gold+=gold;
   w.lifespan+=life;
   if(first){if(e.main){w.summonTickets+=3;}else{w.supplyTickets++;}}
   _end(w,now,'勝利 — $gold G / 寿命 +$life日${first?' / 初回報酬獲得':''}');
   return true;
  }
  return false;
 }
 /// 回復アイテムと共通の上限・切り捨て・最小1の計算。
 static int recoveryAmount(int current,int maximum,int percent){
  if(maximum<=0||current<0||current>maximum||percent<1||percent>100)throw StateError('Invalid recovery resource');
  if(current==maximum)return 0;
  return min<int>(maximum-current,max<int>(1,(maximum~/100)*percent+(maximum%100)*percent~/100));
 }
 int activeSkillCost(WorldState w,ActiveSkillSpec spec)=>w.battle?.buffs.containsKey(BattleBuff.energyDiscount)==true?(spec.physicalCost*(100-BattleBuff.energyDiscount.percent)+99)~/100:spec.physicalCost;
 String? activeSkillUnavailable(WorldState w,String id){
  final b=w.battle;
  if(b==null)return '戦闘中ではありません';
  final matches=b.activeSkills.where((s)=>s.id==id);
  if(matches.isEmpty)return '装着済みスキルではありません';
  if(b.turn==0x7fffffffffffffff)return 'ターン上限';
  if((b._skillCooldowns[id]??0)>0)return 'クールダウン中';
  final spec=matches.first;
  if(spec.effect==ActiveSkillEffect.foresight&&!w.cleared.contains(WorldCatalog.mainId(9)))return 'STAGE 09クリアが必要';
  if(spec.effect==ActiveSkillEffect.accelerationAttack&&!w.cleared.contains(WorldCatalog.mainId(6)))return 'STAGE 06クリアが必要';
  if((spec.effect==ActiveSkillEffect.repairHp||spec.effect==ActiveSkillEffect.timeCleanse)&&!w.cleared.contains(WorldCatalog.mainId(3)))return 'STAGE 03クリアが必要';
  if(spec.effect==ActiveSkillEffect.repairHp){
   if(w.hp<=0||w.hp>b.stats.hp||b.stats.hp<=0)return 'HP状態が不正です';
   if(w.hp==b.stats.hp)return 'HPは満タンです';
  }
  if(spec.effect==ActiveSkillEffect.timeCleanse&&!b._statuses.containsKey(BattleStatus.poison))return '解除可能な状態異常なし';
  if(spec.effect==ActiveSkillEffect.rewindHp){
   if(!w.cleared.contains(WorldCatalog.mainId(16)))return 'STAGE 16クリアが必要';
   final history=b._rewindHistory,previous=b.previousTurnHp;
   if(b.turn<=1||history==null||previous==null)return '前ターンのHP記録なし';
   if(history.startHp!=w.hp||w.hp<=0||previous<1||previous>b.stats.hp||w.hp>b.stats.hp)return 'HP状態が不正です';
   if(previous<=w.hp)return '復元できるHPなし';
  }
  if(w.lifespan<BigInt.from(spec.lifeCost))return '寿命不足';
  if(w.physical<activeSkillCost(w,spec))return '物理エネルギー不足';
  return null;
 }
 void actActiveSkill(WorldState w,String id,int battleId,int expectedTurn,int now){
  final b=w.battle;
  if(b==null||b.id!=battleId||b.turn!=expectedTurn)throw StateError('Stale battle command');
  final reason=activeSkillUnavailable(w,id);
  if(reason!=null)throw StateError(reason);
  final spec=b.activeSkills.firstWhere((s)=>s.id==id);
  final e=WorldCatalog.byId(b.encounterId),s=b.stats;
  w.physical-=activeSkillCost(w,spec);
  w.lifespan-=BigInt.from(spec.lifeCost);
  if(spec.effect==ActiveSkillEffect.foresight){
   b.log.add('${spec.name} — 寿命 ${spec.lifeCost}日消費');
   b._skillCooldowns[id]=spec.cooldown;
   _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false,castSkill:id,foresight:true);
   return;
  }
  if(spec.effect==ActiveSkillEffect.rewindHp){
   final amount=b.previousTurnHp!-w.hp;
   w.hp=b.previousTurnHp!;
   b.log.add('${spec.name} — 寿命 ${spec.lifeCost}日消費 / HP +$amount');
   b._skillCooldowns[id]=spec.cooldown;
   _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false,castSkill:id);
   return;
  }
  if(spec.effect==ActiveSkillEffect.repairHp||spec.effect==ActiveSkillEffect.timeCleanse){
   b.log.add('${spec.name} — 寿命 ${spec.lifeCost}日消費');
   if(spec.effect==ActiveSkillEffect.repairHp){
    final amount=recoveryAmount(w.hp,s.hp,spec.repairPercent);
    w.hp+=amount;
    b.log.add('${spec.name} — HP +$amount');
   }else{
    b._statuses.remove(BattleStatus.poison);
    b.log.add('${spec.name} — 毒を浄化');
   }
   b._skillCooldowns[id]=spec.cooldown;
   _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false,castSkill:id);
   return;
  }
  if(spec.effect==ActiveSkillEffect.accelerationAttack)b.log.add('${spec.name} — 寿命 ${spec.lifeCost}日消費');
  final bonus=b._buffs.containsKey(BattleBuff.attack)?1+BattleBuff.attack.percent/100:1.0;
  final chance=b._buffs.containsKey(BattleBuff.critical)?min<double>(1.0,s.crit+BattleBuff.critical.percent/100):s.crit;
  // 各hitで独立に会心・乱数・防御・丸めを適用。撃破後は乱数を消費しない。
  for(var hit=0;hit<spec.hits&&b.enemyHp>0;hit++){
   final critical=_roll(b)<chance?1.5:1.0;
   final variance=0.95+_roll(b)*0.10;
   final dealt=damage(s.physical,e.defense,spec.powerPercent/100*bonus,critical:critical,variance:variance);
   b.enemyHp=max(0,b.enemyHp-dealt);
   final label=spec.hits==1?spec.name:'${spec.name} ${hit+1}/${spec.hits}';
   b.log.add('$label — ${critical>1?'会心！ ':''}$dealt ダメージ');
  }
  if(spec.cooldown>0)b._skillCooldowns[id]=spec.cooldown;
  if(_victory(w,now))return;
  _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false,castSkill:id);
 }
 /// 回復行動後も通常行動と同じ敵反撃・効果経過を適用する。
 void finishRecoveryTurn(WorldState w,int battleId,int expectedTurn,int now,String itemName,int amount){
  final b=w.battle;
  if(b==null||b.id!=battleId||b.turn!=expectedTurn)throw StateError('Stale battle command');
  if(b.turn==0x7fffffffffffffff)throw StateError('Battle turn overflow');
  if(amount<=0)throw StateError('Invalid recovery amount');
  b.log.add('$itemName — $amount 回復');
  _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false);
 }
 int validatePurification(WorldState w,int battleId,int expectedTurn){
  final b=w.battle;
  if(b==null||b.id!=battleId||b.turn!=expectedTurn)throw StateError('Stale battle command');
  if(b.turn==0x7fffffffffffffff)throw StateError('Battle turn overflow');
  if(b._statuses.isEmpty)throw StateError('No removable status');
  return b._statuses.length;
 }
 void finishPurificationTurn(WorldState w,int battleId,int expectedTurn,int now,String name){
  validatePurification(w,battleId,expectedTurn);
  final b=w.battle!;
  final labels=b._statuses.keys.map((kind)=>kind.label).join('・');
  b._statuses.clear();
  b.log.add('$name — $labels を浄化');
  _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false);
 }
 void validateBuff(WorldState w,BattleBuff kind,int battleId,int expectedTurn){
  final b=w.battle;
  if(b==null||b.id!=battleId||b.turn!=expectedTurn)throw StateError('Stale battle command');
  if(b._buffs.containsKey(kind))throw StateError('Buff already active');
  if(kind==BattleBuff.regenerationSuppression&&WorldCatalog.byId(b.encounterId).regenerationPercent==0)throw StateError('Enemy has no regeneration');
  if(b.turn==0x7fffffffffffffff)throw StateError('Battle turn overflow');
 }
 void finishBuffTurn(WorldState w,BattleBuff kind,int battleId,int expectedTurn,int now,String name){
  validateBuff(w,kind,battleId,expectedTurn);
  final b=w.battle!;
  b._buffs[kind]=kind.duration;
  b.log.add('$name — 効果発動');
  _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false,newBuff:kind);
 }
 void _finishTurn(WorldState w,int now,{required bool skipEnemy,required bool guarding,required bool castingStop,BattleBuff? newBuff,String? castSkill,bool foresight=false}){
  final b=w.battle!;
  final e=WorldCatalog.byId(b.encounterId),s=b.stats;
  if(!skipEnemy){
   final int extra=(s.defense~/100)*BattleBuff.defense.percent+(s.defense%100)*BattleBuff.defense.percent~/100;
   final defense=b._buffs.containsKey(BattleBuff.defense)?s.defense+min<int>(extra,max<int>(0,0x7fffffffffffff9b-s.defense)):s.defense;
   final attack=damage(e.attack,defense,(b.slowTurns>0?0.7:1.0)*(guarding?0.5:1.0));
   if(foresight){
    b.log.add('未来視 — 敵の反撃を無効化した。');
   }else if(b._buffs.containsKey(BattleBuff.evasion)&&_roll(b)<BattleBuff.evasion.percent/100){
    b.log.add('敵の反撃を回避した。');
   }else{
    if(attack>=w.hp&&b._buffs.remove(BattleBuff.lethalProtection)!=null){
     final lost=w.hp-1;
     w.hp=1;
     b.log.add('敵の反撃 — HP -$lost');
     b.log.add('致死耐性発動 — HP1で生存');
    }else{
     w.hp=max(0,w.hp-attack);
     b.log.add('敵の反撃 — HP -$attack');
    }
   }
   if(b.slowTurns>0)b.slowTurns--;
  }
  if(!castingStop&&b.stopCooldown>0)b.stopCooldown--;
  if(w.hp==0){_end(w,now,'敗北 — 回復後に再挑戦できます');return;}
  if(b._statuses.containsKey(BattleStatus.poison)){
   final damage=min<int>(max<int>(0,w.hp-1),max<int>(1,(s.hp~/100)*5+(s.hp%100)*5~/100));
   w.hp-=damage;
   if(damage>0)b.log.add('毒 — HP -$damage');
   final remaining=b._statuses[BattleStatus.poison]!-1;
   if(remaining==0){b._statuses.remove(BattleStatus.poison);}else{b._statuses[BattleStatus.poison]=remaining;}
  }
  if(b._buffs.containsKey(BattleBuff.regeneration)&&newBuff!=BattleBuff.regeneration){
   final amount=min(s.hp-w.hp,max(1,(s.hp~/100)*BattleBuff.regeneration.percent+(s.hp%100)*BattleBuff.regeneration.percent~/100));
   w.hp+=amount;
   if(amount>0)b.log.add('継続回復 — HP +$amount');
  }
  if(!skipEnemy&&e.regenerationPercent>0&&b.enemyHp>0&&b.enemyHp<e.hp){
   final base=max<int>(1,(e.hp~/100)*e.regenerationPercent+(e.hp%100)*e.regenerationPercent~/100);
   final effective=b._buffs.containsKey(BattleBuff.regenerationSuppression)
    ?(base~/100)*(100-BattleBuff.regenerationSuppression.percent)+(base%100)*(100-BattleBuff.regenerationSuppression.percent)~/100
    :base;
   final healed=min<int>(e.hp-b.enemyHp,effective);
   b.enemyHp+=healed;
   if(healed>0)b.log.add('敵の再生 — HP +$healed');
   if(b._buffs.containsKey(BattleBuff.regenerationSuppression))b.log.add('敵再生抑制 — 回復量${BattleBuff.regenerationSuppression.percent}%軽減');
  }
  for(final kind in b._buffs.keys.toList()){
   if(kind==newBuff||kind.isCharge)continue;
   final remaining=b._buffs[kind]!-1;
   if(remaining==0){b._buffs.remove(kind);}else{b._buffs[kind]=remaining;}
  }
  for(final id in b._skillCooldowns.keys.toList()){
   if(id==castSkill)continue;
   final remaining=b._skillCooldowns[id]!-1;
   if(remaining==0){b._skillCooldowns.remove(id);}else{b._skillCooldowns[id]=remaining;}
  }
  // 全ての成立行動が通る経路で、直前の行動開始時HPだけを保持する。
  if(b._rewindHistory case final history?){
   b._rewindHistory=(startHp:w.hp,previousHp:history.startHp);
  }
  b.turn++;
  if(b.log.length>12)b.log.removeRange(0,b.log.length-12);
 }
 void _end(WorldState w,int now,String result){final b=w.battle!;w.battle=null;w.energyAt=max(1,now-b.energyRemainder);w.hpAt=max(1,now-b.hpRemainder);w.lastResult=result;}
}
