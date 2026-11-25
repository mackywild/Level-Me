import 'abyss_inventory.dart';

enum CompendiumCategory { equipment, material, recovery, buff, purification }

extension CompendiumCategoryLabel on CompendiumCategory {
 String get label=>switch(this){
  CompendiumCategory.equipment=>'装備',
  CompendiumCategory.material=>'素材',
  CompendiumCategory.recovery=>'回復',
  CompendiumCategory.buff=>'バフ・特殊効果',
  CompendiumCategory.purification=>'浄化',
 };
}

class CompendiumDefinition {
 const CompendiumDefinition({required this.id,required this.name,required this.category,required this.rarity,required this.description});
 final String id,name,description;
 final CompendiumCategory category;
 final EquipmentRarity rarity;
}

/// 未発見枠にはマスターID・名称・希少度・詳細を保持しない。
class CompendiumEntry {
 const CompendiumEntry._(this.definition,this.owned);
 final CompendiumDefinition? definition;
 final int owned;
 bool get discovered=>definition!=null;
}

class CompendiumView {
 CompendiumView._(List<CompendiumEntry> entries,this.discoveredCount,this.totalCount):entries=List.unmodifiable(entries);
 final List<CompendiumEntry> entries;
 final int discoveredCount,totalCount;
}

class CompendiumCatalog {
 CompendiumCatalog(Iterable<CompendiumDefinition> definitions){
  for(final definition in definitions){
   final prefix=definition.category==CompendiumCategory.equipment?'equipment:':'item:';
   if(!definition.id.startsWith(prefix)||definition.id.length<=prefix.length||definition.name.trim().isEmpty||_definitions.containsKey(definition.id))throw const FormatException('Invalid compendium definition');
   _definitions[definition.id]=definition;
  }
 }
 final _definitions=<String,CompendiumDefinition>{};
 static final production=CompendiumCatalog(const []);
 CompendiumView view(AbyssInventory inventory){
  final discovered=inventory.discovered;
  final stacks=inventory.stacks;
  final ownedEquipment=<String,int>{};
  for(final item in inventory.equipment.values){
   ownedEquipment.update(item.masterId,(count)=>count+1,ifAbsent:()=>1);
  }
  final found=<CompendiumEntry>[];
  var hidden=0;
  for(final definition in _definitions.values){
   if(!discovered.contains(definition.id)){hidden++;continue;}
   final count=definition.category==CompendiumCategory.equipment?ownedEquipment[definition.id]??0:stacks[definition.id]??0;
   found.add(CompendiumEntry._(definition,count));
  }
  found.sort((a,b)=>a.definition!.id.compareTo(b.definition!.id));
  return CompendiumView._([
   ...found,
   for(var i=0;i<hidden;i++)const CompendiumEntry._(null,0),
  ],found.length,_definitions.length);
 }
}
