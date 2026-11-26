import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';

class AbyssForgeScreen extends StatefulWidget {
 const AbyssForgeScreen({super.key,required this.controller});
 final AppController controller;
 @override State<AbyssForgeScreen> createState()=>_AbyssForgeScreenState();
}

class _AbyssForgeScreenState extends State<AbyssForgeScreen>{
 bool _busy=false;
 String? _error;
 Future<void> _enhance(String id,int expectedLevel) async {
  if(_busy)return;
  setState((){_busy=true;_error=null;});
  try {
   await widget.controller.enhanceWorldItem(id,expectedLevel);
  }catch(_){
   if(mounted)setState(()=>_error='強化を完了できませんでした。装備・資産を確認してください。');
  }finally{
   if(mounted)setState(()=>_busy=false);
  }
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('深淵鍛造')),
  body:ListenableBuilder(listenable:widget.controller,builder:(context,child){
   final c=widget.controller;
   final state=c.state;
   final scaling=c.enhancementScaling;
   return ListView(padding:const EdgeInsets.all(16),children:[
    const Text('ABYSS FORGE',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:Color(0xffd5b36e))),
    Text('所持G：${state.world.gold}'),
    const Text('最大+20 / 成功率100% / 装備破壊なし'),
    if(scaling.percentPerLevel==0)const Text('強化性能補正は未有効化です。'),
    if(_busy)const LinearProgressIndicator(),
    if(_error!=null)Text(_error!),
    const SizedBox(height:12),
    if(state.inventory.equipment.isEmpty)const Text('所持装備なし'),
    for(final item in state.inventory.equipment.values)
     Card(child:Padding(padding:const EdgeInsets.all(12),child:Builder(builder:(context){
      final definition=c.equipmentCatalog.find(item.masterId);
      final recipe=c.enhancementRecipeFor(item.rarity,item.enhancement);
      final reason=c.enhancementUnavailable(item.id,item.enhancement);
      final level=item.enhancement;
      String stat(int base)=>level>=20?'${scaling.apply(base,level)}':'${scaling.apply(base,level)} → ${scaling.apply(base,level+1)}';
      return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text('${definition?.name??item.masterId} +$level',style:const TextStyle(fontWeight:FontWeight.bold)),
       Text('${item.rarity.name.toUpperCase()} / ${item.id} / ${state.inventory.equipped.containsValue(item.id)?'装着中':'未装着'}'),
       if(definition!=null&&definition.slot==item.slot&&definition.rarity==item.rarity)...[
        Text('物攻補正 ${stat(definition.physical)}'),
        Text('魔攻補正 ${stat(definition.magic)}'),
        Text('防御補正 ${stat(definition.defense)}'),
       ],
       if(recipe!=null&&level<20)...[
        Text('${c.summonRewardName(recipe.materialId)}：${state.inventory.stacks[recipe.materialId]??0} / ${recipe.quantity}'),
        Text('消費G：${recipe.gold}'),
       ],
       if(reason!=null)Text(reason),
       FilledButton(onPressed:_busy||reason!=null?null:()=>_enhance(item.id,level),child:Text(level>=20?'最大強化済み':'強化 +${level+1}')),
      ]);
     }))),
   ]);
  }),
 );
}
