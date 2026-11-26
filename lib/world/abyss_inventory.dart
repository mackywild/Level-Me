import 'abyss_equipment_skill_policy.dart';

/// Inventory foundation. Master IDs are opaque until the catalog is introduced.
enum EquipmentSlot { hands, head, body, arms, legs, ring, necklace, relic }
enum EquipmentRarity { n, r, sr, ssr, ur, lr, gr, ex }

class EquipmentInstance {
 const EquipmentInstance({required this.id,required this.masterId,required this.slot,required this.rarity,this.enhancement=0,this.favorite=false});
 final String id,masterId;
 final EquipmentSlot slot;
 final EquipmentRarity rarity;
 final int enhancement;
 final bool favorite;
 Map<String,dynamic> toJson()=>{'id':id,'masterId':masterId,'slot':slot.name,'rarity':rarity.name,'enhancement':enhancement,'favorite':favorite};
 factory EquipmentInstance.fromJson(Map<String,dynamic> j)=>EquipmentInstance(id:j['id'] as String,masterId:j['masterId'] as String,slot:EquipmentSlot.values.byName(j['slot'] as String),rarity:EquipmentRarity.values.byName(j['rarity'] as String),enhancement:j['enhancement'] as int,favorite:j['favorite'] as bool);
}

/// 版1のランダム付与確定値。個体IDは所属履歴のキーで固定する。
class StoredEquipmentSkill {
 const StoredEquipmentSkill({required this.milestone,required this.skillId,required this.level,this.ruleVersion=1});
 final int milestone,level,ruleVersion;
 final String skillId;
 Map<String,dynamic> toJson()=>{'milestone':milestone,'skillId':skillId,'level':level,'ruleVersion':ruleVersion};
}

/// 導入時の強化値より前は旧枠として永久に抽選しない。
class EquipmentSkillHistory {
 EquipmentSkillHistory({required this.startEnhancement,required Iterable<StoredEquipmentSkill> grants}):grants=List.unmodifiable(grants);
 final int startEnhancement;
 final List<StoredEquipmentSkill> grants;
 Map<String,dynamic> toJson()=>{'startEnhancement':startEnhancement,'grants':grants.map((g)=>g.toJson()).toList()};
}

/// EX個体の登録済み構成を照合するための不変の参照情報。
/// ハッシュは改ざん防止署名ではなく、マスター差替え検出用。
class ExSkillHistoryLayout {
 ExSkillHistoryLayout({required this.fingerprint,required Iterable<int> milestones})
  :milestones=List.unmodifiable(milestones){
  if(!RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint)||this.milestones.isEmpty)throw const FormatException('Invalid EX layout reference');
  var previous=0;
  for(final stage in this.milestones){
   if(stage<=previous||stage>20)throw const FormatException('Invalid EX milestone');
   previous=stage;
  }
 }
 final String fingerprint;
 final List<int> milestones;
 Map<String,dynamic> toJson()=>{'fingerprint':fingerprint,'milestones':milestones};
 factory ExSkillHistoryLayout.fromJson(Object? raw){
  if(raw is! Map<String,dynamic>||raw.length!=2||raw['fingerprint'] is! String||raw['milestones'] is! List||(raw['milestones'] as List).any((v)=>v is! int))throw const FormatException('Invalid EX layout reference');
  return ExSkillHistoryLayout(fingerprint:raw['fingerprint'] as String,milestones:(raw['milestones'] as List).cast<int>());
 }
}

