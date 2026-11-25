import 'abyss_inventory.dart';
import 'world_engine.dart';

class EquipmentDefinition {
 const EquipmentDefinition({required this.id,required this.name,required this.slot,required this.rarity,this.physical=0,this.magic=0,this.defense=0});
 final String id,name;
 final EquipmentSlot slot;
 final EquipmentRarity rarity;
 final int physical,magic,defense;
}

class EquipmentCatalog {
 EquipmentCatalog(Iterable<EquipmentDefinition> definitions){
  for(final item in definitions){
   if(!item.id.startsWith('equipment:')||item.id.length<=10||item.name.trim().isEmpty||[item.physical,item.magic,item.defense].any((v)=>v<0||v>1000000)||_entries.containsKey(item.id))throw const FormatException('Invalid equipment master');
   _entries[item.id]=item;
  }
 }
 final Map<String,EquipmentDefinition> _entries={};
 // No production definitions until individual item values are approved.
 static final production=EquipmentCatalog(const []);
 EquipmentDefinition? find(String id)=>_entries[id];
 EquipmentDefinition require(EquipmentInstance item){
  final definition=find(item.masterId);
  if(definition==null||definition.slot!=item.slot||definition.rarity!=item.rarity)throw StateError('Equipment master unavailable or mismatched');
  return definition;
 }
 WorldStats apply(WorldStats base,AbyssInventory inventory){
  var physical=base.physical,magic=base.magic,defense=base.defense;
  for(final id in inventory.equipped.values){
   final item=inventory.equipment[id]!;
   final definition=require(item);
   physical+=definition.physical;
   magic+=definition.magic;
   defense+=definition.defense;
  }
  return WorldStats(hp:base.hp,physical:physical,magic:magic,defense:defense,physicalMax:base.physicalMax,magicMax:base.magicMax,crit:base.crit);
 }
}
