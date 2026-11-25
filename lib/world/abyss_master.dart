import 'dart:convert';
import 'abyss_equipment.dart';
import 'abyss_compendium.dart';
import 'abyss_consumable.dart';
import 'abyss_buff.dart';
import 'abyss_purification.dart';
import 'world_engine.dart';
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
 AbyssMaster._(this.equipment,this.summon,this._supplies,this.enabled,this.recovery,this.buffs,this.purification,this.compendium);
 static const assetPath='assets/master/abyss_master.json';
 final EquipmentCatalog equipment;
 final SummonCatalog summon;
 final Map<String,SupplyDefinition> _supplies;
 final bool enabled;
 final ConsumableCatalog recovery;
 final BuffCatalog buffs;
 final PurificationCatalog purification;
 final CompendiumCatalog compendium;
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
  // 回復品候補は素材と別区分。召喚・販売・付与の正式承認までは公開しない。
  final recoveryItems=<RecoveryItem>[];
  final recoveryIds=<String>{};
  final recoveryEnabled=root.containsKey('recoveryEnabled')?root['recoveryEnabled'] as bool:false;
  if(recoveryEnabled)throw const FormatException('Recovery activation not approved');
  for(final row in (root.containsKey('recovery')?root['recovery'] as List:const [])){
   final j=row as Map<String,dynamic>;
   final id=j['id'] as String;
   final rarity=EquipmentRarity.values.byName(j['rarity'] as String);
   if(j['category']!='recovery'||supplies.containsKey(id)||!recoveryIds.add(id)||rarity.index>EquipmentRarity.ssr.index)throw const FormatException('Invalid recovery master');
   recoveryItems.add(RecoveryItem(id:id,name:j['name'] as String,target:RecoveryTarget.values.byName(j['target'] as String),percent:j['percent'] as int));
  }
  // 非公開の候補についても形式を検証する。
  ConsumableCatalog(recoveryItems);
  final buffItems=<BuffItem>[];
  final buffIds=<String>{};
  if(root.containsKey('buffEnabled')&&root['buffEnabled']!=false)throw const FormatException('Buff activation not approved');
  for(final row in (root.containsKey('buffs')?root['buffs'] as List:const [])){
   final j=row as Map<String,dynamic>;
   final id=j['id'] as String;
   final rarity=EquipmentRarity.values.where((r)=>r.name==j['rarity']);
   final kinds=BattleBuff.values.where((k)=>k.name==j['kind']);
   if(j['category']!='buff'||supplies.containsKey(id)||recoveryIds.contains(id)||!buffIds.add(id)||rarity.isEmpty||rarity.first.index>EquipmentRarity.ssr.index||kinds.isEmpty)throw const FormatException('Invalid buff master');
   final kind=kinds.first;
   if(j['percent'] is! int||j['duration'] is! int||j['percent']!=kind.percent||j['duration']!=kind.duration)throw const FormatException('Buff rules mismatch');
   buffItems.add(BuffItem(id:id,name:j['name'] as String,kind:kind));
  }
  BuffCatalog(buffItems);
  final purificationItems=<PurificationItem>[];
  final purificationIds=<String>{};
  if(root.containsKey('purificationEnabled')&&root['purificationEnabled']!=false)throw const FormatException('Purification activation not approved');
  for(final row in (root.containsKey('purification')?root['purification'] as List:const [])){
   final j=row as Map<String,dynamic>;
   final id=j['id'] as String;
   final rarity=EquipmentRarity.values.where((r)=>r.name==j['rarity']);
   if(j['category']!='purification'||supplies.containsKey(id)||recoveryIds.contains(id)||buffIds.contains(id)||!purificationIds.add(id)||rarity.isEmpty||rarity.first.index>EquipmentRarity.ssr.index)throw const FormatException('Invalid purification master');
   purificationItems.add(PurificationItem(id:id,name:j['name'] as String));
  }
  PurificationCatalog(purificationItems);
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
  final compendium=enabled?CompendiumCatalog([
   for(final def in equipment)CompendiumDefinition(id:def.id,name:def.name,category:CompendiumCategory.equipment,rarity:def.rarity,description:'${def.slot.name} / 物攻 +${def.physical} / 魔攻 +${def.magic} / 防御 +${def.defense}'),
   for(final def in supplies.values)CompendiumDefinition(id:def.id,name:def.name,category:CompendiumCategory.material,rarity:def.rarity,description:'素材'),
  ]):CompendiumCatalog.production;
  return AbyssMaster._(enabled?validatedEquipment:EquipmentCatalog.production,enabled?validatedSummon:SummonCatalog.production,Map.unmodifiable(enabled?supplies:<String,SupplyDefinition>{}),enabled,ConsumableCatalog.production,BuffCatalog.production,PurificationCatalog.production,compendium);
 }
}