class AbyssInventory {
 AbyssInventory();
 final Map<String,int> _stacks={};
 final Map<String,EquipmentInstance> _equipment={};
 final Set<String> _discovered={};
 final Map<EquipmentSlot,String> _equipped={};
 final Map<String,EquipmentSkillHistory> _skillHistories={};
 final _exLayouts=<String,ExSkillHistoryLayout>{};
 Map<String,ExSkillHistoryLayout> get exSkillLayouts=>Map.unmodifiable(_exLayouts);
 int? _skillSeed;
 int? get equipmentSkillSeed=>_skillSeed;
 /// 一度だけ導入。版2では全通常個体の履歴を必須にする。
 void activateEquipmentSkills(int seed){
  if(_skillSeed!=null||seed<0||seed>0x7fffffff)throw StateError('Invalid equipment skill activation');
  if(_equipment.values.any((item)=>item.rarity==EquipmentRarity.ex))throw StateError('EX skill history layout not connected');
  for(final item in _equipment.values){
   _skillHistories.putIfAbsent(item.id,()=>EquipmentSkillHistory(startEnhancement:item.enhancement,grants:const []));
  }
  _skillSeed=seed;
 }
 Map<String,EquipmentSkillHistory> get equipmentSkillHistories=>Map.unmodifiable(_skillHistories);

 /// 現在値から将来のみ記録を開始。再初期化・EX仮設定は禁止。
 void beginEquipmentSkillHistory(String id,int expectedLevel){
  final item=_equipment[id];
  if(item==null||item.enhancement!=expectedLevel||_skillHistories.containsKey(id))throw StateError('Invalid skill history initialization');
  if(item.rarity==EquipmentRarity.ex)throw UnsupportedError('EX skill history layout not connected');
  _skillHistories[id]=EquipmentSkillHistory(startEnhancement:expectedLevel,grants:const []);
 }

 static void _validateSkillHistory(EquipmentInstance item,EquipmentSkillHistory history,{ExSkillHistoryLayout? exLayout}){
  if((item.rarity==EquipmentRarity.ex)!=(exLayout!=null)||history.startEnhancement<0||history.startEnhancement>item.enhancement||(exLayout!=null&&history.startEnhancement!=0))throw const FormatException('Invalid equipment skill history start');
  final expected=(exLayout?.milestones??EquipmentSkillPolicy.reachedMilestones(item.rarity,item.enhancement)).where((m)=>m>history.startEnhancement&&m<=item.enhancement).toList();
  if(expected.length!=history.grants.length)throw const FormatException('Missing or extra equipment skill grants');
  for(var i=0;i<expected.length;i++){
   final grant=history.grants[i];
   if(grant.milestone!=expected[i]||grant.ruleVersion!=1||!EquipmentSkillPolicy.validSkillLevel(grant.level)||
      !grant.skillId.startsWith('equipment_skill:')||grant.skillId.length<=16||grant.skillId.trim()!=grant.skillId){
    throw const FormatException('Invalid equipment skill grant');
   }
  }
 }

 /// 強化後の確定履歴を先に検証し、素材消費前に失敗させる。
 EquipmentSkillHistory? _nextSkillHistory(EquipmentInstance item,StoredEquipmentSkill? grant){
  final history=_skillHistories[item.id];
  if(history==null){
   if(grant!=null)throw StateError('Skill history not initialized');
   return null;
  }
  final next=EquipmentSkillHistory(startEnhancement:history.startEnhancement,grants:[...history.grants,?grant]);
  final future=EquipmentInstance(id:item.id,masterId:item.masterId,slot:item.slot,rarity:item.rarity,enhancement:item.enhancement+1,favorite:item.favorite);
  _validateSkillHistory(future,next,exLayout:_exLayouts[item.id]);
  return next;
 }

