import 'abyss_inventory.dart';
import 'world_engine.dart';

class EquipmentDefinition {
 const EquipmentDefinition({required this.id,required this.name,required this.slot,required this.rarity,this.physical=0,this.magic=0,this.defense=0});
 final String id,name;
 final EquipmentSlot slot;
 final EquipmentRarity rarity;
 final int physical,magic,defense;
}

/// 承認済みの基礎装備性能5%加算。公開経路の有効化は別途管理する。
class EnhancementScaling {
 const EnhancementScaling.disabled():percentPerLevel=0;
 const EnhancementScaling.approved():percentPerLevel=5;
 // 既存の明示注入APIとの互換性を保持する。
 const EnhancementScaling.proposed():this.approved();
 final int percentPerLevel;
 int apply(int base,int level){
  if(level<0||level>20)throw RangeError.range(level,0,20);
  // 個々の装備補正を整数で切り捨てる暫定案。プレイヤー基本値には掛けない。
  if(base<0)throw StateError('Invalid equipment base stat');
  return WorldStats.checkedStat(BigInt.from(base)*BigInt.from(100+percentPerLevel*level)~/BigInt.from(100));
 }
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
 void validateLoadout(AbyssInventory inventory){
  for(final id in inventory.equipped.values){require(inventory.equipment[id]!);}
 }
 WorldStats apply(WorldStats base,AbyssInventory inventory,{EnhancementScaling scaling=const EnhancementScaling.disabled()}){
  var physical=base.physical,magic=base.magic,defense=base.defense;
  for(final id in inventory.equipped.values){
   final item=inventory.equipment[id]!;
   final definition=require(item);
   physical=WorldStats.checkedAdd(physical,scaling.apply(definition.physical,item.enhancement));
   magic=WorldStats.checkedAdd(magic,scaling.apply(definition.magic,item.enhancement));
   defense=WorldStats.checkedAdd(defense,scaling.apply(definition.defense,item.enhancement));
  }
  return WorldStats(hp:base.hp,physical:physical,magic:magic,defense:defense,physicalMax:base.physicalMax,magicMax:base.magicMax,crit:base.crit);
 }
}
