import 'dart:convert';

class WorldEncounter {
 const WorldEncounter(this.id,this.stage,this.title,this.enemy,this.hp,this.attack,this.defense,this.gold,
  {this.main=false,this.lifeDays=0,this.rank='F',this.timeResistant=false});
 final String id,title,enemy,rank;
 final int stage,hp,attack,defense,gold,lifeDays;
 final bool main,timeResistant;
 factory WorldEncounter.fromJson(Map<String,dynamic> j)=>WorldEncounter(j['id'] as String,j['stage'] as int,j['title'] as String,j['enemy'] as String,j['hp'] as int,j['attack'] as int,j['defense'] as int,j['gold'] as int,main:j['main'] as bool,lifeDays:j['lifeDays'] as int,rank:j['rank'] as String,timeResistant:j['timeResistant'] as bool? ?? false);
}
class WorldCatalog {
 static const assetPath='assets/master/world_encounters.json';
 static List<WorldEncounter> _encounters=const [];
 static Map<int,String> _titles=const {};
 static List<WorldEncounter> get encounters=>_encounters;
 static Map<int,String> get titles=>_titles;
 static String mainId(int stage)=>'p${stage.toString().padLeft(2,'0')}_main';
 static void loadJson(String raw){
  final data=jsonDecode(raw);
  if(data is! Map<String,dynamic>||data['version']!=1)throw const FormatException('Unsupported world master');
  final entries=(data['encounters'] as List).map((e)=>WorldEncounter.fromJson(e as Map<String,dynamic>)).toList();
  final ids=<String>{},titles=<int,String>{};
  for(final e in entries){
   if(!ids.add(e.id)||e.stage<1||e.hp<1||e.attack<0||e.defense<0||e.gold<0||e.lifeDays<0||e.title.isEmpty||e.enemy.isEmpty)throw const FormatException('Invalid encounter');
   if(e.main){
    if(e.id!=mainId(e.stage)||titles.containsKey(e.stage))throw const FormatException('Invalid main encounter ID');
    titles[e.stage]=e.title;
   }
  }
  if(titles.isEmpty||List.generate(titles.length,(i)=>i+1).any((i)=>!titles.containsKey(i))||entries.any((e)=>!titles.containsKey(e.stage)))throw const FormatException('Noncontiguous stage master');
  for(final stage in titles.keys){
   if(entries.where((e)=>e.stage==stage&&!e.main).length!=3)throw const FormatException('Expected three free quests per stage');
  }
  _encounters=List.unmodifiable(entries);
  _titles=Map.unmodifiable(titles);
 }
 static WorldEncounter byId(String id)=>encounters.firstWhere((e)=>e.id==id,orElse:()=>throw ArgumentError('Unknown encounter: $id'));
}
