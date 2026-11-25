import 'dart:math';
import 'abyss_inventory.dart';
import 'abyss_equipment.dart';
import 'abyss_summon.dart';
import 'world_engine.dart';

class SummonReward {
 const SummonReward({required this.masterId,required this.rarity,this.instanceId});
 final String masterId;
 final EquipmentRarity rarity;
 final String? instanceId;
 Map<String,dynamic> toJson()=>{'masterId':masterId,'rarity':rarity.name,'instanceId':instanceId};
 factory SummonReward.fromJson(Map<String,dynamic> j){
  final id=j['masterId'] as String;
  final instance=j['instanceId'] as String?;
  if(id.trim().isEmpty||instance!=null&&instance.trim().isEmpty)throw const FormatException('Invalid reward ID');
  return SummonReward(masterId:id,rarity:EquipmentRarity.values.byName(j['rarity'] as String),instanceId:instance);
 }
}

class SummonReceipt {
 SummonReceipt({required this.sequence,required this.pool,required List<SummonReward> rewards}):rewards=List.unmodifiable(rewards);
 final int sequence;
 final SummonPool pool;
 final List<SummonReward> rewards;
 Map<String,dynamic> toJson()=>{'sequence':sequence,'pool':pool.name,'rewards':rewards.map((e)=>e.toJson()).toList()};
 factory SummonReceipt.fromJson(Map<String,dynamic> j){
  final sequence=j['sequence'] as int;
  final rewards=(j['rewards'] as List).map((e)=>SummonReward.fromJson(e as Map<String,dynamic>)).toList();
  if(sequence<1||(rewards.length!=1&&rewards.length!=10))throw const FormatException('Invalid summon receipt');
  final pool=SummonPool.values.byName(j['pool'] as String);
  final ids=<String>{};
  for(final reward in rewards){
   final id=reward.instanceId;
   final prefix=pool==SummonPool.supplies?'item:':'equipment:';
   if(!reward.masterId.startsWith(prefix)||reward.masterId.length<=prefix.length)throw const FormatException('Invalid reward master');
   if(pool==SummonPool.supplies){if(id!=null)throw const FormatException('Unexpected instance ID');}
   else {
    final serial=id!=null&&id.startsWith('eq_')?int.tryParse(id.substring(3)):null;
    if(id==null||serial==null||serial<=0||id!='eq_$serial'||!ids.add(id))throw const FormatException('Invalid reward instance');
   }
  }
  return SummonReceipt(sequence:sequence,pool:pool,rewards:rewards);
 }
}

class SummonPlan {
 SummonPlan({required this.sequence,required this.pool,required List<SummonReward> rewards,required Map<EquipmentRarity,int> misses}):rewards=List.unmodifiable(rewards),misses=Map.unmodifiable(misses);
 final int sequence;
 final SummonPool pool;
 final List<SummonReward> rewards;
 final Map<EquipmentRarity,int> misses;
 Map<String,dynamic> toJson()=>{'sequence':sequence,'pool':pool.name,'rewards':rewards.map((e)=>e.toJson()).toList(),'misses':{for(final e in misses.entries)e.key.name:e.value}};
 factory SummonPlan.fromJson(Map<String,dynamic> j){
  final sequence=j['sequence'] as int;
  final pool=SummonPool.values.byName(j['pool'] as String);
  final rewards=(j['rewards'] as List).map((e)=>SummonReward.fromJson(e as Map<String,dynamic>)).toList();
  if(sequence<1||(rewards.length!=1&&rewards.length!=10))throw const FormatException('Invalid pending summon');
  final prefix=pool==SummonPool.supplies?'item:':'equipment:';
  if(rewards.any((r)=>r.instanceId!=null||!r.masterId.startsWith(prefix)||r.masterId.length<=prefix.length))throw const FormatException('Invalid pending reward');
  final misses=<EquipmentRarity,int>{};
  for(final e in (j['misses'] as Map<String,dynamic>).entries){
   final rarity=EquipmentRarity.values.byName(e.key);
   final limit=SummonPolicy.pityLimits[rarity];
   final value=e.value as int;
   if(limit==null||value<0||value>=limit)throw const FormatException('Invalid pending pity');
   misses[rarity]=value;
  }
  if(misses.length!=SummonPolicy.pityLimits.length)throw const FormatException('Incomplete pending pity');
  return SummonPlan(sequence:sequence,pool:pool,rewards:rewards,misses:misses);
 }
}

