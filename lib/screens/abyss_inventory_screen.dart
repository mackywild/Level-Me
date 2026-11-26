import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../world/abyss_inventory.dart';
import '../world/abyss_dismantle.dart';
import '../world/abyss_consumable.dart';

class AbyssInventoryScreen extends StatefulWidget {
 const AbyssInventoryScreen({super.key,required this.controller});
 final AppController controller;
 @override State<AbyssInventoryScreen> createState()=>_AbyssInventoryScreenState();
}
class _AbyssInventoryScreenState extends State<AbyssInventoryScreen>{
 String _query='';
 bool _favoritesOnly=false;
 bool _materials=false;
 EquipmentRarity? _rarity;
 String? _message;
 bool _confirming=false;
 String _rewardText(DismantleRecipe recipe)=>[
  if(recipe.quantity>0)'${widget.controller.summonRewardName(recipe.materialId)} × ${recipe.quantity}',
  for(final entry in recipe.refundedMaterials.entries)'還元：${widget.controller.summonRewardName(entry.key)} × ${entry.value}',
  if(recipe.magicCrystals>0)'魔晶石 × ${recipe.magicCrystals}',
 ].join(' / ');
 Future<void> _favorite(EquipmentInstance item) async {
  if(widget.controller.inventoryBusy||_confirming)return;
  try {
   await widget.controller.setWorldEquipmentFavorite(item.id,!item.favorite);
   if(mounted)setState(()=>_message=item.favorite?'お気に入りを解除しました':'お気に入りに登録しました');
  }catch(_){
   if(mounted)setState(()=>_message='保護状態を保存できませんでした');
  }
 }
 Future<void> _dismantle(EquipmentInstance item) async {
  final c=widget.controller;
  if(_confirming||c.dismantleUnavailable(item.id,item.enhancement)!=null)return;
  final recipe=c.dismantlePreview(item);
  if(recipe==null)return;
  final name=c.summonRewardName(item.masterId);
  final generation=c.restoreGeneration;
  setState(()=>_confirming=true);
  try {
   final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
    title:const Text('装備を分解しますか？'),
    content:Text('$name +${item.enhancement} / ${item.id}\n獲得：${_rewardText(recipe)}\n分解すると装備を失います。この操作は取り消せません。'),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('キャンセル')),
     FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('分解を確定')),
    ],
   ));
   if(!mounted||confirmed!=true)return;
   final reward=await c.dismantleWorldItem(item.id,item.enhancement,expectedGeneration:generation,expectedItem:item);
   if(mounted)setState(()=>_message='分解完了：${_rewardText(reward)}');
  }catch(_){
   if(mounted)setState(()=>_message='分解できませんでした。装備・保護状態を確認してください。');
  }finally{
   if(mounted)setState(()=>_confirming=false);
  }
 }
 String _target(RecoveryTarget target)=>switch(target){
  RecoveryTarget.hp=>'HP',
  RecoveryTarget.physical=>'物理エネルギー',
  RecoveryTarget.magic=>'魔法エネルギー',
  RecoveryTarget.all=>'HP・物理・魔法（合計）',
 };
 Future<void> _recover(RecoveryItem item) async {
  final c=widget.controller;
  if(_confirming)return;
  try{
   final evaluation=c.evaluateRecovery(item.id);
   final amount=evaluation.amount;
   if(amount==null){
    if(mounted)setState(()=>_message=evaluation.reason);
    return;
   }
   final sequence=c.state.world.itemUseSequence;
   final generation=c.restoreGeneration;
   setState(()=>_confirming=true);
   final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:const Text('回復アイテムを使用しますか？'),
    content:Text('${item.name} × 1\n${_target(item.target)}：回復予定 $amount\n自然回復により確定時の回復量が変わる場合があります。'),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('キャンセル')),
     FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('使用を確定')),
    ],
   ));
   if(!mounted||confirmed!=true)return;
   final recovered=await c.useWorldRecoveryItem(item.id,sequence,expectedGeneration:generation);
   if(mounted)setState(()=>_message='${_target(item.target)}を$recovered 回復しました');
  }catch(_){
   if(mounted)setState(()=>_message='使用できませんでした。現在の回復状態・所持数を確認してください。');
  }finally{
   if(mounted)setState(()=>_confirming=false);
  }
 }
 bool _matches(String id,String name)=>id.toLowerCase().contains(_query)||name.toLowerCase().contains(_query);
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('深淵所持品')),
  body:ListenableBuilder(listenable:widget.controller,builder:(context,child){
   final c=widget.controller;
   final inv=c.state.inventory;
   final locked=c.inventoryBusy||_confirming||!c.ready||c.state.world.battle!=null;
   final items=inv.equipment.values.where((item)=>
    (!_favoritesOnly||item.favorite)&&(_rarity==null||item.rarity==_rarity)&&
    (_matches(item.masterId,c.summonRewardName(item.masterId))||item.id.toLowerCase().contains(_query))).toList()
    ..sort((a,b){final rarity=b.rarity.index.compareTo(a.rarity.index);return rarity!=0?rarity:a.id.compareTo(b.id);});
   final stacks=inv.stacks.entries.where((entry)=>_matches(entry.key,c.summonRewardName(entry.key))).toList()
    ..sort((a,b)=>a.key.compareTo(b.key));
   return ListView(padding:const EdgeInsets.all(16),children:[
    const Text('ABYSS INVENTORY',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:Color(0xffd5b36e))),
    Text('装備 ${inv.equipment.length} 個 / 素材 ${inv.stacks.length} 種'),
    TextField(decoration:const InputDecoration(labelText:'名前・IDで検索'),onChanged:(value)=>setState(()=>_query=value.trim().toLowerCase())),
    Wrap(spacing:8,children:[
     ChoiceChip(label:const Text('装備'),selected:!_materials,onSelected:(_)=>setState(()=>_materials=false)),
     ChoiceChip(label:const Text('素材・物資'),selected:_materials,onSelected:(_)=>setState(()=>_materials=true)),
    ]),
    if(c.inventoryBusy)...[const LinearProgressIndicator(),const Text('所持品処理中')],
    if(_message!=null)Text(_message!),
    if(_materials)...[
     if(stacks.isEmpty)const Text('該当する素材なし'),
     for(final entry in stacks)
      if(c.recoveryItem(entry.key) case final item?)
       Builder(builder:(context){
        final evaluation=c.evaluateRecovery(item.id);
        return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${item.name} × ${entry.value}'),
        Text('${_target(item.target)} 最大値の${item.percent}%回復'),
        if(evaluation.reason case final reason?)Text(reason)
        else Text('回復予定：${evaluation.amount}'),
        FilledButton(onPressed:locked||evaluation.amount==null?null:()=>_recover(item),child:const Text('使用')),
       ])));
       })
      else ListTile(title:Text(c.summonRewardName(entry.key)),subtitle:Text(entry.key),trailing:Text('× ${entry.value}')),
    ]else...[
     FilterChip(label:const Text('お気に入りのみ'),selected:_favoritesOnly,onSelected:(value)=>setState(()=>_favoritesOnly=value)),
     DropdownButton<EquipmentRarity?>(
      value:_rarity,
      items:[const DropdownMenuItem<EquipmentRarity?>(value:null,child:Text('全希少度')),for(final rarity in EquipmentRarity.values)DropdownMenuItem<EquipmentRarity?>(value:rarity,child:Text(rarity.name.toUpperCase()))],
      onChanged:(value)=>setState(()=>_rarity=value),
     ),
     if(items.isEmpty)const Text('該当する装備なし'),
     for(final item in items)Card(key:ValueKey(item.id),child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('${c.summonRewardName(item.masterId)} +${item.enhancement}',style:const TextStyle(fontWeight:FontWeight.bold)),
      Text('${item.rarity.name.toUpperCase()} / ${item.slot.name} / ${item.id}'),
      if(inv.equipped.containsValue(item.id))const Text('装着中'),
      if(item.favorite)const Text('お気に入り保護中'),
      if(item.enhancement>0&&!inv.hasCompleteEnhancementHistory(item))const Text('強化済み保護中'),
      if((c.dismantlePreview(item)??c.dismantleRecipe(item.rarity)) case final recipe?)
       Text('分解報酬：${_rewardText(recipe)}'),
      if(c.dismantleUnavailable(item.id,item.enhancement) case final reason?)Text(reason),
      Wrap(spacing:8,children:[
       OutlinedButton(onPressed:locked?null:()=>_favorite(item),child:Text(item.favorite?'お気に入り解除':'お気に入り登録')),
       FilledButton(onPressed:locked||c.dismantleUnavailable(item.id,item.enhancement)!=null?null:()=>_dismantle(item),child:const Text('分解')),
      ]),
     ]))),
    ],
   ]);
  }),
 );
}
