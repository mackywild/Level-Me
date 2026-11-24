import 'dart:math';
import 'world_catalog.dart';

enum WorldCommand { claw, heavyClaw, magic, guard, slow, retreat }

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

class WorldBattle {
 WorldBattle({required this.id,required this.encounterId,required this.stats,required this.enemyHp,this.turn=1,this.slowTurns=0,List<String>? log}):log=log??[];
 final int id;
 final String encounterId;
 final WorldStats stats;
 int enemyHp,turn,slowTurns;
 final List<String> log;
 Map<String,dynamic> toJson()=>{'id':id,'encounterId':encounterId,'stats':stats.toJson(),'enemyHp':enemyHp,'turn':turn,'slowTurns':slowTurns,'log':log};
 factory WorldBattle.fromJson(Map<String,dynamic> j)=>WorldBattle(id:j['id'] as int,encounterId:j['encounterId'] as String,stats:WorldStats.fromJson(j['stats'] as Map<String,dynamic>),enemyHp:j['enemyHp'] as int,turn:j['turn'] as int,slowTurns:j['slowTurns'] as int,log:List<String>.from(j['log'] as List));
}

class WorldState {
 WorldState({this.hp=100,this.physical=27,this.magic=38,this.gold=0,this.summonTickets=0,this.supplyTickets=0,this.sequence=0,this.energyAt=0,this.hpAt=0,BigInt? lifespan,Set<String>? cleared,this.battle,this.lastResult='' }):lifespan=lifespan??BigInt.zero,cleared=cleared??{};
 int hp,physical,magic,gold,summonTickets,supplyTickets,sequence,energyAt,hpAt;
 BigInt lifespan;
 final Set<String> cleared;
 WorldBattle? battle;
 String lastResult;
 Map<String,dynamic> toJson()=>{'version':1,'hp':hp,'physical':physical,'magic':magic,'gold':gold,'summonTickets':summonTickets,'supplyTickets':supplyTickets,'sequence':sequence,'energyAt':energyAt,'hpAt':hpAt,'lifespanDays':lifespan.toString(),'cleared':cleared.toList()..sort(),'battle':battle?.toJson(),'lastResult':lastResult};
 factory WorldState.fromJson(Map<String,dynamic> j){
  if(j['version']!=1)throw const FormatException('Unsupported world save version');
  final w=WorldState(hp:j['hp'] as int,physical:j['physical'] as int,magic:j['magic'] as int,gold:j['gold'] as int,summonTickets:j['summonTickets'] as int,supplyTickets:j['supplyTickets'] as int,sequence:j['sequence'] as int,energyAt:j['energyAt'] as int,hpAt:j['hpAt'] as int,lifespan:BigInt.parse(j['lifespanDays'] as String),cleared:List<String>.from(j['cleared'] as List).toSet(),battle:j['battle']==null?null:WorldBattle.fromJson(j['battle'] as Map<String,dynamic>),lastResult:j['lastResult'] as String);
  if([w.hp,w.physical,w.magic,w.gold,w.summonTickets,w.supplyTickets,w.sequence,w.energyAt,w.hpAt].any((v)=>v<0)||w.lifespan<BigInt.zero)throw const FormatException('Negative world resource');
  if(w.battle!=null){final b=w.battle!;if(b.id!=w.sequence||b.turn<1||b.enemyHp<1||b.enemyHp>WorldCatalog.byId(b.encounterId).hp||b.stats.hp<1||b.stats.physicalMax<1||b.stats.magicMax<1||b.stats.defense<0||b.stats.physical<1||b.stats.magic<1||!b.stats.crit.isFinite||b.stats.crit<0||b.stats.crit>1||w.hp<1||w.hp>b.stats.hp||w.physical>b.stats.physicalMax||w.magic>b.stats.magicMax||b.slowTurns<0||b.slowTurns>2)throw const FormatException('Invalid active battle');}
  return w;
 }
}

