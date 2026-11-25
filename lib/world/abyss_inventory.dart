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

class AbyssInventory {
 AbyssInventory();
 final Map<String,int> _stacks={};
 final Map<String,EquipmentInstance> _equipment={};
 final Set<String> _discovered={};
 final Map<EquipmentSlot,String> _equipped={};
 Map<EquipmentSlot,String> get equipped=>Map.unmodifiable(_equipped);
 void equip(String id){
  final item=_equipment[id];
  if(item==null)throw StateError('Equipment not owned');
  _equipped[item.slot]=id;
 }
 void unequip(EquipmentSlot slot){_equipped.remove(slot);}
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
 Map<String,dynamic> toJson()=>{'version':1,'sequence':_sequence,'equipped':{for(final e in _equipped.entries)e.key.name:e.value},'stacks':Map<String,int>.of(_stacks),'equipment':_equipment.values.map((e)=>e.toJson()).toList(),'discovered':_discovered.toList()..sort()};
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
