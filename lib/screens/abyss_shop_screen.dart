import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../world/abyss_shop.dart';

class AbyssShopScreen extends StatefulWidget {
 const AbyssShopScreen({super.key,required this.controller});
 final AppController controller;
 @override State<AbyssShopScreen> createState()=>_AbyssShopScreenState();
}
class _AbyssShopScreenState extends State<AbyssShopScreen>{
 bool _confirming=false;
 String? _message;
 String currency(ShopOffer offer)=>offer.currency==ShopCurrency.gold?'G':'魔晶石';
 Future<void> _purchase(ShopOffer offer) async {
  final c=widget.controller;
  final sequence=c.state.world.shopSequence;
  final generation=c.restoreGeneration;
  if(_confirming||c.shopUnavailable(offer.id,sequence)!=null)return;
  setState(()=>_confirming=true);
  try{
   final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:const Text('購入を確認'),
    content:Text('${c.summonRewardName(offer.rewardId)} × ${offer.quantity}${offer.isEquipment?' / 未強化・未付与':''}\n支払：${offer.price} ${currency(offer)}'),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('キャンセル')),
     FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('購入を確定')),
    ],
   ));
   if(!mounted||confirmed!=true)return;
   await c.purchaseWorldOffer(offer.id,sequence,expectedGeneration:generation);
   if(mounted)setState(()=>_message='購入完了：${c.summonRewardName(offer.rewardId)} × ${offer.quantity}');
  }catch(_){
   if(mounted)setState(()=>_message='購入できませんでした。残高・商品を確認してください。');
  }finally{
   if(mounted)setState(()=>_confirming=false);
  }
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('深淵商店')),
  body:ListenableBuilder(listenable:widget.controller,builder:(context,child){
   final c=widget.controller,w=c.state.world;
   return ListView(padding:const EdgeInsets.all(16),children:[
    const Text('ABYSS MARKET',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:Color(0xffd5b36e))),
    Text('所持G：${w.gold}'),
    Text('魔晶石：${w.magicCrystals}'),
    if(c.inventoryBusy)...[const LinearProgressIndicator(),const Text('所持品処理中')],
    if(_message!=null)Text(_message!),
    if(c.shopOffers.isEmpty)const Text('販売商品は未承認です'),
    for(final offer in c.shopOffers)Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Text('${c.summonRewardName(offer.rewardId)} × ${offer.quantity}'),
     if(offer.isEquipment)...[
      const Text('未強化 +0 / ランダムスキル未付与'),
      Text('所持数：${c.state.inventory.equipment.values.where((item)=>item.masterId==offer.rewardId).length}'),
     ]else Text('所持数：${c.state.inventory.stacks[offer.rewardId]??0}'),
     Text('価格：${offer.price} ${currency(offer)}'),
     if(c.shopUnavailable(offer.id,w.shopSequence) case final reason?)Text(reason),
     FilledButton(onPressed:_confirming||c.shopUnavailable(offer.id,w.shopSequence)!=null?null:()=>_purchase(offer),child:const Text('購入')),
    ]))),
   ]);
  }),
 );
}
