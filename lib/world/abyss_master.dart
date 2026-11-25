import 'dart:convert';
import 'abyss_equipment.dart';
import 'abyss_inventory.dart';
import 'abyss_summon.dart';
import 'abyss_summon_transaction.dart';

class SupplyDefinition {
 const SupplyDefinition({required this.id,required this.name,required this.rarity,required this.category});
 final String id,name,category;
 final EquipmentRarity rarity;
}

/// 承認済みマスターだけをゲームへ公開する。
class AbyssMaster {
 AbyssMaster._(this.equipment,this.summon,this._supplies,this.enabled);
 static const assetPath='assets/master/abyss_master.json';
 final EquipmentCatalog equipment;
 final SummonCatalog summon;
 final Map<String,SupplyDefinition> _supplies;
 final bool enabled;
 SupplyDefinition? supply(String id)=>_supplies[id];
 factory AbyssMaster.fromJson(String raw){
  final root=jsonDecode(raw) as Map<String,dynamic>;
  if(root['version']!=1||root['enabled'] is! bool)throw const FormatException('Invalid abyss master version');
  final enabled=root['enabled'] as bool;
  final equipment=<EquipmentDefinition>[];
  final equipmentById=<String,EquipmentDefinition>{};
  final supplies=<String,SupplyDefinition>{};
  for(final row in root['equipment'] as List){
   final j=row as Map<String,dynamic>;
   final def=EquipmentDefinition(id:j['id'] as String,name:j['name'] as String,slot:EquipmentSlot.values.byName(j['slot'] as String),rarity:EquipmentRarity.values.byName(j['rarity'] as String),physical:j['physical'] as int,magic:j['magic'] as int,defense:j['defense'] as int);
   if(def.slot==EquipmentSlot.hands||def.rarity.index>EquipmentRarity.ssr.index)throw const FormatException('Equipment outside prologue scope');
   if(equipmentById.containsKey(def.id))throw const FormatException('Duplicate equipment master');
   equipmentById[def.id]=def;
   equipment.add(def);
  }
  final validatedEquipment=EquipmentCatalog(equipment);
  for(final row in root['supplies'] as List){
   final j=row as Map<String,dynamic>;
   final def=SupplyDefinition(id:j['id'] as String,name:j['name'] as String,rarity:EquipmentRarity.values.byName(j['rarity'] as String),category:j['category'] as String);
   // 現段階で使用効果未実装のため、素材だけを許可する。
   if(def.rarity.index>EquipmentRarity.ssr.index)throw const FormatException('Supply outside prologue scope');
   if(!def.id.startsWith('item:')||def.id.length<=5||def.name.trim().isEmpty||def.category!='material'||supplies.containsKey(def.id))throw const FormatException('Invalid supply master');
   supplies[def.id]=def;
  }
  final entries=<SummonEntry>[];
  final seen=<String>{};
  for(final row in root['summon'] as List){
   final j=row as Map<String,dynamic>;
   final pool=SummonPool.values.byName(j['pool'] as String);
   final id=j['masterId'] as String;
   if(!seen.add(id))throw const FormatException('Duplicate summon master');
   EquipmentRarity rarity;
   if(pool==SummonPool.supplies){
    final def=supplies[id];
    if(def==null)throw const FormatException('Unknown supply master');
    rarity=def.rarity;
   }else{
    final def=equipmentById[id];
    if(def==null||(def.slot==EquipmentSlot.relic)!=(pool==SummonPool.relic))throw const FormatException('Invalid equipment pool');
    rarity=def.rarity;
   }
   entries.add(SummonEntry(pool:pool,masterId:id,rarity:rarity));
  }
  final validatedSummon=SummonCatalog(entries);
  // 無効状態の候補も含め、序章の全プール・希少度を検証する。
  for(final pool in SummonPool.values){
   for(final rarity in EquipmentRarity.values.take(4)){
    if(validatedSummon.entries(pool,rarity).isEmpty)throw const FormatException('Incomplete prologue summon pool');
   }
  }
  return AbyssMaster._(enabled?validatedEquipment:EquipmentCatalog.production,enabled?validatedSummon:SummonCatalog.production,Map.unmodifiable(enabled?supplies:<String,SupplyDefinition>{}),enabled);
 }
}