class SummonState {
 SummonState();
 int _sequence=0;
 SummonReceipt? _latest;
 SummonPlan? _pending;
 SummonPlan? get pending=>_pending;
 final Map<SummonPool,Map<EquipmentRarity,int>> _misses={};
 int get sequence=>_sequence;
 SummonReceipt? get latest=>_latest;
 Map<EquipmentRarity,int> misses(SummonPool pool)=>Map.unmodifiable(_misses[pool]??{});
 Map<String,dynamic> toJson()=>{'version':1,'sequence':_sequence,'latest':_latest?.toJson(),'pending':_pending?.toJson(),'misses':{for(final entry in _misses.entries)entry.key.name:{for(final m in entry.value.entries)m.key.name:m.value}}};
 factory SummonState.fromJson(Map<String,dynamic> j){
  if(j['version']!=1)throw const FormatException('Unsupported summon version');
  final state=SummonState();
  state._sequence=j['sequence'] as int;
  state._latest=j['latest']==null?null:SummonReceipt.fromJson(j['latest'] as Map<String,dynamic>);
  if(state._sequence<0||(state._latest?.sequence??0)!=state._sequence)throw const FormatException('Invalid summon sequence');
  for(final entry in (j['misses'] as Map<String,dynamic>).entries){
   final pool=SummonPool.values.byName(entry.key);
   final counters=<EquipmentRarity,int>{};
   for(final counter in (entry.value as Map<String,dynamic>).entries){
    final rarity=EquipmentRarity.values.byName(counter.key);
    final limit=SummonPolicy.pityLimits[rarity];
    final value=counter.value as int;
    if(limit==null||value<0||value>=limit)throw const FormatException('Invalid pity counter');
    counters[rarity]=value;
   }
   state._misses[pool]=counters;
  }
  state._pending=j['pending']==null?null:SummonPlan.fromJson(j['pending'] as Map<String,dynamic>);
  if(state._pending!=null&&state._pending!.sequence!=state._sequence+1)throw const FormatException('Invalid pending sequence');
  return state;
 }
}

class SummonEntry {
 const SummonEntry({required this.pool,required this.masterId,required this.rarity});
 final SummonPool pool;
 final String masterId;
 final EquipmentRarity rarity;
}

class SummonCatalog {
 SummonCatalog(Iterable<SummonEntry> entries){
  final ids=<String>{};
  for(final entry in entries){
   final prefix=entry.pool==SummonPool.supplies?'item:':'equipment:';
   if(!entry.masterId.startsWith(prefix)||entry.masterId.length<=prefix.length||!ids.add('${entry.pool.name}:${entry.masterId}'))throw const FormatException('Invalid summon master');
   (_entries[entry.pool]??={}).putIfAbsent(entry.rarity,()=>[]).add(entry);
  }
 }
 final Map<SummonPool,Map<EquipmentRarity,List<SummonEntry>>> _entries={};
 static final production=SummonCatalog(const []);
 List<SummonEntry> entries(SummonPool pool,EquipmentRarity rarity)=>List.unmodifiable(_entries[pool]?[rarity]??[]);
}

class SummonRate {
 const SummonRate({required this.entry,required this.weight,required this.candidateCount});
 final SummonEntry entry;
 final int weight,candidateCount;
 double get percent=>weight/100/candidateCount;
}

class SummonEngine {
 SummonEngine({required this.catalog,required this.equipmentCatalog,Random? random}):_random=random??Random();
 final SummonCatalog catalog;
 final EquipmentCatalog equipmentCatalog;
 final Random _random;
 static const _policy=SummonPolicy();
 EquipmentRarity highestUnlocked(WorldState world)=>world.cleared.contains('p12_main')?EquipmentRarity.ssr:world.cleared.contains('p01_main')?EquipmentRarity.sr:EquipmentRarity.r;

 /// 通常抽選のみ。天井・10連保証による確率変化は含めない。
 List<SummonRate> rates(WorldState world,SummonPool pool){
  final highest=highestUnlocked(world);
  final weights=_policy.effectiveWeights(highest);
  final result=<SummonRate>[];
  for(final rarity in EquipmentRarity.values.take(highest.index+1)){
   final candidates=catalog.entries(pool,rarity);
   // 不完全なプールの数値を有効な排出率として公開しない。
   if(candidates.isEmpty)return const [];
   for(final entry in candidates){
    if(!_validEntry(pool,entry))return const [];
    result.add(SummonRate(entry:entry,weight:weights[rarity.index],candidateCount:candidates.length));
   }
  }
  return List.unmodifiable(result);
 }
 bool _validEntry(SummonPool pool,SummonEntry entry){
  if(pool==SummonPool.supplies)return true;
  final definition=equipmentCatalog.find(entry.masterId);
  return definition!=null&&definition.rarity==entry.rarity&&(definition.slot==EquipmentSlot.relic)==(pool==SummonPool.relic);
 }
 /// 保留計画は現在の抽選プール全体で再抽選せず、記録済み候補だけを照合する。
 /// 戦闘・券残高は実際の再開時に別途検証する。
 void validatePending(WorldState world,SummonState state){
  final pending=state.pending;
  if(pending==null)return;
  final highest=highestUnlocked(world);
  for(final reward in pending.rewards){
   if(reward.rarity.index>highest.index||!catalog.entries(pending.pool,reward.rarity).any((entry)=>entry.masterId==reward.masterId&&_validEntry(pending.pool,entry))){
    throw StateError('Pending summon master mismatch');
   }
  }
 }