 // 版1: 実消費履歴を強化段階順に保存。旧履歴欠落は推測しない。
 final Map<String,List<Map<String,int>>> _enhancementCosts={};
 bool hasCompleteEnhancementHistory(EquipmentInstance item)=>
  (_enhancementCosts[item.id]?.length??0)==item.enhancement;
 Map<String,int> enhancementRefund(EquipmentInstance item){
  if(!hasCompleteEnhancementHistory(item))throw StateError('Enhanced equipment protected');
  final totals=<String,int>{};
  for(final step in _enhancementCosts[item.id]??const <Map<String,int>>[]){
   for(final cost in step.entries){totals.update(cost.key,(n)=>n+cost.value,ifAbsent:()=>cost.value);}
  }
  return Map.unmodifiable({for(final entry in totals.entries)if(entry.value>=10)entry.key:entry.value~/10});
 }
 Map<EquipmentSlot,String> get equipped=>Map.unmodifiable(_equipped);
 void equip(String id){
  final item=_equipment[id];
  if(item==null)throw StateError('Equipment not owned');
  if(_exLayouts.containsKey(id))throw StateError('EX fixed effects not connected');
  _equipped[item.slot]=id;
 }
 void unequip(EquipmentSlot slot){_equipped.remove(slot);}
 /// 保護状態を個体単位で更新し、他の属性は保持する。
 void setFavorite(String id,bool favorite){
  final item=_equipment[id];
  if(item==null)throw StateError('Equipment not owned');
  _equipment[id]=EquipmentInstance(id:item.id,masterId:item.masterId,slot:item.slot,rarity:item.rarity,enhancement:item.enhancement,favorite:favorite);
 }
 /// 分解対象の保護条件を低レベルAPIでも保証する。
 EquipmentInstance requireDismantleable(String id,int expectedLevel){
  final item=_equipment[id];
  if(item==null)throw StateError('Equipment not owned');
  if(item.enhancement!=expectedLevel)throw StateError('Stale dismantle request');
  if(item.favorite||_equipped.containsValue(id))throw StateError('Equipment protected');
  if(!hasCompleteEnhancementHistory(item))throw StateError('Enhanced equipment protected');
  return item;
 }
 EquipmentInstance removeEquipment(String id,int expectedLevel){
  final item=requireDismantleable(id,expectedLevel);
  _equipment.remove(id);
  _enhancementCosts.remove(id);
  _skillHistories.remove(id);
  _exLayouts.remove(id);
  return item;
 }

 /// 強化値を一段階進める。個体ID・装着状態・お気に入りを保持する。
 EquipmentInstance enhance(String id,int expectedLevel){
  final item=_equipment[id];
  if(item==null)throw StateError('Equipment not owned');
  if(item.enhancement!=expectedLevel)throw StateError('Stale enhancement request');
  if(item.enhancement>=20)throw StateError('Enhancement limit reached');
  if(_enhancementCosts.containsKey(id)||_skillHistories.containsKey(id))throw StateError('Recorded enhancement history requires paid enhancement');
  return _advanceEnhancement(item);
 }
 EquipmentInstance _advanceEnhancement(EquipmentInstance item){
  final next=EquipmentInstance(id:item.id,masterId:item.masterId,slot:item.slot,rarity:item.rarity,enhancement:item.enhancement+1,favorite:item.favorite);
  _equipment[item.id]=next;
  return next;
 }

 /// 実消費と強化を同時に記録。旧履歴欠落個体は引き続き還元保護。
 EquipmentInstance enhanceWithMaterial(String id,int expectedLevel,String materialId,int quantity,{StoredEquipmentSkill? skillGrant})=>enhanceWithMaterials(id,expectedLevel,{materialId:quantity},skillGrant:skillGrant);

