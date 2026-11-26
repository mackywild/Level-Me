import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/achievement.dart';
import '../models/achievement_catalog.dart';
import '../models/app_state.dart';
import '../models/quest.dart';
import '../models/stat_type.dart';
import '../services/reward_arithmetic.dart';
import '../services/level_calculator.dart';
import '../services/local_store.dart';
import '../services/portable_backup.dart';
import '../world/world_engine.dart';
import '../world/abyss_inventory.dart';
import '../world/abyss_equipment.dart';
import '../world/abyss_enhancement.dart';
import '../world/abyss_equipment_skill_master.dart';
import '../world/abyss_ex_equipment_transaction.dart';
import '../world/abyss_equipment_effects.dart';
import '../world/abyss_equipment_skill_policy.dart';
import '../world/abyss_equipment_enhancement_draw.dart';
import '../world/abyss_dismantle.dart';
import '../world/abyss_shop.dart';
import '../world/abyss_consumable.dart';
import '../world/abyss_buff.dart';
import '../world/abyss_purification.dart';
import '../world/abyss_master.dart';
import '../world/abyss_compendium.dart';
import '../world/abyss_skill.dart';
import '../world/abyss_summon.dart';
import '../world/abyss_summon_transaction.dart';
class AppController extends ChangeNotifier {
 AppController(this._store,{PortableBackup? portableBackup,EquipmentCatalog? equipmentCatalog,SummonCatalog? summonCatalog,Random? summonRandom,Random? legacyRewardRandom,Future<AbyssMaster> Function()? loadAbyssMaster,EnhancementPolicy? enhancementPolicy,EquipmentSkillMaster? equipmentSkillMaster,ExEquipmentTransactionPolicy? exEquipmentPolicy,Random? equipmentSkillSeedRandom,DismantlePolicy? dismantlePolicy,ShopCatalog? shopCatalog,ConsumableCatalog? consumableCatalog,BuffCatalog? buffCatalog,PurificationCatalog? purificationCatalog,SkillCatalog? skillCatalog,int Function()? clockMs,this.enhancementScaling=const EnhancementScaling.disabled()}):_exEquipmentPolicy=exEquipmentPolicy,_equipmentSkillMaster=equipmentSkillMaster??exEquipmentPolicy?.master.randomMaster,_equipmentSkillSeedRandom=equipmentSkillSeedRandom??Random.secure(),_skillCatalog=skillCatalog??SkillCatalog.production,_purificationCatalog=purificationCatalog??PurificationCatalog.production,_buffCatalog=buffCatalog??BuffCatalog.production,_clockMs=clockMs??_systemClockMs,_consumableCatalog=consumableCatalog??ConsumableCatalog.production,_shopCatalog=shopCatalog??ShopCatalog.production,_dismantlePolicy=dismantlePolicy??DismantlePolicy.production,_enhancementPolicy=enhancementPolicy??EnhancementPolicy.production,_loadAbyssMaster=loadAbyssMaster,_summonRandom=summonRandom,_legacyRewardRandom=legacyRewardRandom,_portableBackup=portableBackup,_equipmentCatalog=equipmentCatalog??EquipmentCatalog.production {
  if(exEquipmentPolicy!=null&&(!identical(_equipmentSkillMaster,exEquipmentPolicy.master.randomMaster)||loadAbyssMaster!=null))throw ArgumentError('EX test policy master mismatch');
  _summonEngine=SummonEngine(catalog:summonCatalog??SummonCatalog.production,equipmentCatalog:this.equipmentCatalog,random:summonRandom);
  _store.validatePlayer=_validateEquipment;
  _portableBackup?.validatePlayer=_validateEquipment;
 }
 void _validateEquipment(AppStateData state){
  equipmentCatalog.validateLoadout(state.inventory);
  if(state.inventory.equipmentSkillSeed!=null&&_equipmentSkillMaster==null)throw StateError('Equipment skill master unavailable');
  _validateEquipmentSkillInventory(state.inventory);
  final battle=state.world.battle;
  if((battle?.executionVersion??0)>=4){
   final expected=_battleEquipmentEffects(state);
   if(expected==null||!battle!.equipmentEffects!.sameAs(expected))throw const FormatException('Battle equipment snapshot mismatch');
  }
  _summonEngine.validatePending(state.world,state.summon);
  _buffCatalog.validateSavedEffects(state.world);
  _purificationCatalog.validateSavedStatuses(state.world);
  _skillCatalog.validateBattle(state.world,state.skills);
  _worldStatsFor(state);
 }
 EquipmentCatalog _equipmentCatalog;
 EquipmentCatalog get equipmentCatalog=>_equipmentCatalog;
 late SummonEngine _summonEngine;
 final Future<AbyssMaster> Function()? _loadAbyssMaster;
 final Random? _summonRandom;
 final Random? _legacyRewardRandom;
 Future<void>? _masterLoading;
 AbyssMaster? _abyssMaster;
 Future<void> _ensureAbyssMaster() async {
  final loader=_loadAbyssMaster;
  if(loader==null||hasAbyssMaster)return;
  final loading=_masterLoading??=() async {configureAbyssMaster(await loader());}();
  try {await loading;} finally {if(identical(_masterLoading,loading))_masterLoading=null;}
 }
 bool get hasAbyssMaster=>_abyssMaster!=null;
 CompendiumView get compendiumView=>(_abyssMaster?.compendium??CompendiumCatalog.production).view(_state.inventory);
 void configureAbyssMaster(AbyssMaster master){
  if(_exEquipmentPolicy!=null)throw StateError('EX test policy cannot configure production master');
  if(_ready||_summonBusy||_abyssMaster!=null)throw StateError('Cannot replace master while active');
  _enhancementPolicy.validateMaterials((recipe){
   final material=master.supply(recipe.materialId);
   return material!=null&&material.category=='material'&&material.rarity==recipe.rarity;
  });
  _dismantlePolicy.validateMaterials((recipe){
   final material=master.supply(recipe.materialId);
   return material!=null&&material.category=='material'&&material.rarity==recipe.rarity;
  });
  _shopCatalog.validateMaterials((offer)=>master.supply(offer.materialId)?.category=='material');
  _shopCatalog.validateEquipment(master.equipment);
  // 現行の素材マスターに回復品を混入させない。正式統合は別PR。
  if(_consumableCatalog.items.isNotEmpty)throw const FormatException('Recovery master not enabled');
  if(_buffCatalog.items.isNotEmpty)throw const FormatException('Buff master not enabled');
  if(_purificationCatalog.items.isNotEmpty)throw const FormatException('Purification master not enabled');
  if(_skillCatalog.definitions.isNotEmpty)throw const FormatException('Skill master not enabled');
  _skillCatalog=master.skills;
  _purificationCatalog=master.purification;
  _consumableCatalog=master.recovery;
  _buffCatalog=master.buffs;
  _abyssMaster=master;
  _equipmentCatalog=master.equipment;
  _summonEngine=SummonEngine(catalog:master.summon,equipmentCatalog:master.equipment,random:_summonRandom);
 }
 String summonRewardName(String id)=>equipmentCatalog.find(id)?.name??_abyssMaster?.supply(id)?.name??_consumableCatalog.find(id)?.name??id;
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
 ConsumableCatalog _consumableCatalog;
 List<RecoveryItem> get recoveryItems=>_consumableCatalog.items;
 RecoveryItem? recoveryItem(String id)=>_consumableCatalog.find(id);
 ({int? amount,String? reason}) evaluateRecovery(String id){
  if(!_ready)return (amount:null,reason:'初期化中');
  if(_inventoryBusy)return (amount:null,reason:'所持品処理中');
  try{
   final working=WorldState.fromJson(jsonDecode(jsonEncode(_state.world.toJson())) as Map<String,dynamic>);
   final stats=worldStats;
   worldEngine.refresh(working,stats,_nowMs,naturalRecovery:_naturalRecoveryFor(_state));
   final amount=_consumableCatalog.preview(world:working,stats:stats,inventory:_state.inventory,id:id,expectedSequence:working.itemUseSequence);
   return (amount:amount,reason:null);
  }on StateError catch(error){
   return (amount:null,reason:switch(error.message){
    'Recovery not needed'=>'回復不要',
    'Consumable unavailable in battle'=>'戦闘中は使用できません',
    'Insufficient items'=>'所持数不足',
    _=>'使用できません',
   });
  }
 }
 Future<int> useWorldRecoveryItem(String id,int expectedSequence,{required int expectedGeneration})=>_inventoryTransaction(() async {
  if(!_ready)throw StateError('Player not ready');
  if(expectedGeneration!=_restoreGeneration)throw StateError('Stale save generation');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  // 自然回復を先に反映し、満タンなら消費しない。失敗時は作業用状態を破棄。
  final stats=worldStats;
  worldEngine.refresh(working.world,stats,_nowMs,naturalRecovery:_naturalRecoveryFor(working));
  final amount=_consumableCatalog.use(world:working.world,stats:stats,inventory:working.inventory,id:id,expectedSequence:expectedSequence);
  await _store.save(working);
  _state=working;
  return amount;
 });
 ({int? amount,String? reason}) evaluateBattleRecovery(String id){
  if(!_ready||_inventoryBusy)return (amount:null,reason:'所持品処理中');
  final w=_state.world,b=w.battle;
  if(b==null)return (amount:null,reason:'戦闘中ではありません');
  try{
   final amount=_consumableCatalog.previewInBattle(world:w,inventory:_state.inventory,id:id,expectedSequence:w.itemUseSequence,battleId:b.id,expectedTurn:b.turn);
   return (amount:amount,reason:null);
  }on StateError catch(error){
   return (amount:null,reason:switch(error.message){
    'Recovery not needed'=>'回復不要',
    'Insufficient items'=>'所持数不足',
    _=>'使用できません',
   });
  }
 }
 Future<int> useBattleRecoveryItem(String id,int battleId,int turn,int expectedSequence,{required int expectedGeneration})=>_inventoryTransaction(() async {
  if(!_ready)throw StateError('Player not ready');
  if(expectedGeneration!=_restoreGeneration)throw StateError('Stale save generation');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final now=_nowMs;
  final amount=_consumableCatalog.useInBattle(world:working.world,inventory:working.inventory,id:id,expectedSequence:expectedSequence,battleId:battleId,expectedTurn:turn,engine:worldEngine,now:now);
  worldEngine.refresh(working.world,worldStats,now,naturalRecovery:_naturalRecoveryFor(working));
  await _store.save(working);
  _state=working;
  return amount;
 });
 BuffCatalog _buffCatalog;
 List<BuffItem> get buffItems=>_buffCatalog.items;
 String? battleBuffUnavailable(String id){
  if(!_ready||_inventoryBusy)return '所持品処理中';
  final w=_state.world,b=w.battle;
  if(b==null)return '戦闘中ではありません';
  try{
   _buffCatalog.validate(world:w,inventory:_state.inventory,id:id,expectedSequence:w.itemUseSequence,battleId:b.id,turn:b.turn,engine:worldEngine);
   return null;
  }on StateError catch(error){
   return switch(error.message){
    'Buff already active'=>'効果発動中',
    'Enemy has no regeneration'=>'敵に再生能力がありません',
    'Insufficient items'=>'所持数不足',
    _=>'使用できません',
   };
  }
 }
 Future<void> useBattleBuffItem(String id,int battleId,int turn,int expectedSequence,{required int expectedGeneration})=>_inventoryTransaction(() async {
  if(!_ready)throw StateError('Player not ready');
  if(expectedGeneration!=_restoreGeneration)throw StateError('Stale save generation');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final now=_nowMs;
  _buffCatalog.use(world:working.world,inventory:working.inventory,id:id,expectedSequence:expectedSequence,battleId:battleId,turn:turn,engine:worldEngine,now:now);
  worldEngine.refresh(working.world,worldStats,now,naturalRecovery:_naturalRecoveryFor(working));
  await _store.save(working);
  _state=working;
 });
 PurificationCatalog _purificationCatalog;
 List<PurificationItem> get purificationItems=>_purificationCatalog.items;
 String? battlePurificationUnavailable(String id){
  if(!_ready||_inventoryBusy)return '所持品処理中';
  final w=_state.world,b=w.battle;
  if(b==null)return '戦闘中ではありません';
  try{
   _purificationCatalog.preview(world:w,inventory:_state.inventory,id:id,expectedSequence:w.itemUseSequence,battleId:b.id,turn:b.turn,engine:worldEngine);
   return null;
  }on StateError catch(error){
   return switch(error.message){
    'No removable status'=>'浄化対象なし',
    'Insufficient items'=>'所持数不足',
    _=>'使用できません',
   };
  }
 }
 Future<int> useBattlePurificationItem(String id,int battleId,int turn,int expectedSequence,{required int expectedGeneration})=>_inventoryTransaction(() async {
  if(!_ready)throw StateError('Player not ready');
  if(expectedGeneration!=_restoreGeneration)throw StateError('Stale save generation');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final now=_nowMs;
  final count=_purificationCatalog.use(world:working.world,inventory:working.inventory,id:id,expectedSequence:expectedSequence,battleId:battleId,turn:turn,engine:worldEngine,now:now);
  worldEngine.refresh(working.world,worldStats,now,naturalRecovery:_naturalRecoveryFor(working));
  await _store.save(working);
  _state=working;
  return count;
 });
 SkillCatalog _skillCatalog;
 List<SkillDefinition> get skillDefinitions=>_skillCatalog.definitions;
 Future<void> _changeSkill(String id,int expectedGeneration,int expectedRevision,void Function(AppStateData,String) change)=>_inventoryTransaction(() async {
  if(!_ready)throw StateError('Player not ready');
  if(expectedGeneration!=_restoreGeneration)throw StateError('Stale save generation');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  if(working.skills.revision!=expectedRevision)throw StateError('Stale skill revision');
  change(working,id);
  _skillCatalog.validateProgress(working.world,working.skills);
  // 保存前に変更後の補正値も検証し、計算不能な構成を確定しない。
  _worldStatsFor(working);
  await _store.save(working);
  _state=working;
 });
 String? skillLearnUnavailable(String id){
  if(!_ready)return '初期化中';
  if(_inventoryBusy)return '処理中';
  return _skillCatalog.learnUnavailable(_state.world,_state.skills,id,playerLevel:LevelCalculator.fromTotalExp(_state.totalExp).level);
 }
 Future<void> learnWorldSkill(String id,{required int expectedGeneration,required int expectedRevision})=>_changeSkill(id,expectedGeneration,expectedRevision,(state,id)=>_skillCatalog.learn(state.world,state.skills,id,playerLevel:LevelCalculator.fromTotalExp(state.totalExp).level));
 Future<void> equipWorldSkill(String id,{required int expectedGeneration,required int expectedRevision})=>_changeSkill(id,expectedGeneration,expectedRevision,(state,id)=>_skillCatalog.equip(state.world,state.skills,id));
 Future<void> unequipWorldSkill(String id,{required int expectedGeneration,required int expectedRevision})=>_changeSkill(id,expectedGeneration,expectedRevision,(state,id)=>_skillCatalog.unequip(state.world,state.skills,id));
 final ShopCatalog _shopCatalog;
 List<ShopOffer> get shopOffers=>_shopCatalog.offers;
 int _restoreGeneration=0;
 int get restoreGeneration=>_restoreGeneration;
 String? shopUnavailable(String id,int sequence){
  if(!_ready)return '初期化中';
  if(_inventoryBusy)return '所持品処理中';
  try {
   _shopCatalog.validate(world:_state.world,inventory:_state.inventory,offerId:id,expectedSequence:sequence,equipmentCatalog:equipmentCatalog);
   return null;
  } on StateError catch(error){
   return switch(error.message){
    'Shop unavailable in battle'=>'戦闘中は購入できません',
    'Insufficient shop currency'=>'通貨残高不足',
    'Shop equipment unavailable'=>'交換装備未承認',
    'Stack overflow'=>'素材所持数の上限です',
    _=>'購入できません',
   };
  }
 }
 Future<ShopOffer> purchaseWorldMaterial(String offerId,int expectedSequence,{int? expectedGeneration})=>
  purchaseWorldOffer(offerId,expectedSequence,expectedGeneration:expectedGeneration);
 Future<ShopOffer> purchaseWorldOffer(String offerId,int expectedSequence,{int? expectedGeneration})=>_inventoryTransaction(() async {
  if(expectedGeneration!=null&&expectedGeneration!=_restoreGeneration)throw StateError('Stale save generation');
  if(!_ready)throw StateError('Player not ready');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final result=_shopCatalog.purchase(world:working.world,inventory:working.inventory,offerId:offerId,expectedSequence:expectedSequence,equipmentCatalog:equipmentCatalog);
  await _store.save(working);
  _state=working;
  return result;
 });
 final DismantlePolicy _dismantlePolicy;
 bool _inventoryBusy=false;
 bool get inventoryBusy=>_inventoryBusy;
 DismantleRecipe? dismantleRecipe(EquipmentRarity rarity)=>_dismantlePolicy.recipe(rarity);
 DismantleRecipe? dismantlePreview(EquipmentInstance item){
  try{return _dismantlePolicy.validate(world:_state.world,inventory:_state.inventory,catalog:equipmentCatalog,id:item.id,expectedLevel:item.enhancement);}on StateError{return null;}
 }
 String? dismantleUnavailable(String id,int expectedLevel){
  if(!_ready)return '初期化中';
  if(_inventoryBusy)return '所持品処理中';
  try {
   _dismantlePolicy.validate(world:_state.world,inventory:_state.inventory,catalog:equipmentCatalog,id:id,expectedLevel:expectedLevel);
   return null;
  } on StateError catch(error){
   return switch(error.message){
    'Dismantle unavailable in battle'=>'戦闘中は分解できません',
    'Equipment protected'=>'装着中・お気に入りの装備は分解できません',
    'Enhanced equipment protected'=>'強化済み装備は分解できません（素材履歴なし）',
    'Dismantle recipe unavailable'=>'分解報酬未承認',
    'Stack overflow'=>'素材所持数の上限です',
    'Crystal overflow'=>'魔晶石所持数の上限です',
    _=>'分解できません',
   };
  }
 }
 Future<T> _inventoryTransaction<T>(Future<T> Function() action) async {
  if(_inventoryBusy)throw StateError('Inventory operation in progress');
  _inventoryBusy=true;
  notifyListeners();
  try {
   return await _transaction(action,keepPublishedState:true);
  }finally{
   _inventoryBusy=false;
   notifyListeners();
  }
 }
 Future<void> setWorldEquipmentFavorite(String id,bool favorite)=>_inventoryTransaction(() async {
  if(!_ready||_state.world.battle!=null)throw StateError('Equipment protection unavailable');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  working.inventory.setFavorite(id,favorite);
  await _store.save(working);
  _state=working;
 });
 Future<DismantleRecipe> dismantleWorldItem(String id,int expectedLevel,{int? expectedGeneration,EquipmentInstance? expectedItem})=>_inventoryTransaction(() async {
  if(expectedGeneration!=null&&expectedGeneration!=_restoreGeneration)throw StateError('Stale save generation');
  final current=_state.inventory.equipment[id];
  if(expectedItem!=null&&(current==null||current.id!=expectedItem.id||current.masterId!=expectedItem.masterId||current.slot!=expectedItem.slot||current.rarity!=expectedItem.rarity||current.enhancement!=expectedItem.enhancement))throw StateError('Stale equipment confirmation');
  if(!_ready)throw StateError('Player not ready');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final reward=_dismantlePolicy.dismantle(world:working.world,inventory:working.inventory,catalog:equipmentCatalog,id:id,expectedLevel:expectedLevel);
  await _store.save(working);
  _state=working;
  return reward;
 });
 final EnhancementPolicy _enhancementPolicy;
 final EquipmentSkillMaster? _equipmentSkillMaster;
 final ExEquipmentTransactionPolicy? _exEquipmentPolicy;
 void _validateEquipmentSkillInventory(AbyssInventory inventory){
  final ex=_exEquipmentPolicy;
  if(ex==null){_equipmentSkillMaster?.validateInventory(inventory);}else{ex.validateInventory(inventory,equipmentCatalog);}
 }
 EquipmentSkillMaster? get equipmentSkillMaster=>_equipmentSkillMaster;
 final Random _equipmentSkillSeedRandom;
 void _validateEnhancementSkills(AbyssInventory inventory,String id){
  final master=_equipmentSkillMaster;
  if(master==null)return;
  final item=inventory.equipment[id]!;
  if(item.rarity==EquipmentRarity.ex||(inventory.equipmentSkillSeed==null&&inventory.equipment.values.any((e)=>e.rarity==EquipmentRarity.ex)))throw StateError('EX skill history layout not connected');
  final milestone=EquipmentSkillPolicy.nextGrant(item.rarity,item.enhancement,item.enhancement+1);
  if(milestone!=null&&!master.hasCandidates(item.slot))throw StateError('Equipment skill pool unavailable');
  _validateEquipmentSkillInventory(inventory);
 }
 final EnhancementScaling enhancementScaling;
 EnhancementRecipe? enhancementRecipe(EquipmentRarity rarity)=>_enhancementPolicy.recipe(rarity);
 EnhancementRecipe? enhancementRecipeFor(EquipmentRarity rarity,int currentLevel)=>currentLevel==20?null:_enhancementPolicy.recipeFor(rarity,currentLevel);
 String? enhancementUnavailable(String id,int expectedLevel){
  if(!_ready)return '初期化中';
  try {
   final ex=_exEquipmentPolicy;
   if(_state.inventory.equipment[id]?.rarity==EquipmentRarity.ex&&ex!=null){
    ex.validateEnhancement(_state.world,_state.inventory,equipmentCatalog,id,expectedLevel);
    return null;
   }
   _enhancementPolicy.validate(world:_state.world,inventory:_state.inventory,catalog:equipmentCatalog,id:id,expectedLevel:expectedLevel);
   _validateEnhancementSkills(_state.inventory,id);
   return null;
  } on StateError catch(error){
   return switch(error.message){
    'Enhancement unavailable in battle'=>'戦闘中は強化できません',
    'Enhancement limit reached'=>'最大強化済み',
    'Enhancement recipe unavailable'=>'強化レシピ未承認',
    'Enhancement history missing'=>'素材消費履歴がないため強化できません',
    'Equipment skill pool unavailable'=>'装備スキル候補未承認',
    'EX skill history layout not connected'=>'EX装備スキル未対応',
    'Insufficient gold'=>'G不足',
    'Insufficient materials'=>'素材不足',
    _=>'強化できません',
   };
  }
 }
 /// Explicit test-injected acquisition; shares the ordinary shop sequence.
 Future<EquipmentInstance> acquireExWorldItem(String offerId,int expectedSequence,{required int expectedGeneration})=>_transaction(() async {
  if(!_ready||expectedGeneration!=_restoreGeneration)throw StateError('Stale EX acquisition request');
  final ex=_exEquipmentPolicy;
  if(ex==null)throw StateError('EX acquisition unavailable');
  ex.validateAcquisition(_state.world,equipmentCatalog,offerId,expectedSequence);
  _validateEquipmentSkillInventory(_state.inventory);
  if(_state.inventory.equipmentSkillSeed==null){
   final prepared=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
   prepared.inventory.activateEquipmentSkills(_equipmentSkillSeedRandom.nextInt(0x80000000));
   await _store.save(prepared);
   _state=prepared;
  }
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final item=ex.acquire(working.world,working.inventory,equipmentCatalog,offerId,expectedSequence);
  _validateEquipment(working);
  await _store.save(working);
  _state=working;
  notifyListeners();
  return item;
 },keepPublishedState:true);
 Future<EquipmentInstance> enhanceWorldItem(String id,int expectedLevel,{int? expectedGeneration})=>_transaction(() async {
  if(!_ready)throw StateError('Player not ready');
  if(expectedGeneration!=null&&expectedGeneration!=_restoreGeneration)throw StateError('Stale save generation');
  final ex=_exEquipmentPolicy;
  if(_state.inventory.equipment[id]?.rarity==EquipmentRarity.ex&&ex!=null){
   if(expectedGeneration!=_restoreGeneration)throw StateError('Stale save generation');
   final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
   final result=ex.enhance(working.world,working.inventory,equipmentCatalog,id,expectedLevel);
   _validateEquipment(working);
   await _store.save(working);
   _state=working;
   notifyListeners();
   return result;
  }
  final master=_equipmentSkillMaster;
  if(master!=null){
   _enhancementPolicy.validate(world:_state.world,inventory:_state.inventory,catalog:equipmentCatalog,id:id,expectedLevel:expectedLevel);
   _validateEnhancementSkills(_state.inventory,id);
   if(_state.inventory.equipmentSkillSeed==null){
    final prepared=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
    prepared.inventory.activateEquipmentSkills(_equipmentSkillSeedRandom.nextInt(0x80000000));
    await _store.save(prepared);
    _state=prepared;
   }
  }
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final previousStats=_worldStatsFor(working);
  final previousRecovery=_naturalRecoveryFor(working);
  final grant=master==null?null:EquipmentEnhancementDraw.prepare(working.inventory,working.inventory.equipment[id]!,master);
  final result=_enhancementPolicy.enhance(world:working.world,inventory:working.inventory,catalog:equipmentCatalog,id:id,expectedLevel:expectedLevel,skillGrant:grant);
  _settleEquipmentRecoveryChange(working,previousStats,previousRecovery);
  await _store.save(working);
  _state=working;
  notifyListeners();
  return result;
 },keepPublishedState:true);
 final PortableBackup? _portableBackup;
 final LocalStore _store;
 final WorldEngine worldEngine=WorldEngine();
 BattleEquipmentEffects? _battleEquipmentEffects(AppStateData state){
  final master=_equipmentSkillMaster;
  if(master==null||state.inventory.equipmentSkillSeed==null)return null;
  final snapshot=_equipmentEffectSnapshot(state)!;
  int v(EquipmentEffect effect)=>snapshot.value(effect);
  if(snapshot.totals.entries.any((e)=>e.value>0&&!battleConnectedEquipmentEffects.contains(e.key)))throw StateError('Equipment battle effect not connected');
  return BattleEquipmentEffects(physical:v(EquipmentEffect.physicalPercent),magic:v(EquipmentEffect.magicPercent),defense:v(EquipmentEffect.defensePercent),critical:v(EquipmentEffect.criticalChance),evasion:v(EquipmentEffect.evasionChance),reduction:v(EquipmentEffect.damageReduction),discount:v(EquipmentEffect.energyDiscount),penetration:v(EquipmentEffect.penetration),extraAttack:v(EquipmentEffect.extraAttackChance),hp:v(EquipmentEffect.hpPercent),cooldown:v(EquipmentEffect.cooldownReduction),resistance:v(EquipmentEffect.resistance),naturalRecovery:v(EquipmentEffect.naturalRecovery),reward:v(EquipmentEffect.rewardPercent));
 }
 EquipmentEffectSnapshot? _equipmentEffectSnapshot(AppStateData state){
  final master=_equipmentSkillMaster;
  if(master==null||state.inventory.equipmentSkillSeed==null)return null;
  return master.effectPolicy.snapshot(state.inventory,[
   for(final entry in state.inventory.equipmentSkillHistories.entries)
    if(state.inventory.equipment[entry.key]!.rarity!=EquipmentRarity.ex)
    for(final grant in entry.value.grants)
     EquipmentSkillGrant(instanceId:entry.key,milestone:grant.milestone,skillId:grant.skillId,level:grant.level),
  ]);
 }
 int _naturalRecoveryFor(AppStateData state)=>_equipmentEffectSnapshot(state)?.value(EquipmentEffect.naturalRecovery)??0;
 WorldStats get worldStats=>_worldStatsFor(_state);
 WorldStats _worldStatsFor(AppStateData state){
  final base=_baseWorldStatsFor(state);
  final hp=_equipmentEffectSnapshot(state)?.value(EquipmentEffect.hpPercent)??0;
  return BattleEquipmentEffects(hp:hp).apply(base);
 }
 /// 最大HP変更境界で旧能力値の経過分を精算する。HPの未満tickは
 /// 新旧の回復量を混在させないため破棄し、エネルギー端数は維持する。
 void _settleEquipmentRecoveryChange(AppStateData working,WorldStats previousStats,int previousRecovery){
  final maximum=_worldStatsFor(working).hp;
  final recoveryChanged=previousRecovery!=_naturalRecoveryFor(working);
  if(maximum!=previousStats.hp||recoveryChanged){
   final now=_nowMs;
   worldEngine.refresh(working.world,previousStats,now,naturalRecovery:previousRecovery);
   working.world.hpAt=now;
   if(recoveryChanged)working.world.energyAt=now;
  }
  if(working.world.hp>maximum)working.world.hp=maximum;
 }
 WorldStats _baseWorldStatsFor(AppStateData state)=>_skillCatalog.applyPassive(equipmentCatalog.apply(WorldStats.fromRanks(level:LevelCalculator.fromTotalExp(state.totalExp).level,fitness:LevelCalculator.statRankFromExp(state.stats[StatType.fitness]??0),intelligence:LevelCalculator.statRankFromExp(state.stats[StatType.intelligence]??0),discipline:LevelCalculator.statRankFromExp(state.stats[StatType.discipline]??0),creativity:LevelCalculator.statRankFromExp(state.stats[StatType.creativity]??0)),state.inventory,scaling:enhancementScaling),state.skills);
 final int Function() _clockMs;
 static int _systemClockMs()=>DateTime.now().millisecondsSinceEpoch;
 int get _nowMs=>_clockMs();
 Future<void> startWorldBattle(String id)=>_transaction(() async {
  if(!_ready)throw StateError('Player not ready');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  _skillCatalog.validateProgress(working.world,working.skills);
  worldEngine.start(working.world,_baseWorldStatsFor(working),id,_nowMs,activeSkills:_skillCatalog.snapshot(working.skills),lifeRewardBonuses:_skillCatalog.rewardSnapshot(working.skills),equipmentEffects:_battleEquipmentEffects(working));
  await _store.save(working);
  _state=working;
  notifyListeners();
 },keepPublishedState:true);
 Future<void> useBattleActiveSkill(String id,int battleId,int turn,{required int expectedGeneration})=>_inventoryTransaction(() async {
  if(!_ready)throw StateError('Player not ready');
  if(expectedGeneration!=_restoreGeneration)throw StateError('Stale save generation');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  _skillCatalog.validateBattle(working.world,working.skills);
  final now=_nowMs;
  _skillCatalog.executeActive(worldEngine,working.world,working.skills,id,battleId,turn,now);
  worldEngine.refresh(working.world,worldStats,now,naturalRecovery:_naturalRecoveryFor(working));
  await _store.save(working);
  _state=working;
 });
 Future<void> worldCommand(WorldCommand command,int battleId,int turn,{int? expectedGeneration})=>_transaction(() async {
  if(!_ready)throw StateError('Player not ready');
  if(expectedGeneration!=null&&expectedGeneration!=_restoreGeneration)throw StateError('Stale save generation');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final now=_nowMs;
  worldEngine.act(working.world,command,battleId,turn,now);
  worldEngine.refresh(working.world,worldStats,now,naturalRecovery:_naturalRecoveryFor(working));
  await _store.save(working);
  _state=working;
  notifyListeners();
 },keepPublishedState:true);
 Future<void> equipWorldItem(String id)=>_transaction(() async {
  if(!_ready||_state.world.battle!=null)throw StateError('Equipment change unavailable');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final item=working.inventory.equipment[id];
  if(item==null)throw StateError('Equipment not owned');
  equipmentCatalog.require(item);
  final previousStats=_worldStatsFor(working);
  final previousRecovery=_naturalRecoveryFor(working);
  working.inventory.equip(id);
  _settleEquipmentRecoveryChange(working,previousStats,previousRecovery);
  await _store.save(working);
  _state=working;
  notifyListeners();
 },keepPublishedState:true);
 Future<void> unequipWorldItem(EquipmentSlot slot)=>_transaction(() async {
  if(!_ready||_state.world.battle!=null)throw StateError('Equipment change unavailable');
  final working=AppStateData.fromJson(jsonDecode(jsonEncode(_state.toJson())) as Map<String,dynamic>);
  final previousStats=_worldStatsFor(working);
  final previousRecovery=_naturalRecoveryFor(working);
  working.inventory.unequip(slot);
  _settleEquipmentRecoveryChange(working,previousStats,previousRecovery);
  await _store.save(working);
  _state=working;
  notifyListeners();
 },keepPublishedState:true);
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
  worldEngine.refresh(_state.world,worldStats,_nowMs,naturalRecovery:_naturalRecoveryFor(_state));
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
   _restoreGeneration++;
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
   _restoreGeneration++;
   await _store.restoreBackup();
   await initialize();
  });
 }
 Future<void> addQuest({required String title,required List<QuestReward> rewards,QuestCadence cadence=QuestCadence.oneTime,List<String> reviewQuestionIds=const []}) => _transaction(() async {
  if(title.trim().isEmpty||rewards.isEmpty||rewards.any((r)=>r.exp<=0))throw ArgumentError('Invalid quest');
  rewards.fold<int>(0,(sum,r)=>RewardArithmetic.add(sum,r.exp));
  if(reviewQuestionIds.isEmpty&&title.trim().startsWith('基本情報：見直し'))throw ArgumentError('Reserved title');
  _state.quests.insert(0,Quest(id:DateTime.now().microsecondsSinceEpoch.toString(),title:title.trim(),rewards:List.of(rewards),createdAt:DateTime.now(),cadence:cadence,reviewQuestionIds:List.of(reviewQuestionIds)));
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
  final changed=worldEngine.refresh(_state.world,worldStats,_nowMs,naturalRecovery:_naturalRecoveryFor(_state));
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
  _state.completionCount=RewardArithmetic.add(_state.completionCount,1);
  final beforeLevel=LevelCalculator.fromTotalExp(_state.totalExp).level;
  final multiplier = activeSeconds == null ? 1 : (activeSeconds ~/ 60).clamp(1, 120);
  final rewards = activeSeconds == null ? current.rewards : current.rewards.map((r) => QuestReward(stat:r.stat, exp:RewardArithmetic.timedExp(r.exp,multiplier))).toList();
  _addReview(current,now,reviewIds);
  _grantRewards(rewards);
  _state.attackEnergy=RewardArithmetic.cappedAdd(_state.attackEnergy,rewards.fold<int>(0,(sum,r)=>RewardArithmetic.add(sum,r.exp)),9999);
  _state.gachaTickets=RewardArithmetic.add(_state.gachaTickets,1);
  if(current.rewards.any((r)=>r.stat==StatType.fitness)){
   _state.maxPlayerHp=RewardArithmetic.add(_state.maxPlayerHp,2);
   _state.playerHp=RewardArithmetic.cappedAdd(_state.playerHp,20,_state.maxPlayerHp);
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
  worldEngine.rewardEffort(_state.world,worldStats,_nowMs,physical:physical,magic:magic,levelUp:levelUp,naturalRecovery:_naturalRecoveryFor(_state));
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
  // 1回の付与内の同一属性・総EXPを全件検査し、成功後にまとめて反映する。
  final nextStats=Map<StatType,int>.of(_state.stats);
  var nextTotal=_state.totalExp;
  for(final r in rewards){
   if(r.exp<=0)throw StateError('Invalid EXP reward');
   nextStats[r.stat]=RewardArithmetic.add(nextStats[r.stat]??0,r.exp);
   nextTotal=RewardArithmetic.add(nextTotal,r.exp);
  }
  _state.stats.addAll(nextStats);
  _state.totalExp=nextTotal;
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
   _state.world.gold=RewardArithmetic.add(_state.world.gold,80);
  }else{
   counterDamage=8+min(10,_state.boss.defeats)*2;
   _state.playerHp=max(0,_state.playerHp-counterDamage);
  }
  _checkAchievements(battleOnly:true);
  await _persist();
  return BattleResult(damage:damage,counterDamage:counterDamage,defeated:defeated,playerKnockedOut:_state.playerHp==0);
 });
 Future<String?> drawBattleReward() => _transaction(() async{
  if(_state.gachaTickets<=0)return null;
  _state.gachaTickets--;
  final roll=(_legacyRewardRandom??Random.secure()).nextInt(100);
  String reward;
  if(roll<15){
   _state.attackEnergy=RewardArithmetic.cappedAdd(_state.attackEnergy,60,9999);
   reward='大当たり！ 攻撃エネルギー +60';
  }else if(roll<50){
   _state.attackEnergy=RewardArithmetic.cappedAdd(_state.attackEnergy,30,9999);
   reward='攻撃エネルギー +30';
  }else if(roll<80){
   _state.attackEnergy=RewardArithmetic.cappedAdd(_state.attackEnergy,15,9999);
   reward='攻撃エネルギー +15';
  }else{
   _state.world.gold=RewardArithmetic.add(_state.world.gold,50);
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