 void validateRequest({required WorldState world,required SummonState state,required SummonPool pool,required int count,required int expectedSequence}){
  if(count!=1&&count!=10)throw ArgumentError('Invalid summon count');
  if(world.battle!=null)throw StateError('Summon unavailable in battle');
  if(expectedSequence!=state.sequence)throw StateError('Stale summon request');
  final sequence=state.sequence+1;
  if(sequence<=state.sequence)throw StateError('Summon sequence overflow');
  final cost=SummonPolicy.costs[pool]!*count;
  final supplies=pool==SummonPool.supplies;
  if((supplies?world.supplyTickets:world.summonTickets)<cost)throw StateError('Insufficient tickets');
  final pending=state.pending;
  if(pending!=null){
   if(pending.pool!=pool||pending.rewards.length!=count||pending.sequence!=sequence)throw StateError('Pending summon request mismatch');
   validatePending(world,state);
   return;
  }
  final highest=highestUnlocked(world);
  // 新規抽選だけは解放済みの全希少度・全候補を事前検証する。
  for(final rarity in EquipmentRarity.values.take(highest.index+1)){
   final entries=catalog.entries(pool,rarity);
   if(entries.isEmpty)throw StateError('Summon pool incomplete');
   if(entries.any((entry)=>!_validEntry(pool,entry)))throw StateError('Summon equipment master mismatch');
  }
 }
 SummonPlan prepare({required WorldState world,required SummonState state,required SummonPool pool,required int count,required int expectedSequence}){
  validateRequest(world:world,state:state,pool:pool,count:count,expectedSequence:expectedSequence);
  if(state.pending!=null)return state.pending!;
  final highest=highestUnlocked(world);
  var counters=state.misses(pool);
  final rewards=<SummonReward>[];
  for(var i=0;i<count;i++){
   final guarantee=count==10&&i==9&&!rewards.any((r)=>r.rarity.index>=EquipmentRarity.sr.index);
   final result=_policy.draw(highestUnlocked:highest,roll:_random.nextInt(10000),misses:counters,guaranteeSr:guarantee);
   final entries=catalog.entries(pool,result.rarity);
   final entry=entries[_random.nextInt(entries.length)];
   rewards.add(SummonReward(masterId:entry.masterId,rarity:result.rarity));
   counters=result.misses;
  }
  final plan=SummonPlan(sequence:state.sequence+1,pool:pool,rewards:rewards,misses:counters);
  state._pending=plan;
  return plan;
 }
 SummonReceipt commit({required WorldState world,required AbyssInventory inventory,required SummonState state}){
  final plan=state.pending;
  if(plan==null)throw StateError('Missing pending summon');
  final pool=plan.pool;
  final sequence=plan.sequence;
  validateRequest(world:world,state:state,pool:pool,count:plan.rewards.length,expectedSequence:sequence-1);
  final supplies=pool==SummonPool.supplies;
  final cost=SummonPolicy.costs[pool]!*plan.rewards.length;
  final rewards=<SummonReward>[];
  for(final reward in plan.rewards){
   String? instanceId;
   if(supplies){inventory.addStack(reward.masterId,1);}
   else{
    final definition=equipmentCatalog.find(reward.masterId)!;
    instanceId=inventory.addEquipment(definition.id,definition.slot,definition.rarity).id;
   }
   rewards.add(SummonReward(masterId:reward.masterId,rarity:reward.rarity,instanceId:instanceId));
  }
  if(supplies){world.supplyTickets-=cost;}else{world.summonTickets-=cost;}
  final receipt=SummonReceipt(sequence:sequence,pool:pool,rewards:rewards);
  state._sequence=sequence;
  state._misses[pool]=Map.of(plan.misses);
  state._pending=null;
  state._latest=receipt;
  return receipt;
 }
}
