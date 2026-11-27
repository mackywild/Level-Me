import 'dart:math';
import 'world_catalog.dart';
import 'abyss_ex_battle_attack.dart';

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
 static const maxStat=0x7fffffffffffffff;
 /// 能力値は飽和させず、表現不能な構成を確定前に拒否する。
 static int checkedAdd(int value,int bonus){
  if(value<0||bonus<0||value>maxStat-bonus)throw StateError('Stat addition overflow or negative value');
  return value+bonus;
 }
 static int checkedStat(BigInt value){
  if(value<BigInt.zero||value>BigInt.from(maxStat))throw StateError('Stat overflow or negative value');
  return value.toInt();
 }
 static int _linear(int base,int rank,int coefficient,int level,int levelCoefficient){
  return checkedStat(BigInt.from(base)+BigInt.from(rank-1)*BigInt.from(coefficient)+BigInt.from(level-1)*BigInt.from(levelCoefficient));
 }
 static int _sqrtFloor(int value){
  var root=sqrt(value).floor();
  // doubleの丸めが完全平方数の境界をまたいでも整数除算で補正する。
  while(root>value~/root){root--;}
  while(root+1<=value~/(root+1)){root++;}
  return root;
 }
 factory WorldStats.fromRanks({required int level,required int fitness,required int intelligence,required int discipline,required int creativity}){
  if([level,fitness,intelligence,discipline,creativity].any((v)=>v<1))throw StateError('Invalid player rank');
  return WorldStats(
   hp:_linear(100,fitness,12,level,8),
   physical:_linear(40,fitness,8,level,3),
   magic:_linear(45,intelligence,8,level,3),
   defense:_linear(10,discipline,5,level,2),
   physicalMax:25+_sqrtFloor(fitness)*2,
   magicMax:35+_sqrtFloor(intelligence)*3,
   crit:min(0.5,0.05+0.005*(creativity-1)),
  );
 }
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
enum ActiveSkillEffect { physical, foresight, accelerationAttack, repairHp, timeCleanse, rewindHp, crimsonAwakening, stopAttack, ultimateAttack }

/// 既存の能動効果を固定した規則v1。将来の性能変更は別版として追加する。
class ActiveSkillRulesV1 {
 const ActiveSkillRulesV1({this.requiredStages=const [],this.repairPercent=0,this.awakeningPercent=0,this.awakeningDuration=0,this.sharedStopCooldown=0});
 static const version=1,crimsonPercent=30,crimsonDuration=3,stopCooldown=5;
 final List<int> requiredStages;
 final int repairPercent,awakeningPercent,awakeningDuration,sharedStopCooldown;
 static ActiveSkillRulesV1 forSpec(ActiveSkillSpec spec)=>switch(spec.effect){
  ActiveSkillEffect.physical=>const ActiveSkillRulesV1(),
  ActiveSkillEffect.foresight=>const ActiveSkillRulesV1(requiredStages:[9]),
  ActiveSkillEffect.accelerationAttack=>const ActiveSkillRulesV1(requiredStages:[6]),
  ActiveSkillEffect.repairHp=>ActiveSkillRulesV1(requiredStages:const [3],repairPercent:switch(spec.id){
   'skill:wound_repair'=>10,'skill:body_repair'=>25,'skill:life_rewind'=>50,'skill:full_repair'=>100,_=>0,
  }),
  ActiveSkillEffect.timeCleanse=>const ActiveSkillRulesV1(requiredStages:[3]),
  ActiveSkillEffect.rewindHp=>const ActiveSkillRulesV1(requiredStages:[16]),
  ActiveSkillEffect.crimsonAwakening=>const ActiveSkillRulesV1(requiredStages:[12],awakeningPercent:crimsonPercent,awakeningDuration:crimsonDuration),
  ActiveSkillEffect.stopAttack=>ActiveSkillRulesV1(requiredStages:spec.id=='skill:chrono_combo'?const [12,6]:const [12],sharedStopCooldown:stopCooldown),
  ActiveSkillEffect.ultimateAttack=>ActiveSkillRulesV1(requiredStages:switch(spec.id){
   'skill:spacetime_break'=>const [18],'skill:world_collapse'=>const [21],_=>const <int>[],
  }),
 };
 Map<String,dynamic> toJson(String id)=>{'id':id,'version':version,'requiredStages':requiredStages,'repairPercent':repairPercent,'awakeningPercent':awakeningPercent,'awakeningDuration':awakeningDuration,'sharedStopCooldown':sharedStopCooldown};
 static void validateSnapshot(Object? raw,List<ActiveSkillSpec> specs){
  if(raw is! List||raw.length!=specs.length)throw const FormatException('Invalid active rule snapshot count');
  for(var i=0;i<specs.length;i++){
   final row=raw[i],expected=forSpec(specs[i]).toJson(specs[i].id);
   if(row is! Map<String,dynamic>||row.length!=expected.length||row['id']!=expected['id'])throw const FormatException('Invalid active rule snapshot');
   for(final key in const ['version','repairPercent','awakeningPercent','awakeningDuration','sharedStopCooldown']){
    if(row[key] is! int||row[key]!=expected[key])throw FormatException('Invalid active rule field: $key');
   }
   final stages=row['requiredStages'],required=forSpec(specs[i]).requiredStages;
   if(stages is! List||stages.length!=required.length)throw const FormatException('Invalid active rule stages');
   for(var j=0;j<required.length;j++){
    if(stages[j] is! int||stages[j]!=required[j])throw const FormatException('Invalid active rule stage');
   }
  }
 }
}