 /// 複数素材は全件を検証してから一段階分として消費する。
 EquipmentInstance enhanceWithMaterials(String id,int expectedLevel,Map<String,int> materials,{StoredEquipmentSkill? skillGrant}){
  final item=_equipment[id];
  if(item==null||item.enhancement!=expectedLevel||expectedLevel<0||expectedLevel>=20)throw StateError('Invalid enhancement request');
  final costs=Map<String,int>.unmodifiable(materials);
  if(_exLayouts.containsKey(id)&&costs.length!=2)throw StateError('EX enhancement requires two materials');
  if(costs.isEmpty||costs.length>2||costs.entries.any((e)=>!e.key.startsWith('item:')||e.key.length<=5||e.key.trim()!=e.key||e.value<=0||e.value>1000000))throw ArgumentError('Invalid enhancement cost');
  for(final cost in costs.entries){if((_stacks[cost.key]??0)<cost.value)throw StateError('Insufficient items');}
  if(!hasCompleteEnhancementHistory(item))throw StateError('Enhancement history missing');
  final nextSkills=_nextSkillHistory(item,skillGrant);
  final history=[...?_enhancementCosts[id],costs];
  for(final cost in costs.entries){removeStack(cost.key,cost.value);}
  final next=_advanceEnhancement(item);
  _enhancementCosts[id]=history;
  if(nextSkills!=null)_skillHistories[id]=nextSkills;
  return next;
 }