class WorldEngine {
 WorldEngine({Random? random}):_random=random??Random();
 final Random _random;
 static const energyInterval=600000,hpInterval=1800000;
 bool isUnlocked(WorldState w,WorldEncounter e){
  if(e.main)return !w.cleared.contains(e.id)&&(e.stage==1||w.cleared.contains('p0${e.stage-1}_main'));
  return w.cleared.contains('p0${e.stage}_main');
 }
 bool refresh(WorldState w,WorldStats s,int now){
  if(w.battle!=null)return false;
  final before=[w.hp,w.physical,w.magic,w.energyAt,w.hpAt].join(',');
  if(w.energyAt==0||now<w.energyAt)w.energyAt=now;
  if(w.hpAt==0||now<w.hpAt)w.hpAt=now;
  final ticks=(now-w.energyAt)~/energyInterval,heals=(now-w.hpAt)~/hpInterval;
  w.physical=min(s.physicalMax,w.physical+ticks);
  w.magic=min(s.magicMax,w.magic+ticks);
  w.hp=min(s.hp,w.hp+heals*max(1,(s.hp*0.05).floor()));
  w.energyAt+=ticks*energyInterval;
  w.hpAt+=heals*hpInterval;
  return before!=[w.hp,w.physical,w.magic,w.energyAt,w.hpAt].join(',');
 }
 void rewardEffort(WorldState w,WorldStats s,int now,{required int physical,required int magic,required bool levelUp}){
  if(w.battle!=null)return; // Battle snapshot is isolated from changes in daily stats.
  refresh(w,s,now);
  w.physical=levelUp?s.physicalMax:min(s.physicalMax,w.physical+physical);
  w.magic=levelUp?s.magicMax:min(s.magicMax,w.magic+magic);
  if(levelUp)w.hp=s.hp;
 }
 void start(WorldState w,WorldStats s,String id,int now){
  if(w.battle!=null)throw StateError('A battle is already active');
  final e=WorldCatalog.byId(id);
  if(!isUnlocked(w,e))throw StateError('Encounter locked or completed');
  refresh(w,s,now);
  if(w.hp<=0)throw StateError('HP recovery required');
  w.sequence++;
  w.battle=WorldBattle(id:w.sequence,encounterId:id,stats:s,enemyHp:e.hp,log:['${e.enemy} が現れた。']);
  w.lastResult='';
 }
 String? unavailable(WorldState w,WorldCommand command){
  if(w.battle==null)return '戦闘中ではありません';
  return switch(command){
   WorldCommand.heavyClaw=>w.physical<9?'物理エネルギー不足':null,
   WorldCommand.magic=>w.magic<6?'魔法エネルギー不足':null,
   WorldCommand.slow=>!w.cleared.contains('p03_main')?'STAGE 03クリアで解放':w.lifespan<BigInt.from(3)?'寿命不足':w.battle!.slowTurns>0?'効果発動中':null,
   _=>null,
  };
 }
 int damage(int attack,int defense,double multiplier,{double critical=1,double variance=1})=>max(1,(attack*multiplier*100/(100+defense)*critical*variance).floor());
 void act(WorldState w,WorldCommand command,int battleId,int expectedTurn,int now){
  final b=w.battle;
  if(b==null||b.id!=battleId||b.turn!=expectedTurn)throw StateError('Stale battle command');
  final unavailableReason=unavailable(w,command);
  if(unavailableReason!=null)throw StateError(unavailableReason);
  final e=WorldCatalog.byId(b.encounterId),s=b.stats;
  if(command==WorldCommand.retreat){_end(w,now,'撤退 — 消費済み資源は返還されません');return;}
  var dealt=0;
  final guarding=command==WorldCommand.guard;
  if(command==WorldCommand.slow){
   w.lifespan-=BigInt.from(3);
   if(e.timeResistant){b.log.add('時間遅延は無効化された。');}else{b.slowTurns=2;b.log.add('時間遅延 — 敵攻撃力30%低下');}
  }else if(guarding){b.log.add('防御態勢');}
  else{
   final critical=_random.nextDouble()<s.crit?1.5:1.0;
   final variance=0.95+_random.nextDouble()*0.10;
   switch(command){
    case WorldCommand.claw:
     final strong=w.physical>=4;
     if(strong)w.physical-=4;
     dealt=damage(s.physical,e.defense,strong?1:0.25,critical:critical,variance:variance);
    case WorldCommand.heavyClaw:
     w.physical-=9;dealt=damage(s.physical,e.defense,1.8,critical:critical,variance:variance);
    case WorldCommand.magic:
     w.magic-=6;dealt=damage(s.magic,e.defense,1.2,critical:critical,variance:variance);
    default:break;
   }
   b.enemyHp=max(0,b.enemyHp-dealt);
   b.log.add('${critical>1?'会心！ ':''}$dealt ダメージ');
  }
  if(b.enemyHp==0){
   final first=w.cleared.add(e.id);
   final gold=e.gold;
   w.gold+=gold;
   w.lifespan+=BigInt.from(e.lifeDays);
   if(first){if(e.main){w.summonTickets+=3;}else{w.supplyTickets++;}}
   _end(w,now,'勝利 — $gold G / 寿命 +${e.lifeDays}日${first?' / 初回報酬獲得':''}');
   return;
  }
  final attack=damage(e.attack,s.defense,(b.slowTurns>0?0.7:1.0)*(guarding?0.5:1.0));
  w.hp=max(0,w.hp-attack);
  b.log.add('敵の反撃 — HP -$attack');
  if(b.slowTurns>0)b.slowTurns--;
  if(w.hp==0){_end(w,now,'敗北 — 回復後に再挑戦できます');return;}
  b.turn++;
  if(b.log.length>12)b.log.removeRange(0,b.log.length-12);
 }
 void _end(WorldState w,int now,String result){w.battle=null;w.energyAt=now;w.hpAt=now;w.lastResult=result;}
}
