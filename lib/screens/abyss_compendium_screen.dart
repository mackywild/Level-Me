import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../world/abyss_compendium.dart';
import '../world/abyss_inventory.dart';

enum _DiscoveryFilter { all, found, hidden }

class AbyssCompendiumScreen extends StatefulWidget {
 const AbyssCompendiumScreen({super.key,required this.controller});
 final AppController controller;
 @override State<AbyssCompendiumScreen> createState()=>_AbyssCompendiumScreenState();
}

class _AbyssCompendiumScreenState extends State<AbyssCompendiumScreen>{
 String _query='';
 _DiscoveryFilter _filter=_DiscoveryFilter.all;
 CompendiumCategory? _category;
 EquipmentRarity? _rarity;
 bool _matches(CompendiumEntry entry){
  final def=entry.definition;
  if(def==null)return _filter!=_DiscoveryFilter.found&&_query.isEmpty&&_category==null&&_rarity==null;
  return _filter!=_DiscoveryFilter.hidden&&(_category==null||def.category==_category)&&(_rarity==null||def.rarity==_rarity)&&
   (def.name.toLowerCase().contains(_query)||def.id.toLowerCase().contains(_query));
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('深淵図鑑')),
  body:ListenableBuilder(listenable:widget.controller,builder:(context,child){
   final c=widget.controller;
   if(!c.ready)return const Center(child:Text('初期化中'));
   final view=c.compendiumView;
   final visible=view.entries.where(_matches).toList();
   return ListView(padding:const EdgeInsets.all(16),children:[
    const Text('ABYSS COMPENDIUM',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:Color(0xffd5b36e))),
    if(view.totalCount==0)
     const Text('公開済み図鑑マスターなし')
    else...[
     Text('発見済み ${view.discoveredCount} / ${view.totalCount}'),
     LinearProgressIndicator(value:view.discoveredCount/view.totalCount),
     Text('発見率：${(view.discoveredCount/view.totalCount*100).toStringAsFixed(1)}%'),
     TextField(key:const ValueKey('compendium-search'),decoration:const InputDecoration(labelText:'発見済みの名前・IDで検索'),onChanged:(value)=>setState(()=>_query=value.trim().toLowerCase())),
     Wrap(spacing:8,children:[
      for(final pair in const [(_DiscoveryFilter.all,'すべて'),(_DiscoveryFilter.found,'発見済み'),(_DiscoveryFilter.hidden,'未発見')])
       ChoiceChip(label:Text(pair.$2),selected:_filter==pair.$1,onSelected:(_)=>setState(()=>_filter=pair.$1)),
     ]),
     DropdownButton<CompendiumCategory?>(
      key:const ValueKey('compendium-category'),value:_category,
      items:[const DropdownMenuItem<CompendiumCategory?>(value:null,child:Text('全カテゴリ')),for(final category in CompendiumCategory.values)DropdownMenuItem<CompendiumCategory?>(value:category,child:Text(category.label))],
      onChanged:(value)=>setState(()=>_category=value),
     ),
     DropdownButton<EquipmentRarity?>(
      key:const ValueKey('compendium-rarity'),value:_rarity,
      items:[const DropdownMenuItem<EquipmentRarity?>(value:null,child:Text('全希少度')),for(final rarity in EquipmentRarity.values)DropdownMenuItem<EquipmentRarity?>(value:rarity,child:Text(rarity.name.toUpperCase()))],
      onChanged:(value)=>setState(()=>_rarity=value),
     ),
     if(visible.isEmpty)const Text('該当する図鑑項目なし'),
     for(final entry in visible)
      if(entry.definition case final def?)
       Card(key:ValueKey(def.id),child:ListTile(
        title:Text(def.name),
        subtitle:Text('${def.rarity.name.toUpperCase()} / ${def.category.label}\n${def.description}\n${entry.owned==0?'発見済み・現在未所持':'所持数：${entry.owned}'}'),
        leading:const Icon(Icons.check_circle_outline),
       ))
      else const Card(child:ListTile(leading:Icon(Icons.lock_outline),title:Text('？？？'),subtitle:Text('未発見'))),
    ],
   ]);
  }),
 );
}