 int _sequence=0;
 Map<String,int> get stacks=>Map.unmodifiable(_stacks);
 Map<String,EquipmentInstance> get equipment=>Map.unmodifiable(_equipment);
 Set<String> get discovered=>Set.unmodifiable(_discovered);
 static void _checkId(String id){if(id.trim().isEmpty)throw const FormatException('Empty master or instance ID');}
 void addStack(String masterId,int quantity){
  _checkId(masterId);
  if(quantity<=0)throw ArgumentError.value(quantity,'quantity');
  final next=(_stacks[masterId]??0)+quantity;
  if(next<=0||next<quantity)throw StateError('Stack overflow');
  _stacks[masterId]=next;
  _discovered.add(masterId);
 }
 void removeStack(String masterId,int quantity){
  if(quantity<=0)throw ArgumentError.value(quantity,'quantity');
  final count=_stacks[masterId]??0;
  if(count<quantity)throw StateError('Insufficient items');
  if(count==quantity){_stacks.remove(masterId);}else{_stacks[masterId]=count-quantity;}
 }
 EquipmentInstance addEquipment(String masterId,EquipmentSlot slot,EquipmentRarity rarity){
  _checkId(masterId);
  if(_skillSeed!=null&&rarity==EquipmentRarity.ex)throw StateError('EX skill history layout not connected');
  return _addEquipment(masterId,slot,rarity);
 }
 /// 登録済みマスターの照合情報から新規EX個体を作る低レベル入口。
 /// 正式な入手経路・素材種別の検証は呼出し側の責務。
 EquipmentInstance addRegisteredExEquipment(String masterId,EquipmentSlot slot,ExSkillHistoryLayout layout){
  if(_skillSeed==null)throw StateError('Equipment skill seed missing');
  if(!masterId.startsWith('equipment:')||masterId.length<=10||masterId.trim()!=masterId)throw StateError('Invalid EX master ID');
  final item=_addEquipment(masterId,slot,EquipmentRarity.ex);
  _exLayouts[item.id]=layout;
  return item;
 }
 EquipmentInstance _addEquipment(String masterId,EquipmentSlot slot,EquipmentRarity rarity){
  final next=_sequence+1;
  if(next<=_sequence)throw StateError('Equipment sequence overflow');
  final item=EquipmentInstance(id:'eq_$next',masterId:masterId,slot:slot,rarity:rarity);
  if(_equipment.containsKey(item.id))throw StateError('Duplicate equipment ID');
  _sequence=next;
  _equipment[item.id]=item;
  if(_skillSeed!=null)_skillHistories[item.id]=EquipmentSkillHistory(startEnhancement:0,grants:const []);
  _discovered.add(masterId);
  return item;
 }
 Map<String,dynamic> toJson()=>{'version':_exLayouts.isNotEmpty?3:_skillSeed==null?1:2,if(_exLayouts.isNotEmpty)'exSkillLayouts':{for(final e in _exLayouts.entries)e.key:e.value.toJson()},if(_skillSeed!=null)'equipmentSkillSeed':_skillSeed,'sequence':_sequence,'equipped':{for(final e in _equipped.entries)e.key.name:e.value},'stacks':Map<String,int>.of(_stacks),'equipment':_equipment.values.map((e)=>e.toJson()).toList(),'discovered':_discovered.toList()..sort(),if(_skillSeed!=null||_skillHistories.isNotEmpty)'equipmentSkills':{'version':1,'items':{for(final e in _skillHistories.entries)e.key:e.value.toJson()}},if(_enhancementCosts.isNotEmpty)'enhancementCosts':_encodeEnhancementCosts()};
 Map<String,dynamic> _encodeEnhancementCosts(){
  final multi=_enhancementCosts.values.any((steps)=>steps.any((step)=>step.length>1));
  return {'version':multi?2:1,'items':{for(final e in _enhancementCosts.entries)e.key:[
   for(final step in e.value)if(multi){'materials':Map<String,int>.of(step)}else{'materialId':step.keys.single,'quantity':step.values.single}
  ]}};
 }
 factory AbyssInventory.fromJson(Map<String,dynamic> j){
  final version=j['version'];
  if(version is! int||(version!=1&&version!=2&&version!=3))throw const FormatException('Unsupported inventory version');
  final inventory=AbyssInventory();
  if(version==2||version==3){
   final seed=j['equipmentSkillSeed'];
   if(seed is! int||seed<0||seed>0x7fffffff||!j.containsKey('equipmentSkills'))throw const FormatException('Invalid equipment skill activation');
   inventory._skillSeed=seed;
  }else if(j.containsKey('equipmentSkillSeed')){throw const FormatException('Unexpected equipment skill seed');}
  inventory._sequence=j['sequence'] as int;
  if(inventory._sequence<0)throw const FormatException('Negative equipment sequence');
  for(final entry in (j['stacks'] as Map<String,dynamic>).entries){
   _checkId(entry.key);
   final count=entry.value as int;
   if(count<=0)throw const FormatException('Invalid stack count');
   inventory._stacks[entry.key]=count;
  }
  for(final raw in j['equipment'] as List){
   final item=EquipmentInstance.fromJson(raw as Map<String,dynamic>);
   _checkId(item.masterId);
   final serial=int.tryParse(item.id.startsWith('eq_')?item.id.substring(3):'');
   if(serial==null||serial<=0||serial>inventory._sequence||item.id!='eq_$serial'||inventory._equipment.containsKey(item.id)||item.enhancement<0||item.enhancement>20)throw const FormatException('Invalid equipment instance');
   inventory._equipment[item.id]=item;
  }
  for(final id in (j['discovered'] as List).cast<String>()){
   _checkId(id);
   inventory._discovered.add(id);
  }
  if(!inventory._discovered.containsAll(inventory._stacks.keys)||!inventory._discovered.containsAll(inventory._equipment.values.map((e)=>e.masterId)))throw const FormatException('Missing discovery record');
  if(j.containsKey('enhancementCosts')){
   final history=j['enhancementCosts'];
   if(history is! Map<String,dynamic>||history['version'] is! int||(history['version']!=1&&history['version']!=2)||history['items'] is! Map<String,dynamic>)throw const FormatException('Invalid enhancement history');
   for(final entry in (history['items'] as Map<String,dynamic>).entries){
    final item=inventory._equipment[entry.key];
    final costs=entry.value;
    if(item==null||costs is! List||costs.isEmpty||costs.length!=item.enhancement)throw const FormatException('Invalid enhancement history length');
    final validated=<Map<String,int>>[];
    for(final raw in costs){
     if(raw is! Map<String,dynamic>)throw const FormatException('Invalid enhancement cost');
     final Map<dynamic,dynamic> materials;
     if(history['version']==1){
      if(raw.length!=2||!raw.containsKey('materialId')||!raw.containsKey('quantity'))throw const FormatException('Invalid enhancement cost');
      materials={raw['materialId']:raw['quantity']};
     }else{
      if(raw.length!=1||raw['materials'] is! Map<String,dynamic>)throw const FormatException('Invalid enhancement materials');
      materials=raw['materials'] as Map<String,dynamic>;
     }
     if(materials.isEmpty||materials.length>2)throw const FormatException('Invalid enhancement materials');
     final step=<String,int>{};
     for(final entry in materials.entries){
      final materialId=entry.key,quantity=entry.value;
      if(materialId is! String||!materialId.startsWith('item:')||materialId.length<=5||materialId.trim()!=materialId||quantity is! int||quantity<=0||quantity>1000000||!inventory._discovered.contains(materialId))throw const FormatException('Invalid enhancement cost');
      step[materialId]=quantity;
     }
     validated.add(Map.unmodifiable(step));
    }
    inventory._enhancementCosts[entry.key]=validated;
   }
  }
  if(version==3){
   final layouts=j['exSkillLayouts'];
   if(layouts is! Map<String,dynamic>||layouts.isEmpty)throw const FormatException('Missing EX layout references');
   for(final entry in layouts.entries){
    final item=inventory._equipment[entry.key];
    if(item==null||item.rarity!=EquipmentRarity.ex)throw const FormatException('Invalid EX layout owner');
    inventory._exLayouts[entry.key]=ExSkillHistoryLayout.fromJson(entry.value);
    final steps=inventory._enhancementCosts[item.id]??const <Map<String,int>>[];
    if(steps.length!=item.enhancement||steps.any((step)=>step.length!=2))throw const FormatException('Incomplete EX material history');
   }
  }else if(j.containsKey('exSkillLayouts')){throw const FormatException('Unexpected EX layout references');}
  if(j.containsKey('equipmentSkills')){
   final raw=j['equipmentSkills'];
   if(raw is! Map<String,dynamic>||raw['version'] is! int||raw['version']!=1||raw['items'] is! Map<String,dynamic>)throw const FormatException('Invalid equipment skills version');
   for(final entry in (raw['items'] as Map<String,dynamic>).entries){
    final item=inventory._equipment[entry.key],history=entry.value;
    if(item==null||history is! Map<String,dynamic>||history['startEnhancement'] is! int||history['grants'] is! List)throw const FormatException('Invalid equipment skill history');
    final grants=<StoredEquipmentSkill>[];
    for(final row in history['grants'] as List){
     if(row is! Map<String,dynamic>||row['milestone'] is! int||row['skillId'] is! String||row['level'] is! int||row['ruleVersion'] is! int)throw const FormatException('Invalid equipment skill grant fields');
     grants.add(StoredEquipmentSkill(milestone:row['milestone'] as int,skillId:row['skillId'] as String,level:row['level'] as int,ruleVersion:row['ruleVersion'] as int));
    }
    final value=EquipmentSkillHistory(startEnhancement:history['startEnhancement'] as int,grants:grants);
    _validateSkillHistory(item,value,exLayout:inventory._exLayouts[item.id]);
    inventory._skillHistories[item.id]=value;
   }
  }
  if(version>=2&&(inventory._skillHistories.length!=inventory._equipment.length||inventory._equipment.values.any((item)=>(item.rarity==EquipmentRarity.ex)!=inventory._exLayouts.containsKey(item.id)||!inventory._skillHistories.containsKey(item.id)))){
   throw const FormatException('Incomplete activated equipment skill histories');
  }
  final equipped=j.containsKey('equipped')?j['equipped'] as Map<String,dynamic>:<String,dynamic>{};
  for(final entry in equipped.entries){
   final slot=EquipmentSlot.values.byName(entry.key);
   final id=entry.value as String;
   if(inventory._equipment[id]?.slot!=slot||inventory._exLayouts.containsKey(id))throw const FormatException('Invalid equipped reference');
   inventory._equipped[slot]=id;
  }
  return inventory;
 }
}