class ActiveSkillSpec {
 const ActiveSkillSpec({required this.id,required this.name,required this.powerPercent,required this.physicalCost,required this.cooldown,this.hits=1,this.effect=ActiveSkillEffect.physical,this.lifeCost=0});
 final String id,name;
 final int powerPercent,physicalCost,cooldown,hits,lifeCost;
 final ActiveSkillEffect effect;
 /// 実装済みの特殊IDを汎用物理等へ差し替えない。
 static const reservedEffects=<String,ActiveSkillEffect>{
  'skill:foresight':ActiveSkillEffect.foresight,
  'skill:speed_claw':ActiveSkillEffect.accelerationAttack,'skill:gale_claws':ActiveSkillEffect.accelerationAttack,
  'skill:wound_repair':ActiveSkillEffect.repairHp,'skill:body_repair':ActiveSkillEffect.repairHp,'skill:life_rewind':ActiveSkillEffect.repairHp,'skill:full_repair':ActiveSkillEffect.repairHp,
  'skill:time_cleanse':ActiveSkillEffect.timeCleanse,'skill:rewind':ActiveSkillEffect.rewindHp,
  'skill:crimson_awakening':ActiveSkillEffect.crimsonAwakening,
  'skill:still_claw':ActiveSkillEffect.stopAttack,'skill:chrono_combo':ActiveSkillEffect.stopAttack,
  'skill:spacetime_break':ActiveSkillEffect.ultimateAttack,'skill:world_collapse':ActiveSkillEffect.ultimateAttack,
 };
 void validate(){
  if((reservedEffects[id]!=null&&reservedEffects[id]!=effect)||!id.startsWith('skill:')||id.length<=6||name.trim().isEmpty||cooldown<0||cooldown>20||!_validEffect)throw const FormatException('Invalid active skill spec');
 }
 ActiveSkillRulesV1 get rules=>ActiveSkillRulesV1.forSpec(this);
 int? missingStage(Set<String> cleared){
  for(final stage in rules.requiredStages){
   if(!cleared.contains(WorldCatalog.mainId(stage)))return stage;
  }
  return null;
 }
 int get repairPercent=>rules.repairPercent;
 bool get usesStopCooldown=>rules.sharedStopCooldown>0;
 int get ultimateUnlockStage=>effect==ActiveSkillEffect.ultimateAttack&&rules.requiredStages.isNotEmpty?rules.requiredStages.single:0;
 /// v1の定義許容範囲。旧版の意味を変更しない。
 bool get _validEffect=>switch(effect){
  ActiveSkillEffect.physical=>powerPercent>=1&&powerPercent<=500&&hits>=1&&hits<=10&&powerPercent*hits<=500&&physicalCost>=1&&physicalCost<=100&&lifeCost==0,
  ActiveSkillEffect.foresight=>id=='skill:foresight'&&powerPercent==0&&physicalCost==0&&hits==1&&lifeCost==14&&cooldown>=1,
  ActiveSkillEffect.accelerationAttack=>physicalCost==0&&cooldown>=1&&((id=='skill:speed_claw'&&powerPercent==250&&hits==1&&lifeCost==10)||(id=='skill:gale_claws'&&powerPercent==50&&hits==8&&lifeCost==45)),
  ActiveSkillEffect.repairHp=>powerPercent==0&&physicalCost==0&&hits==1&&cooldown>=1&&repairPercent>0&&lifeCost==(switch(repairPercent){10=>7,25=>21,50=>180,100=>365,_=>0}),
  ActiveSkillEffect.timeCleanse=>id=='skill:time_cleanse'&&powerPercent==0&&physicalCost==0&&hits==1&&lifeCost==30&&cooldown>=1,
  ActiveSkillEffect.rewindHp=>id=='skill:rewind'&&powerPercent==0&&physicalCost==0&&hits==1&&lifeCost==90&&cooldown==8,
  ActiveSkillEffect.crimsonAwakening=>id=='skill:crimson_awakening'&&powerPercent==0&&physicalCost==0&&hits==1&&lifeCost==30&&cooldown==5,
  ActiveSkillEffect.stopAttack=>physicalCost==0&&hits==1&&cooldown==0&&((id=='skill:still_claw'&&powerPercent==250&&lifeCost==45)||(id=='skill:chrono_combo'&&powerPercent==400&&lifeCost==90)),
  ActiveSkillEffect.ultimateAttack=>physicalCost==0&&hits==1&&((id=='skill:spacetime_break'&&powerPercent==500&&lifeCost==180&&cooldown==8)||(id=='skill:world_collapse'&&powerPercent==800&&lifeCost==730&&cooldown==10)),
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
 static int totalPercent(List<LifeRewardBonus> bonuses){
  validate(bonuses);
  return bonuses.fold<int>(100,(sum,b)=>sum+b.percent);
 }
 static BigInt reward(int base,List<LifeRewardBonus> bonuses)=>rewardAtPercent(base,totalPercent(bonuses));
 static BigInt rewardAtPercent(int base,int percent){
  if(base<0||percent<100||percent>130)throw const FormatException('Invalid life reward');
  return BigInt.from(base)*BigInt.from(percent)~/BigInt.from(100);
 }
}

/// 戦闘実行版4の装備効果。未承認の効果はこの版に含めない。
class BattleEquipmentEffects {
 BattleEquipmentEffects({this.physical=0,this.magic=0,this.defense=0,this.critical=0,this.evasion=0,this.reduction=0,this.discount=0,this.penetration=0,this.extraAttack=0,this.hp=0,this.cooldown=0,this.resistance=0,this.naturalRecovery=0,this.reward=0}){
  if([physical,magic,defense].any((v)=>v<0||v>30000)||critical<0||critical>10000||evasion<0||evasion>5000||reduction<0||reduction>7000||discount<0||discount>5000||penetration<0||penetration>5000||extraAttack<0||extraAttack>5000||hp<0||hp>30000||cooldown<0||cooldown>5000||resistance<0||resistance>8000||naturalRecovery<0||naturalRecovery>30000||reward<0||reward>10000)throw const FormatException('Invalid battle equipment effects');
 }
 final int physical,magic,defense,critical,evasion,reduction,discount,penetration,extraAttack,hp,cooldown,resistance,naturalRecovery,reward;
 bool get requiresV8=>naturalRecovery>0||reward>0;
 bool get requiresV7=>resistance>0;
 /// 固有権能はphysical以外の既存効果として識別する。正のCDのみ短縮。
 static int effectiveCooldown(ActiveSkillSpec spec,int reduction)=>spec.effect!=ActiveSkillEffect.physical||spec.cooldown==0?spec.cooldown:max(1,(spec.cooldown*(10000-reduction)+9999)~/10000);
 bool get requiresV6=>hp>0||cooldown>0;
 bool get requiresV5=>penetration>0||extraAttack>0;
 Map<String,int> toJson({bool extended=false,bool hpCooldown=false,bool statusResistance=false,bool recoveryReward=false})=>{'physical':physical,'magic':magic,'defense':defense,'critical':critical,'evasion':evasion,'reduction':reduction,'discount':discount,if(extended||hpCooldown||statusResistance||recoveryReward)...{'penetration':penetration,'extraAttack':extraAttack},if(hpCooldown||statusResistance||recoveryReward)...{'hp':hp,'cooldown':cooldown},if(statusResistance||recoveryReward)'resistance':resistance,if(recoveryReward)...{'naturalRecovery':naturalRecovery,'reward':reward}};
 factory BattleEquipmentEffects.fromJson(Object? raw,{bool extended=false,bool hpCooldown=false,bool statusResistance=false,bool recoveryReward=false}){
  if(raw is! Map<String,dynamic>||raw.length!=(recoveryReward?14:statusResistance?12:hpCooldown?11:extended?9:7)||['physical','magic','defense','critical','evasion','reduction','discount',if(extended||hpCooldown||statusResistance||recoveryReward)...['penetration','extraAttack'],if(hpCooldown||statusResistance||recoveryReward)...['hp','cooldown'],if(statusResistance||recoveryReward)'resistance',if(recoveryReward)...['naturalRecovery','reward']].any((key)=>raw[key] is! int))throw const FormatException('Invalid battle equipment snapshot');
  return BattleEquipmentEffects(physical:raw['physical'] as int,magic:raw['magic'] as int,defense:raw['defense'] as int,critical:raw['critical'] as int,evasion:raw['evasion'] as int,reduction:raw['reduction'] as int,discount:raw['discount'] as int,penetration:extended||hpCooldown||statusResistance||recoveryReward?raw['penetration'] as int:0,extraAttack:extended||hpCooldown||statusResistance||recoveryReward?raw['extraAttack'] as int:0,hp:hpCooldown||statusResistance||recoveryReward?raw['hp'] as int:0,cooldown:hpCooldown||statusResistance||recoveryReward?raw['cooldown'] as int:0,resistance:statusResistance||recoveryReward?raw['resistance'] as int:0,naturalRecovery:recoveryReward?raw['naturalRecovery'] as int:0,reward:recoveryReward?raw['reward'] as int:0);
 }
 WorldStats apply(WorldStats base){
  int scale(int value,int bonus)=>WorldStats.checkedStat(BigInt.from(value)*BigInt.from(10000+bonus)~/BigInt.from(10000));
  return WorldStats(hp:scale(base.hp,hp),physical:scale(base.physical,physical),magic:scale(base.magic,magic),defense:scale(base.defense,defense),physicalMax:base.physicalMax,magicMax:base.magicMax,crit:base.crit);
 }
 bool sameAs(BattleEquipmentEffects other)=>toJson(recoveryReward:true).entries.every((e)=>other.toJson(recoveryReward:true)[e.key]==e.value);
}

class WorldBattle {
 WorldBattle({required this.id,required this.encounterId,required this.stats,required this.enemyHp,this.turn=1,this.slowTurns=0,this.acceleratedClaws=0,this.stopCooldown=0,this.energyRemainder=0,this.hpRemainder=0,List<String>? log,Map<BattleBuff,int>? buffs,Map<BattleStatus,int>? statuses,List<ActiveSkillSpec> activeSkills=const [],Map<String,int>? skillCooldowns,int? rngState,({int startHp,int? previousHp})? rewindHistory,List<LifeRewardBonus> lifeRewardBonuses=const [],int awakeningTurns=0,this.executionVersion,int? lifeRewardPercent,WorldEncounter? encounterSnapshot,this.equipmentEffects,List<ExBattleAttack> exAttacks=const []}):_exAttacks=ExBattleAttack.validate(exAttacks,turn),_encounterSnapshot=encounterSnapshot,_lifeRewardPercent=lifeRewardPercent,_awakeningTurns=awakeningTurns,lifeRewardBonuses=List.unmodifiable(lifeRewardBonuses),_rewindHistory=rewindHistory,log=log??[],_buffs=Map.of(buffs??{}),_statuses=Map.of(statuses??{}),activeSkills=List.unmodifiable(activeSkills),_skillCooldowns=Map.of(skillCooldowns??{}),_rngState=BattleRandom.validate(rngState??BattleRandom.legacySeed(id,turn));
 final int id;
 final String encounterId;
 final WorldStats stats;
 final BattleEquipmentEffects? equipmentEffects;
 final List<ExBattleAttack> _exAttacks;
 List<ExBattleAttack> get exAttacks=>List.unmodifiable(_exAttacks);
 final int energyRemainder,hpRemainder;
 int enemyHp,turn,slowTurns,acceleratedClaws,stopCooldown;
 final List<String> log;
 ({int startHp,int? previousHp})? _rewindHistory;
 int? get previousTurnHp=>_rewindHistory?.previousHp;
 int _awakeningTurns;
 int get awakeningTurns=>_awakeningTurns;
 static const awakeningPercent=ActiveSkillRulesV1.crimsonPercent,awakeningDuration=ActiveSkillRulesV1.crimsonDuration;
 ActiveSkillRulesV1 get awakeningRules=>activeSkills.firstWhere((s)=>s.effect==ActiveSkillEffect.crimsonAwakening).rules;
 int _rngState;
 int get rngState=>_rngState;
 final Map<BattleBuff,int> _buffs;
 final Map<BattleStatus,int> _statuses;
 final List<ActiveSkillSpec> activeSkills;
 final List<LifeRewardBonus> lifeRewardBonuses;
 /// v1は敵master参照、v2は敵定義固定、v3は能動規則v1も明示。nullは版番号導入前。
 static const currentExecutionVersion=3;
 final WorldEncounter? _encounterSnapshot;
 WorldEncounter get encounter=>_encounterSnapshot??WorldCatalog.byId(encounterId);
 final int? executionVersion;
 final int? _lifeRewardPercent;
 int get lifeRewardPercent=>_lifeRewardPercent??LifeRewardBonus.totalPercent(lifeRewardBonuses);
 final Map<String,int> _skillCooldowns;
 Map<String,int> get skillCooldowns=>Map.unmodifiable(_skillCooldowns);
 Map<BattleStatus,int> get statuses=>Map.unmodifiable(_statuses);
 Map<BattleBuff,int> get buffs=>Map.unmodifiable(_buffs);
 Map<String,dynamic> toJson()=>{'id':id,'encounterId':encounterId,'stats':stats.toJson(),'enemyHp':enemyHp,'turn':turn,'slowTurns':slowTurns,'acceleratedClaws':acceleratedClaws,'stopCooldown':stopCooldown,'energyRemainder':energyRemainder,'hpRemainder':hpRemainder,'log':log,'rngVersion':BattleRandom.version,'rngState':_rngState,'activeSkills':activeSkills.map((s)=>s.toJson()).toList(),'skillCooldowns':Map<String,int>.of(_skillCooldowns),if(executionVersion!=null)'executionVersion':executionVersion,if(executionVersion!=null)'lifeRewardPercent':lifeRewardPercent,if((executionVersion??0)>=2)'encounterSnapshot':_encounterSnapshot!.toBattleJson(),if((executionVersion??0)>=3)'activeRuleSnapshots':activeSkills.map((s)=>s.rules.toJson(s.id)).toList(),if((executionVersion??0)>=4)'equipmentEffects':equipmentEffects!.toJson(extended:executionVersion==5,hpCooldown:executionVersion==6,statusResistance:executionVersion==7,recoveryReward:(executionVersion??0)>=8),if((executionVersion??0)>=9)'exAttacks':_exAttacks.map((a)=>a.toJson()).toList(),if(activeSkills.any((s)=>s.effect==ActiveSkillEffect.crimsonAwakening))'awakeningTurns':_awakeningTurns,if(executionVersion!=null||lifeRewardBonuses.isNotEmpty)'lifeRewardBonuses':lifeRewardBonuses.map((b)=>b.name).toList(),if(_rewindHistory case final history?)'rewindHistory':{'turn':turn,'startHp':history.startHp,'previousHp':history.previousHp},'statuses':{for(final entry in _statuses.entries)entry.key.name:entry.value},'buffs':{for(final entry in _buffs.entries)entry.key.name:entry.value}};
 factory WorldBattle.fromJson(Map<String,dynamic> j){
  final version=_decodeExecutionVersion(j);
  final specs=_decodeActiveSkills(j);
  if((version??0)>=3)ActiveSkillRulesV1.validateSnapshot(j['activeRuleSnapshots'],specs);
  final attacks=(version??0)>=9?(j['exAttacks'] as List).map(ExBattleAttack.fromJson).toList():<ExBattleAttack>[];
  if((version==10)!=attacks.any((a)=>a.attribute==ExAttackAttribute.hpRecovery))throw const FormatException('EX recovery snapshot version mismatch');
  return WorldBattle(id:j['id'] as int,encounterId:j['encounterId'] as String,stats:WorldStats.fromJson(j['stats'] as Map<String,dynamic>),enemyHp:j['enemyHp'] as int,turn:j['turn'] as int,slowTurns:j['slowTurns'] as int,acceleratedClaws:j['acceleratedClaws'] as int? ?? 0,stopCooldown:j['stopCooldown'] as int? ?? 0,energyRemainder:j['energyRemainder'] as int? ?? 0,hpRemainder:j['hpRemainder'] as int? ?? 0,log:List<String>.from(j['log'] as List),buffs:_decodeBuffs(j),statuses:_decodeStatuses(j),activeSkills:specs,skillCooldowns:_decodeSkillCooldowns(j),rngState:_decodeRng(j),rewindHistory:_decodeRewindHistory(j),lifeRewardBonuses:_decodeLifeRewardBonuses(j),awakeningTurns:_decodeAwakeningTurns(j),executionVersion:version,exAttacks:attacks,equipmentEffects:(version??0)>=4?BattleEquipmentEffects.fromJson(j['equipmentEffects'],extended:version==5,hpCooldown:version==6,statusResistance:version==7,recoveryReward:(version??0)>=8):null,lifeRewardPercent:version!=null?j['lifeRewardPercent'] as int:null,encounterSnapshot:(version??0)>=2?WorldEncounter.fromBattleJson(j['encounterSnapshot'] as Map<String,dynamic>,j['encounterId'] as String):null);
 }
 static int? _decodeExecutionVersion(Map<String,dynamic> j){
  if(!j.containsKey('executionVersion')){
   if(j.containsKey('lifeRewardPercent')||j.containsKey('encounterSnapshot')||j.containsKey('activeRuleSnapshots')||j.containsKey('equipmentEffects')||j.containsKey('exAttacks'))throw const FormatException('Missing execution version');
   return null;
  }
  final version=j['executionVersion'];
  if(version is! int||(version!=1&&version!=2&&version!=currentExecutionVersion&&version!=4&&version!=5&&version!=6&&version!=7&&version!=8&&version!=9&&version!=10))throw const FormatException('Unsupported battle execution version');
  if(version>=2?j['encounterSnapshot'] is! Map<String,dynamic>:j.containsKey('encounterSnapshot'))throw const FormatException('Invalid encounter snapshot version');
  if(version>=3?j['activeRuleSnapshots'] is! List:j.containsKey('activeRuleSnapshots'))throw const FormatException('Invalid active rule snapshot version');
  if(version>=4?!j.containsKey('equipmentEffects'):j.containsKey('equipmentEffects'))throw const FormatException('Invalid equipment snapshot version');
  if(version>=9?(j['exAttacks'] is! List||(j['exAttacks'] as List).isEmpty):j.containsKey('exAttacks'))throw const FormatException('Invalid EX attack snapshot version');
  // 版付き戦闘は全非条件付き出力項目が必須。
  for(final key in const ['id','enemyHp','turn','slowTurns','acceleratedClaws','stopCooldown','energyRemainder','hpRemainder','rngVersion','rngState','lifeRewardPercent']){
   if(j[key] is! int)throw FormatException('Invalid versioned battle integer: $key');
  }
  if(j['encounterId'] is! String)throw const FormatException('Invalid versioned encounter ID');
  final stats=j['stats'],log=j['log'];
  if(stats is! Map<String,dynamic>||log is! List||log.any((entry)=>entry is! String))throw const FormatException('Invalid versioned battle stats or log');
  for(final key in const ['hp','physical','magic','defense','physicalMax','magicMax']){
   if(stats[key] is! int)throw FormatException('Invalid versioned battle stat: $key');
  }
  final crit=stats['crit'];
  if(crit is! num||!crit.isFinite||crit<0||crit>1)throw const FormatException('Invalid versioned battle critical rate');
  for(final key in const ['skillCooldowns','buffs','statuses']){
   if(j[key] is! Map<String,dynamic>)throw FormatException('Invalid versioned battle map: $key');
  }
  for(final key in const ['activeSkills','lifeRewardBonuses']){
   if(j[key] is! List)throw FormatException('Invalid versioned battle list: $key');
  }
  final raw=j['lifeRewardPercent'];
  if(raw is! int||raw!=LifeRewardBonus.totalPercent(_decodeLifeRewardBonuses(j)))throw const FormatException('Invalid life reward percent snapshot');
  return version;
 }
 static int _decodeAwakeningTurns(Map<String,dynamic> j){
  final awakening=_decodeActiveSkills(j).where((s)=>s.effect==ActiveSkillEffect.crimsonAwakening);
  final equipped=awakening.isNotEmpty;
  if(!j.containsKey('awakeningTurns')){
   if(equipped)throw const FormatException('Missing awakening state');
   return 0;
  }
  final raw=j['awakeningTurns'];
  if(!equipped||raw is! int||raw<0||raw>awakening.single.rules.awakeningDuration)throw const FormatException('Invalid awakening state');
  final cd=_decodeSkillCooldowns(j)['skill:crimson_awakening']??0;
  if(raw!=max(0,cd-(awakening.single.cooldown-awakening.single.rules.awakeningDuration))||(cd>0&&(j['turn'] is! int||(j['turn'] as int)<2+awakening.single.cooldown-cd)))throw const FormatException('Invalid awakening cooldown');
  return raw;
 }
 static List<LifeRewardBonus> _decodeLifeRewardBonuses(Map<String,dynamic> j){
  if(!j.containsKey('lifeRewardBonuses'))return const [];
  final raw=j['lifeRewardBonuses'];
  if(raw is! List||(raw.isEmpty&&!j.containsKey('executionVersion'))||raw.length>2)throw const FormatException('Invalid life reward bonuses');
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
   if(j.containsKey('executionVersion')&&const ['id','name','powerPercent','physicalCost','cooldown','hits','effect','lifeCost'].any((key)=>!row.containsKey(key)))throw const FormatException('Incomplete versioned skill definition');
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
  final version=j['executionVersion'];
  final reduction=version==6||version==7||version==8||version==9||version==10?BattleEquipmentEffects.fromJson(j['equipmentEffects'],hpCooldown:version==6,statusResistance:version==7,recoveryReward:(version??0)>=8).cooldown:0;
  for(final entry in raw.entries){
   final spec=specs[entry.key],value=entry.value;
   if(spec==null||value is! int||value<1||value>BattleEquipmentEffects.effectiveCooldown(spec,reduction))throw const FormatException('Invalid skill cooldown');
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
  if(w.battle!=null){final b=w.battle!;if(b.activeSkills.any((spec)=>spec.missingStage(w.cleared)!=null))throw const FormatException('Locked active skill snapshot');if((b.awakeningTurns>0&&!w.cleared.contains(WorldCatalog.mainId(12)))||(b.lifeRewardBonuses.isNotEmpty&&!w.cleared.contains(WorldCatalog.mainId(3)))||(b._rewindHistory!=null&&b._rewindHistory!.startHp!=w.hp)||b.id!=w.sequence||b.turn<1||b.enemyHp<1||b.enemyHp>b.encounter.hp||b.stats.hp<1||b.stats.physicalMax<1||b.stats.magicMax<1||b.stats.defense<0||b.stats.physical<1||b.stats.magic<1||!b.stats.crit.isFinite||b.stats.crit<0||b.stats.crit>1||w.hp<1||w.hp>b.stats.hp||w.physical>b.stats.physicalMax||w.magic>b.stats.magicMax||b.slowTurns<0||b.slowTurns>2||b.acceleratedClaws<0||b.acceleratedClaws>2||b.stopCooldown<0||b.stopCooldown>5||b.energyRemainder<0||b.energyRemainder>=WorldEngine.energyInterval||b.hpRemainder<0||b.hpRemainder>=WorldEngine.hpInterval)throw const FormatException('Invalid active battle');}
  return w;
 }
}

class WorldEngine {
 WorldEngine({Random? random,Random? seedRandom}):_testRandom=random,_seedRandom=seedRandom??Random.secure();
 // 既存の固定乱数ユニット試験専用。本番Controllerは指定しない。
 final Random? _testRandom;
 final Random _seedRandom;
 /// 覚醒は物理攻撃のみ。攻撃強化薬とは加算せず高い補正を採用する。
 double _attackBonus(WorldBattle b,{required bool physical}){
  final item=b._buffs.containsKey(BattleBuff.attack)?BattleBuff.attack.percent:0;
  final awakening=physical&&b.awakeningTurns>0?b.awakeningRules.awakeningPercent:0;
  return 1+max(item,awakening)/100;
 }
 double _roll(WorldBattle battle)=>_testRandom?.nextDouble()??BattleRandom.next(battle);
 static const energyInterval=600000,hpInterval=1800000;
 /// 加算・積を計算する前に残容量と比較する。上限超過の既存値も回復時に正規化。
 static int _cappedGain(int current,int maximum,int amount,{int times=1}){
  if(current<0||maximum<0||amount<0||times<0)throw StateError('Invalid recovery operands');
  if(current>=maximum)return maximum;
  final room=maximum-current;
  if(amount==0||times==0)return current;
  if(times>room~/amount)return maximum;
  return current+amount*times;
 }
 bool isUnlocked(WorldState w,WorldEncounter e){
  if(e.main)return !w.cleared.contains(e.id)&&(e.stage==1||w.cleared.contains(WorldCatalog.mainId(e.stage-1)));
  return w.cleared.contains(WorldCatalog.mainId(e.stage));
 }
 /// 0.01%単位の割合補正。整数切捨て・64bit上限検証。
 static int equipmentRewardAmount(int base,int bonus){
  if(base<0||bonus<0||bonus>10000)throw StateError('Invalid equipment reward');
  return WorldStats.checkedStat(BigInt.from(base)*BigInt.from(10000+bonus)~/BigInt.from(10000));
 }
 static int _naturalAmount(int base,int bonus){
  if(bonus<0||bonus>30000)throw StateError('Invalid natural recovery bonus');
  return WorldStats.checkedStat(BigInt.from(base)*BigInt.from(10000+bonus)~/BigInt.from(10000));
 }
 bool refresh(WorldState w,WorldStats s,int now,{int naturalRecovery=0}){
  if(w.battle!=null)return false;
  final before=[w.hp,w.physical,w.magic,w.energyAt,w.hpAt].join(',');
  if(w.energyAt==0){w.energyAt=now;w.physical=s.physicalMax;w.magic=s.magicMax;}
  if(now<w.energyAt)w.energyAt=now;
  if(w.hpAt==0){w.hpAt=now;w.hp=s.hp;}
  if(now<w.hpAt)w.hpAt=now;
  final ticks=(now-w.energyAt)~/energyInterval,heals=(now-w.hpAt)~/hpInterval;
  w.physical=_cappedGain(w.physical,s.physicalMax,_naturalAmount(1,naturalRecovery),times:ticks);
  w.magic=_cappedGain(w.magic,s.magicMax,_naturalAmount(1,naturalRecovery),times:ticks);
  w.hp=_cappedGain(w.hp,s.hp,_naturalAmount(max(1,s.hp~/20),naturalRecovery),times:heals);
  w.energyAt+=ticks*energyInterval;
  w.hpAt+=heals*hpInterval;
  final pending=w.pendingPhysical>0||w.pendingMagic>0||w.pendingLevelUp;
  if(pending){
   w.physical=w.pendingLevelUp?s.physicalMax:_cappedGain(w.physical,s.physicalMax,w.pendingPhysical);
   w.magic=w.pendingLevelUp?s.magicMax:_cappedGain(w.magic,s.magicMax,w.pendingMagic);
   if(w.pendingLevelUp)w.hp=s.hp;
   w.pendingPhysical=0;w.pendingMagic=0;w.pendingLevelUp=false;
  }
  return pending||before!=[w.hp,w.physical,w.magic,w.energyAt,w.hpAt].join(',');
 }
 void rewardEffort(WorldState w,WorldStats s,int now,{required int physical,required int magic,required bool levelUp,int naturalRecovery=0}){
  if(physical<0||magic<0)throw StateError('Invalid effort reward');
  if(w.battle!=null){
   w.pendingPhysical=_cappedGain(w.pendingPhysical,s.physicalMax,physical);
   w.pendingMagic=_cappedGain(w.pendingMagic,s.magicMax,magic);
   w.pendingLevelUp=w.pendingLevelUp||levelUp;
   return;
  }
  refresh(w,s,now,naturalRecovery:naturalRecovery);
  w.physical=levelUp?s.physicalMax:_cappedGain(w.physical,s.physicalMax,physical);
  w.magic=levelUp?s.magicMax:_cappedGain(w.magic,s.magicMax,magic);
  if(levelUp)w.hp=s.hp;
 }
 void start(WorldState w,WorldStats s,String id,int now,{List<ActiveSkillSpec> activeSkills=const [],List<LifeRewardBonus> lifeRewardBonuses=const [],BattleEquipmentEffects? equipmentEffects,List<ExBattleAttack> exAttacks=const []}){
  ExBattleAttack.validate(exAttacks,1);
  if(exAttacks.isNotEmpty&&equipmentEffects==null)throw const FormatException('EX equipment snapshot required');
  LifeRewardBonus.validate(lifeRewardBonuses);
  if(lifeRewardBonuses.isNotEmpty&&!w.cleared.contains(WorldCatalog.mainId(3)))throw StateError('STAGE 03 clear required');
  if(activeSkills.length>6||activeSkills.map((s)=>s.id).toSet().length!=activeSkills.length)throw const FormatException('Invalid active skill snapshot');
  for(final spec in activeSkills){
   spec.validate();
   if(spec.missingStage(w.cleared)!=null)throw StateError('Active skill stage not cleared: ${spec.id}');
  }
  if(w.battle!=null)throw StateError('A battle is already active');
  final e=WorldCatalog.byId(id);
  if(!isUnlocked(w,e))throw StateError('Encounter locked or completed');
  final rewardReason=victoryRewardUnavailable(w,e,rewardBonus:equipmentEffects?.reward??0);
  if(rewardReason!=null)throw StateError(rewardReason);
  final battleStats=equipmentEffects?.apply(s)??s;
  refresh(w,battleStats,now,naturalRecovery:equipmentEffects?.naturalRecovery??0);
  if(w.hp<=0)throw StateError('HP recovery required');
  if(w.sequence==0x7fffffffffffffff)throw StateError('Battle sequence overflow');
  final seed=_seedRandom.nextInt(BattleRandom.modulus-1)+1;
  w.sequence++;
  w.battle=WorldBattle(encounterSnapshot:e,executionVersion:exAttacks.any((a)=>a.attribute==ExAttackAttribute.hpRecovery)?10:exAttacks.isNotEmpty?9:equipmentEffects==null?WorldBattle.currentExecutionVersion:equipmentEffects.requiresV8?8:equipmentEffects.requiresV7?7:equipmentEffects.requiresV6?6:equipmentEffects.requiresV5?5:4,equipmentEffects:equipmentEffects,exAttacks:exAttacks,lifeRewardPercent:LifeRewardBonus.totalPercent(lifeRewardBonuses),activeSkills:activeSkills,lifeRewardBonuses:lifeRewardBonuses,rewindHistory:activeSkills.any((s)=>s.effect==ActiveSkillEffect.rewindHp)?(startHp:w.hp,previousHp:null):null,rngState:seed,id:w.sequence,encounterId:id,stats:battleStats,enemyHp:e.hp,energyRemainder:now-w.energyAt,hpRemainder:now-w.hpAt,log:['${e.enemy} が現れた。']);
  w.lastResult='';
 }
 /// 単一の消費計算を可否・実行・画面で共有する。寿命には適用しない。
 int energyCost(WorldState w,WorldCommand command){
  final base=switch(command){WorldCommand.claw=>4,WorldCommand.heavyClaw=>9,WorldCommand.magic=>6,_=>0};
  return _discountedCost(w,base);
 }
 /// 勝利時の整数資源を加算前に検査する。寿命はBigIntのため別上限を設けない。
 static const maxRewardResource=0x7fffffffffffffff;
 static const mainFirstTickets=3,freeFirstTickets=1;
 static bool _fitsReward(int balance,int reward)=>balance>=0&&reward>=0&&balance<=maxRewardResource-reward;
 String? victoryRewardUnavailable(WorldState w,WorldEncounter e,{int? rewardBonus}){
  final bonus=rewardBonus??w.battle?.equipmentEffects?.reward??0;
  final amount=BigInt.from(e.gold)*BigInt.from(10000+bonus)~/BigInt.from(10000);
  if(amount>BigInt.from(maxRewardResource)||!_fitsReward(w.gold,amount.toInt()))return 'ゴールド報酬が所持上限を超えます';
  if(!w.cleared.contains(e.id)){
   if(e.main&&!_fitsReward(w.summonTickets,mainFirstTickets))return '召喚券報酬が所持上限を超えます';
   if(!e.main&&!_fitsReward(w.supplyTickets,freeFirstTickets))return '補給券報酬が所持上限を超えます';
  }
  return null;
 }
 bool _canDamage(WorldCommand command)=>switch(command){
  WorldCommand.claw||WorldCommand.heavyClaw||WorldCommand.magic||WorldCommand.compositeClaw=>true,
  WorldCommand.guard||WorldCommand.slow||WorldCommand.retreat||WorldCommand.accelerate||WorldCommand.stopTime=>false,
 };
 bool _activeCanDamage(ActiveSkillSpec spec)=>switch(spec.effect){
  ActiveSkillEffect.physical||ActiveSkillEffect.accelerationAttack||ActiveSkillEffect.stopAttack||ActiveSkillEffect.ultimateAttack=>true,
  ActiveSkillEffect.foresight||ActiveSkillEffect.repairHp||ActiveSkillEffect.timeCleanse||ActiveSkillEffect.rewindHp||ActiveSkillEffect.crimsonAwakening=>false,
 };
 String? unavailable(WorldState w,WorldCommand command){
  final b=w.battle;
  if(b==null)return '戦闘中ではありません';
  if(_canDamage(command)){
   final reason=victoryRewardUnavailable(w,b.encounter);
   if(reason!=null)return reason;
  }
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
 /// 停止系コマンドと奥義で共有する停止CDと耐性判定。
 bool _applyStop(WorldBattle b,WorldEncounter e,{int cooldown=ActiveSkillRulesV1.stopCooldown}){
  b.stopCooldown=cooldown;
  return !e.timeResistant;
 }
 /// 通常の浮動小数演算順・最小1を維持し、整数変換境界を明示する。
 int _enemyDefense(WorldBattle b)=>(BigInt.from(b.encounter.defense)*BigInt.from(10000-(b.equipmentEffects?.penetration??0))~/BigInt.from(10000)).toInt();
 /// 元属性の基礎攻撃50%、1行動1回、無消費。元攻撃で撃破したら抽選しない。
 void _extraAttack(WorldBattle b,{required bool physical}){
  final chance=b.equipmentEffects?.extraAttack??0;
  if(chance==0||b.enemyHp<=0||_roll(b)>=chance/10000)return;
  final critical=_roll(b)<_criticalChance(b)?1.5:1.0;
  final variance=0.95+_roll(b)*0.10;
  final dealt=damage(physical?b.stats.physical:b.stats.magic,_enemyDefense(b),0.5*_attackBonus(b,physical:physical),critical:critical,variance:variance);
  b.enemyHp=max(0,b.enemyHp-dealt);
  b.log.add('追加攻撃 — ${critical>1?'会心！ ':''}$dealt ダメージ');
 }
 int damage(int attack,int defense,double multiplier,{double critical=1,double variance=1}){
  if(attack<0||defense<0||[multiplier,critical,variance].any((v)=>!v.isFinite||v<0))throw StateError('Invalid damage operands');
  final value=attack*multiplier*100/(100.0+defense)*critical*variance;
  if(!value.isFinite)throw StateError('Nonfinite damage');
  if(value>=maxRewardResource.toDouble())return maxRewardResource;
  return max(1,value.floor());
 }
 void act(WorldState w,WorldCommand command,int battleId,int expectedTurn,int now){
  final b=w.battle;
  if(b==null||b.id!=battleId||b.turn!=expectedTurn)throw StateError('Stale battle command');
  if(b.turn==0x7fffffffffffffff)throw StateError('Battle turn overflow');
  final unavailableReason=unavailable(w,command);
  if(unavailableReason!=null)throw StateError(unavailableReason);
  final e=b.encounter,s=b.stats;
  final attackBonus=_attackBonus(b,physical:command!=WorldCommand.magic);
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
   skipEnemy=_applyStop(b,e);
   b.log.add(skipEnemy?'時間停止 — 敵の行動停止':'時間停止は無効化された。');
  }else if(guarding){b.log.add('防御態勢');}
  else{
   final chance=_criticalChance(b);
   final critical=_roll(b)<chance?1.5:1.0;
   final variance=0.95+_roll(b)*0.10;
   switch(command){
    case WorldCommand.claw:
     final cost=energyCost(w,command);
     final strong=w.physical>=cost;
     if(strong)w.physical-=cost;
     dealt=damage(s.physical,_enemyDefense(b),(strong?1.0:0.25)*(b.acceleratedClaws>0?2.0:1.0)*attackBonus,critical:critical,variance:variance);
     if(b.acceleratedClaws>0)b.acceleratedClaws--;
    case WorldCommand.heavyClaw:
     w.physical-=energyCost(w,command);dealt=damage(s.physical,_enemyDefense(b),1.8*attackBonus,critical:critical,variance:variance);
    case WorldCommand.compositeClaw:
     w.lifespan-=BigInt.from(90);
     skipEnemy=_applyStop(b,e);
     b.log.add(skipEnemy?'複合爪撃 — 時間停止・自己加速・爪撃':'複合爪撃 — 時間停止は無効化された。');
     dealt=damage(s.physical,_enemyDefense(b),4.0*attackBonus,critical:critical,variance:variance);
    case WorldCommand.magic:
     w.magic-=energyCost(w,command);dealt=damage(s.magic,_enemyDefense(b),1.2*attackBonus,critical:critical,variance:variance);
    default:break;
   }
   b.enemyHp=max(0,b.enemyHp-dealt);
   b.log.add('${critical>1?'会心！ ':''}$dealt ダメージ');
   _extraAttack(b,physical:command!=WorldCommand.magic);
  }
  if(_victory(w,now))return;
  _finishTurn(w,now,skipEnemy:skipEnemy,guarding:guarding,castingStop:castingStop);
 }
 bool _victory(WorldState w,int now){
  final b=w.battle!,e=w.battle!.encounter;
  if(b.enemyHp==0){
   final reason=victoryRewardUnavailable(w,e);
   if(reason!=null)throw StateError(reason);
   final life=LifeRewardBonus.rewardAtPercent(e.lifeDays,b.lifeRewardPercent);
   final first=w.cleared.add(e.id);
   final gold=equipmentRewardAmount(e.gold,b.equipmentEffects?.reward??0);
   w.gold+=gold;
   w.lifespan+=life;
   if(first){if(e.main){w.summonTickets+=mainFirstTickets;}else{w.supplyTickets+=freeFirstTickets;}}
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
 int _effectiveCooldown(WorldBattle b,ActiveSkillSpec spec)=>BattleEquipmentEffects.effectiveCooldown(spec,b.equipmentEffects?.cooldown??0);
 int activeSkillCooldown(WorldBattle b,ActiveSkillSpec spec)=>spec.usesStopCooldown?b.stopCooldown:b.skillCooldowns[spec.id]??0;
 int _discountedCost(WorldState w,int base){
  final b=w.battle;
  final buff=b?.buffs.containsKey(BattleBuff.energyDiscount)==true?BattleBuff.energyDiscount.percent*100:0;
  final discount=min(5000,buff+(b?.equipmentEffects?.discount??0));
  return (base*(10000-discount)+9999)~/10000;
 }
 double _criticalChance(WorldBattle b)=>min<double>(1,b.stats.crit+(b.equipmentEffects?.critical??0)/10000+(b._buffs.containsKey(BattleBuff.critical)?BattleBuff.critical.percent/100:0));
 double _evasionChance(WorldBattle b)=>min<double>(0.5,(b.equipmentEffects?.evasion??0)/10000+(b._buffs.containsKey(BattleBuff.evasion)?BattleBuff.evasion.percent/100:0));
 /// The HP sacrifice cannot be evaded or reduced; ceil and leave at least 1 HP.
 int _exHpCost(WorldBattle b,ExBattleAttack a)=>((BigInt.from(b.stats.hp)*BigInt.from(a.hpCostBps)+BigInt.from(9999))~/BigInt.from(10000)).toInt();
 int _exEnergyCost(WorldState w,ExBattleAttack a,int base)=>a.energyDiscount?_discountedCost(w,base):base;
 String? exAttackUnavailable(WorldState w,int slot){
  final b=w.battle;
  if(b==null)return '戦闘中ではありません';
  final matches=b.exAttacks.where((a)=>a.slot==slot);
  if(matches.isEmpty)return 'EXスキル未登録';
  final a=matches.single;
  if(b.turn==0x7fffffffffffffff)return 'ターン上限';
  if(a.remaining(b.turn)>0)return 'クールダウン中';
  if(a.maxUses!=null&&a.uses>=a.maxUses!)return '使用回数上限';
  if(a.maxHpBps!=null&&BigInt.from(w.hp)*BigInt.from(10000)>BigInt.from(b.stats.hp)*BigInt.from(a.maxHpBps!))return 'HP条件未達';
  if(a.attribute==ExAttackAttribute.hpRecovery&&w.hp==b.stats.hp)return 'HPは満タンです';
  if(w.hp<=_exHpCost(b,a))return 'HP不足';
  if(w.lifespan<BigInt.from(a.lifeDays))return '寿命不足';
  if(w.physical<_exEnergyCost(w,a,a.physicalCost))return '物理エネルギー不足';
  if(w.magic<_exEnergyCost(w,a,a.magicCost))return '魔法エネルギー不足';
  return a.attribute==ExAttackAttribute.hpRecovery?null:victoryRewardUnavailable(w,b.encounter);
 }
 void actExAttack(WorldState w,int slot,int battleId,int expectedTurn,int now){
  final b=w.battle;
  if(b==null||b.id!=battleId||b.turn!=expectedTurn)throw StateError('Stale battle command');
  final reason=exAttackUnavailable(w,slot);
  if(reason!=null)throw StateError(reason);
  final index=b._exAttacks.indexWhere((a)=>a.slot==slot),a=b._exAttacks.firstWhere((a)=>a.slot==slot);
  final physicalCost=_exEnergyCost(w,a,a.physicalCost),magicCost=_exEnergyCost(w,a,a.magicCost),hpCost=_exHpCost(b,a);
  w.physical-=physicalCost;
  w.magic-=magicCost;
  w.hp-=hpCost;
  w.lifespan-=BigInt.from(a.lifeDays);
  b._exAttacks[index]=a.cast(b.turn);
  b.log.add('EX代償 — 物理 $physicalCost / 魔法 $magicCost / HP $hpCost / 寿命 ${a.lifeDays}日');
  if(a.attribute==ExAttackAttribute.hpRecovery){
   final base=(BigInt.from(b.stats.hp)*BigInt.from(a.powerBps)~/BigInt.from(10000)).toInt();
   final amount=min(b.stats.hp-w.hp,max(1,base));
   w.hp+=amount;
   b.log.add('EX ${a.skillId} — HP +$amount');
   _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false);
   return;
  }
  final physical=a.attribute==ExAttackAttribute.physical;
  final critical=_roll(b)<_criticalChance(b)?1.5:1.0;
  final variance=0.95+_roll(b)*0.10;
  final dealt=damage(physical?b.stats.physical:b.stats.magic,_enemyDefense(b),a.powerBps/10000*_attackBonus(b,physical:physical),critical:critical,variance:variance);
  b.enemyHp=max(0,b.enemyHp-dealt);
  b.log.add('EX ${a.skillId} — ${critical>1?'会心！ ':''}$dealt ダメージ');
  _extraAttack(b,physical:physical);
  if(_victory(w,now))return;
  _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false);
 }
 int activeSkillCost(WorldState w,ActiveSkillSpec spec)=>_discountedCost(w,spec.physicalCost);
 String? activeSkillUnavailable(WorldState w,String id){
  final b=w.battle;
  if(b==null)return '戦闘中ではありません';
  final matches=b.activeSkills.where((s)=>s.id==id);
  if(matches.isEmpty)return '装着済みスキルではありません';
  if(b.turn==0x7fffffffffffffff)return 'ターン上限';
  final spec=matches.first;
  String? stageUnavailable(){
   final stage=spec.missingStage(w.cleared);
   return stage==null?null:'STAGE ${stage.toString().padLeft(2,'0')}クリアが必要';
  }
  if(spec.usesStopCooldown){
   final reason=stageUnavailable();
   if(reason!=null)return reason;
  }
  if(activeSkillCooldown(b,spec)>0)return 'クールダウン中';
  final stageReason=stageUnavailable();
  if(stageReason!=null)return stageReason;
  if(spec.effect==ActiveSkillEffect.repairHp){
   if(w.hp<=0||w.hp>b.stats.hp||b.stats.hp<=0)return 'HP状態が不正です';
   if(w.hp==b.stats.hp)return 'HPは満タンです';
  }
  if(spec.effect==ActiveSkillEffect.timeCleanse&&!b._statuses.containsKey(BattleStatus.poison))return '解除可能な状態異常なし';
  if(spec.effect==ActiveSkillEffect.rewindHp){
   final history=b._rewindHistory,previous=b.previousTurnHp;
   if(b.turn<=1||history==null||previous==null)return '前ターンのHP記録なし';
   if(history.startHp!=w.hp||w.hp<=0||previous<1||previous>b.stats.hp||w.hp>b.stats.hp)return 'HP状態が不正です';
   if(previous<=w.hp)return '復元できるHPなし';
  }
  if(spec.effect==ActiveSkillEffect.crimsonAwakening){
   if(b.awakeningTurns>0)return '覚醒発動中';
  }
  if(w.lifespan<BigInt.from(spec.lifeCost))return '寿命不足';
  if(w.physical<activeSkillCost(w,spec))return '物理エネルギー不足';
  if(_activeCanDamage(spec))return victoryRewardUnavailable(w,b.encounter);
  return null;
 }
 void actActiveSkill(WorldState w,String id,int battleId,int expectedTurn,int now){
  final b=w.battle;
  if(b==null||b.id!=battleId||b.turn!=expectedTurn)throw StateError('Stale battle command');
  final reason=activeSkillUnavailable(w,id);
  if(reason!=null)throw StateError(reason);
  final spec=b.activeSkills.firstWhere((s)=>s.id==id);
  final e=b.encounter,s=b.stats;
  w.physical-=activeSkillCost(w,spec);
  w.lifespan-=BigInt.from(spec.lifeCost);
  if(spec.effect==ActiveSkillEffect.crimsonAwakening){
   b._awakeningTurns=spec.rules.awakeningDuration;
   b._skillCooldowns[id]=_effectiveCooldown(b,spec);
   b.log.add('${spec.name} — 寿命 ${spec.lifeCost}日消費 / 物攻 +${spec.rules.awakeningPercent}%');
   _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false,castSkill:id);
   return;
  }
  if(spec.effect==ActiveSkillEffect.foresight){
   b.log.add('${spec.name} — 寿命 ${spec.lifeCost}日消費');
   b._skillCooldowns[id]=_effectiveCooldown(b,spec);
   _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false,castSkill:id,foresight:true);
   return;
  }
  if(spec.effect==ActiveSkillEffect.rewindHp){
   final amount=b.previousTurnHp!-w.hp;
   w.hp=b.previousTurnHp!;
   b.log.add('${spec.name} — 寿命 ${spec.lifeCost}日消費 / HP +$amount');
   b._skillCooldowns[id]=_effectiveCooldown(b,spec);
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
   b._skillCooldowns[id]=_effectiveCooldown(b,spec);
   _finishTurn(w,now,skipEnemy:false,guarding:false,castingStop:false,castSkill:id);
   return;
  }
  if(spec.effect==ActiveSkillEffect.accelerationAttack||spec.effect==ActiveSkillEffect.ultimateAttack||spec.usesStopCooldown)b.log.add('${spec.name} — 寿命 ${spec.lifeCost}日消費');
  final skipEnemy=spec.usesStopCooldown&&_applyStop(b,e,cooldown:spec.rules.sharedStopCooldown);
  if(spec.usesStopCooldown)b.log.add(skipEnemy?'時間停止 — 敵の行動停止':'時間停止は無効化された。');
  final bonus=_attackBonus(b,physical:true);
  final chance=_criticalChance(b);
  // 各hitで独立に会心・乱数・防御・丸めを適用。撃破後は乱数を消費しない。
  for(var hit=0;hit<spec.hits&&b.enemyHp>0;hit++){
   final critical=_roll(b)<chance?1.5:1.0;
   final variance=0.95+_roll(b)*0.10;
   final dealt=damage(s.physical,_enemyDefense(b),spec.powerPercent/100*bonus,critical:critical,variance:variance);
   b.enemyHp=max(0,b.enemyHp-dealt);
   final label=spec.hits==1?spec.name:'${spec.name} ${hit+1}/${spec.hits}';
   b.log.add('$label — ${critical>1?'会心！ ':''}$dealt ダメージ');
  }
  _extraAttack(b,physical:true);
  if(spec.cooldown>0)b._skillCooldowns[id]=_effectiveCooldown(b,spec);
  if(_victory(w,now))return;
  _finishTurn(w,now,skipEnemy:skipEnemy,guarding:false,castingStop:spec.usesStopCooldown,castSkill:id);
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
 /// 状態異常付与の共通入口。敵の付与能力・発動確率は別途承認して接続する。
 /// 成立済み付与要求にのみ耐性を抽選し、既存状態の持続は変更しない。
 bool tryInflictStatus(WorldState w,BattleStatus kind,int battleId,int expectedTurn){
  final b=w.battle;
  if(b==null||b.id!=battleId||b.turn!=expectedTurn||w.hp<=0||b.enemyHp<=0)throw StateError('Stale status application');
  final resistance=b.equipmentEffects?.resistance??0;
  if(resistance>0&&_roll(b)<resistance/10000){
   b.log.add('${kind.label} — 状態異常耐性で無効化');
   return false;
  }
  b._statuses[kind]=kind.duration;
  b.log.add('${kind.label} — 状態異常付与');
  return true;
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
  if(kind==BattleBuff.regenerationSuppression&&b.encounter.regenerationPercent==0)throw StateError('Enemy has no regeneration');
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
  final e=b.encounter,s=b.stats;
  if(!skipEnemy){
   final int extra=(s.defense~/100)*BattleBuff.defense.percent+(s.defense%100)*BattleBuff.defense.percent~/100;
   final defense=b._buffs.containsKey(BattleBuff.defense)?_cappedGain(s.defense,maxRewardResource,extra):s.defense;
   final rawAttack=damage(e.attack,defense,(b.slowTurns>0?0.7:1.0)*(guarding?0.5:1.0));
   final attack=max(1,(BigInt.from(rawAttack)*BigInt.from(10000-(b.equipmentEffects?.reduction??0))~/BigInt.from(10000)).toInt());
   if(foresight){
    b.log.add('未来視 — 敵の反撃を無効化した。');
   }else if(_evasionChance(b)>0&&_roll(b)<_evasionChance(b)){
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
  if(b._awakeningTurns>0&&castSkill!='skill:crimson_awakening')b._awakeningTurns--;
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
