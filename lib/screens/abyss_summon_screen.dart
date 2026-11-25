import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../world/abyss_inventory.dart';
import '../world/abyss_summon.dart';

class AbyssSummonScreen extends StatefulWidget {
 const AbyssSummonScreen({super.key,required this.controller});
 final AppController controller;
 @override State<AbyssSummonScreen> createState()=>_AbyssSummonScreenState();
}
class _AbyssSummonScreenState extends State<AbyssSummonScreen>{
 bool _busy=false;
 SummonPool _pool=SummonPool.equipment;
 String? _error;
 String _label(SummonPool pool)=>switch(pool){
  SummonPool.equipment=>'武装召喚',
  SummonPool.relic=>'魔遺物召喚',
  SummonPool.supplies=>'物資召喚',
 };
 Future<void> _summon(SummonPool pool,int count,int sequence) async {
  if(_busy)return;
  setState((){_busy=true;_error=null;});
  try {
   await widget.controller.summonWorldItems(pool,count,sequence);
  } catch (_) {
   if(mounted)setState(()=>_error='召喚を完了できませんでした。保留状態と券残高を確認してください。');
  } finally {
   if(mounted)setState(()=>_busy=false);
  }
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('深淵召喚')),
  body:ListenableBuilder(listenable:widget.controller,builder:(context,child){
   final c=widget.controller;
   final state=c.state;
   final pending=state.summon.pending;
   final latest=state.summon.latest;
   final pool=pending?.pool??_pool;
   final highest=c.summonHighestUnlocked;
   final weights=c.summonWeights;
   final tickets=pool==SummonPool.supplies?state.world.supplyTickets:state.world.summonTickets;
   final cost=SummonPolicy.costs[pool]!;
   final counters=state.summon.misses(pool);
   final sequence=state.summon.sequence;
   return ListView(padding:const EdgeInsets.all(16),children:[
    const Text('ABYSS SUMMON',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:Color(0xffd5b36e))),
    Text('武装券 ${state.world.summonTickets} / 物資券 ${state.world.supplyTickets}'),
    const SizedBox(height:12),
    Wrap(spacing:8,runSpacing:8,children:[
     for(final option in SummonPool.values)
      ChoiceChip(label:Text(_label(option)),selected:pool==option,onSelected:_busy||pending!=null?null:(_)=>setState((){_pool=option;_error=null;})),
    ]),
    const SizedBox(height:12),
    Text('${_label(pool)} / 所持券 ${tickets}枚'),
    if(pending!=null)...[
     Text('保留中の召喚：${pending.rewards.length}回（取引 ${pending.sequence}）'),
     const Text('同じ条件でのみ再開できます。未確定の排出結果は表示しません。'),
     _action(c,pool,pending.rewards.length,sequence,'保留中の召喚を再開'),
    ]else...[
     _action(c,pool,1,sequence,'単発召喚（${cost}券）'),
     _action(c,pool,10,sequence,'10連召喚（${cost*10}券）'),
    ],
    if(_busy)const LinearProgressIndicator(),
    if(_error!=null)Text(_error!),
    const Divider(),
    Text('解放済み希少度：${highest.name.toUpperCase()}まで'),
    const Text('通常抽選の希少度確率（天井・10連保証を除く）'),
    for(final rarity in EquipmentRarity.values)
     ListTile(dense:true,title:Text(rarity.name.toUpperCase()),trailing:Text(rarity.index>highest.index?'未解放':'${(weights[rarity.index]/100).toStringAsFixed(2)}%')),
    const Divider(),
    const Text('天井進捗'),
    for(final entry in SummonPolicy.pityLimits.entries)
     ListTile(dense:true,title:Text(entry.key.name.toUpperCase()),subtitle:entry.key.index>highest.index?const Text('未解放'):LinearProgressIndicator(value:(counters[entry.key]??0)/entry.value),trailing:Text('${counters[entry.key]??0} / ${entry.value}')),
    Text(highest.index>=EquipmentRarity.sr.index?'10連でSR以上を最低1枠保証':'SR解放後に10連保証が有効になります'),
    const Divider(),
    const Text('直近の確定済み召喚結果',style:TextStyle(fontWeight:FontWeight.bold)),
    if(latest==null)const Text('召喚履歴なし')else...[
     Text('${_label(latest.pool)} / 取引 ${latest.sequence}'),
     for(final reward in latest.rewards)
      ListTile(dense:true,title:Text(c.equipmentCatalog.find(reward.masterId)?.name??reward.masterId),subtitle:reward.instanceId==null?null:Text(reward.instanceId!),trailing:Text(reward.rarity.name.toUpperCase())),
    ],
   ]);
  }),
 );
 Widget _action(AppController c,SummonPool pool,int count,int sequence,String label){
  final reason=c.summonUnavailable(pool,count);
  return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
   FilledButton(onPressed:_busy||reason!=null?null:()=>_summon(pool,count,sequence),child:Text(label)),
   if(reason!=null)Text(reason),
  ]);
 }
}
