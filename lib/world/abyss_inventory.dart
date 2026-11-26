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

class AbyssInventory {
 AbyssInventory();
 final Map<String,int> _stacks={};
 final Map<String,EquipmentInstance> _equipment={};
 final Set<String> _discovered={};
 final Map<EquipmentSlot,String> _equipped={};
 final Map<String,EquipmentSkillHistory> _skillHistories={};
 Map<String,EquipmentSkillHistory> get equipmentSkillHistories=>Map.unmodifiable(_skillHistories);

 /// 現在値から将来のみ記録を開始。再初期化・EX仮設定は禁止。
 void beginEquipmentSkillHistory(String id,int expectedLevel){
  final item=_equipment[id];
  if(item==null||item.enhancement!=expectedLevel||_skillHistories.containsKey(id))throw StateError('Invalid skill history initialization');
  if(item.rarity==EquipmentRarity.ex)throw UnsupportedError('EX skill history layout not connected');
  _skillHistories[id]=EquipmentSkillHistory(startEnhancement:expectedLevel,grants:const []);
 }

 static void _validateSkillHistory(EquipmentInstance item,EquipmentSkillHistory history){
  if(item.rarity==EquipmentRarity.ex||history.startEnhancement<0||history.startEnhancement>item.enhancement)throw const FormatException('Invalid equipment skill history start');
  final expected=EquipmentSkillPolicy.reachedMilestones(item.rarity,item.enhancement).where((m)=>m>history.startEnhancement).toList();
  if(expected.length!=history.grants.length)throw const FormatException('Missing or extra equipment skill grants');
  for(var i=0;i<expected.length;i++){
   final grant=history.grants[i];
   if(grant.milestone!=expected[i]||grant.ruleVersion!=1||!EquipmentSkillPolicy.validSkillLevel(grant.level)||
      !grant.skillId.startsWith('equipment_skill:')||grant.skillId.length<=16||grant.skillId.trim()!=grant.skillId)throw const FormatException('Invalid equipment skill grant');
  }
 }

 /// 強化後の確定履歴を先に検証し、素材消費前に失敗させる。
 EquipmentSkillHistory? _nextSkillHistory(EquipmentInstance item,StoredEquipmentSkill? grant){
  final history=_skillHistories[item.id];
  if(history==null){
   if(grant!=null)throw StateError('Skill history not initialized');
   return null;
  }
  final next=EquipmentSkillHistory(startEnhancement:history.startEnhancement,grants:[...history.grants,if(grant!=null)grant]);
  final future=EquipmentInstance(id:item.id,masterId:item.masterId,slot:item.slot,rarity:item.rarity,enhancement:item.enhancement+1,favorite:item.favorite);
  _validateSkillHistory(future,next);
  return next;
 }

