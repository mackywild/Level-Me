import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../widgets/panel.dart';
class BossScreen extends StatelessWidget{
 const BossScreen({super.key,required this.controller});
 final AppController controller;
 @override Widget build(BuildContext context){
  final b=controller.state.boss;
  return ListView(padding:const EdgeInsets.fromLTRB(16,12,16,120),children:[
   Text('BOSS BATTLE',style:Theme.of(context).textTheme.headlineSmall),
   const SizedBox(height:16),
   Panel(child:Column(children:[
    const Text('🐉',style:TextStyle(fontSize:100)),
    Text(b.title,textAlign:TextAlign.center,style:Theme.of(context).textTheme.titleLarge),
    Text(b.description,textAlign:TextAlign.center),
    const SizedBox(height:16),
    Row(children:[const Text('HP'),const Spacer(),Text('${b.hp} / ${b.maxHp}')]),
    LinearProgressIndicator(value:b.hp/b.maxHp,minHeight:12,color:Colors.redAccent),
    const SizedBox(height:16),
    Text('DEFEATS ${b.defeats}  •  REWARD +${b.rewardExp} DISCIPLINE EXP'),
   ])),
   const SizedBox(height:24),
   const Text('クエスト完了で報酬EXPに応じてダメージを与えます。討伐成功で追加報酬と実績を獲得できます。'),
  ]);
 }
}