 // 版1: 実消費履歴を強化段階順に保存。旧履歴欠落は推測しない。
 final Map<String,List<({String materialId,int quantity})>> _enhancementCosts={};
 bool hasCompleteEnhancementHistory(EquipmentInstance item)=>
  (_enhancementCosts[item.id]?.length??0)==item.enhancement;
 Map<String,int> enhancementRefund(EquipmentInstance item){
  if(!hasCompleteEnhancementHistory(item))throw StateError('Enhanced equipment protected');
  final totals=<String,int>{};
  for(final cost in _enhancementCosts[item.id]??const <({String materialId,int quantity})>[]){
   totals.update(cost.materialId,(n)=>n+cost.quantity,ifAbsent:()=>cost.quantity);
  }
  return Map.unmodifiable({for(final entry in totals.entries)if(entry.value>=10)entry.key:entry.value~/10});
 }
 Map<EquipmentSlot,String> get equipped=>Map.unmodifiable(_equipped);
 void equip(String id){
  final item=_equipment[id];
  if(item==null)throw StateError('Equipment not owned');
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
 EquipmentInstance enhanceWithMaterial(String id,int expectedLevel,String materialId,int quantity,{StoredEquipmentSkill? skillGrant}){
  final item=_equipment[id];
  if(item==null||item.enhancement!=expectedLevel||expectedLevel<0||expectedLevel>=20)throw StateError('Invalid enhancement request');
  if(!materialId.startsWith('item:')||materialId.length<=5||quantity<=0||quantity>1000000)throw ArgumentError('Invalid enhancement cost');
  if(!hasCompleteEnhancementHistory(item))throw StateError('Enhancement history missing');
  final nextSkills=_nextSkillHistory(item,skillGrant);
  final history=[...?_enhancementCosts[id],(materialId:materialId,quantity:quantity)];
  removeStack(materialId,quantity);
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
  final next=_sequence+1;
  if(next<=_sequence)throw StateError('Equipment sequence overflow');
  final item=EquipmentInstance(id:'eq_$next',masterId:masterId,slot:slot,rarity:rarity);
  if(_equipment.containsKey(item.id))throw StateError('Duplicate equipment ID');
  _sequence=next;
  _equipment[item.id]=item;
  _discovered.add(masterId);
  return item;
 }
 Map<String,dynamic> toJson()=>{'version':1,'sequence':_sequence,'equipped':{for(final e in _equipped.entries)e.key.name:e.value},'stacks':Map<String,int>.of(_stacks),'equipment':_equipment.values.map((e)=>e.toJson()).toList(),'discovered':_discovered.toList()..sort(),if(_skillHistories.isNotEmpty)'equipmentSkills':{'version':1,'items':{for(final e in _skillHistories.entries)e.key:e.value.toJson()}},if(_enhancementCosts.isNotEmpty)'enhancementCosts':{'version':1,'items':{for(final e in _enhancementCosts.entries)e.key:[for(final cost in e.value){'materialId':cost.materialId,'quantity':cost.quantity}]}}};
 factory AbyssInventory.fromJson(Map<String,dynamic> j){
  if(j['version']!=1)throw const FormatException('Unsupported inventory version');
  final inventory=AbyssInventory();
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
   if(history is! Map<String,dynamic>||history['version']!=1||history['items'] is! Map<String,dynamic>)throw const FormatException('Invalid enhancement history');
   for(final entry in (history['items'] as Map<String,dynamic>).entries){
    final item=inventory._equipment[entry.key];
    final costs=entry.value;
    if(item==null||costs is! List||costs.isEmpty||costs.length!=item.enhancement)throw const FormatException('Invalid enhancement history length');
    final validated=<({String materialId,int quantity})>[];
    for(final raw in costs){
     if(raw is! Map<String,dynamic>)throw const FormatException('Invalid enhancement cost');
     final materialId=raw['materialId'],quantity=raw['quantity'];
     if(materialId is! String||!materialId.startsWith('item:')||materialId.length<=5||quantity is! int||quantity<=0||quantity>1000000||!inventory._discovered.contains(materialId))throw const FormatException('Invalid enhancement cost');
     validated.add((materialId:materialId,quantity:quantity));
    }
    inventory._enhancementCosts[entry.key]=validated;
   }
  }
  if(j.containsKey('equipmentSkills')){
   final raw=j['equipmentSkills'];
   if(raw is! Map<String,dynamic>||raw['version']!=1||raw['items'] is! Map<String,dynamic>)throw const FormatException('Invalid equipment skills version');
   for(final entry in (raw['items'] as Map<String,dynamic>).entries){
    final item=inventory._equipment[entry.key],history=entry.value;
    if(item==null||history is! Map<String,dynamic>||history['startEnhancement'] is! int||history['grants'] is! List)throw const FormatException('Invalid equipment skill history');
    final grants=<StoredEquipmentSkill>[];
    for(final row in history['grants'] as List){
     if(row is! Map<String,dynamic>||row['milestone'] is! int||row['skillId'] is! String||row['level'] is! int||row['ruleVersion'] is! int)throw const FormatException('Invalid equipment skill grant fields');
     grants.add(StoredEquipmentSkill(milestone:row['milestone'] as int,skillId:row['skillId'] as String,level:row['level'] as int,ruleVersion:row['ruleVersion'] as int));
    }
    final value=EquipmentSkillHistory(startEnhancement:history['startEnhancement'] as int,grants:grants);
    _validateSkillHistory(item,value);
    inventory._skillHistories[item.id]=value;
   }
  }
  final equipped=j.containsKey('equipped')?j['equipped'] as Map<String,dynamic>:<String,dynamic>{};
  for(final entry in equipped.entries){
   final slot=EquipmentSlot.values.byName(entry.key);
   final id=entry.value as String;
   if(inventory._equipment[id]?.slot!=slot)throw const FormatException('Invalid equipped reference');
   inventory._equipped[slot]=id;
  }
  return inventory;
 }
}
