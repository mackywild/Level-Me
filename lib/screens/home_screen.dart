import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/stat_type.dart';
import '../services/level_calculator.dart';
import '../widgets/panel.dart';
class HomeScreen extends StatelessWidget{
 const HomeScreen({super.key,required this.controller});
 final AppController controller;
 @override Widget build(BuildContext context){
  final state=controller.state,progress=LevelCalculator.fromTotalExp(state.totalExp);
  final quests=state.quests.where((q)=>!q.isCompleted).take(4);
  return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,120),children:[
   Text('PLAYER STATUS',style:Theme.of(context).textTheme.titleMedium),
   const SizedBox(height:8),
   Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[Text('LV ${progress.level}',style:Theme.of(context).textTheme.headlineLarge),const Spacer(),Text('${state.totalExp} TOTAL EXP')]),
    LinearProgressIndicator(value:progress.ratio.clamp(0.0,1.0),minHeight:10),
    Text('${progress.expIntoLevel} / ${progress.expToNextLevel} EXP'),
   ])),
   const SizedBox(height:18),
   Text('ATTRIBUTES',style:Theme.of(context).textTheme.titleMedium),
   Panel(child:Column(children:[
    for(final s in StatType.values)ListTile(
     contentPadding:EdgeInsets.zero,leading:Text(s.icon),title:Text(s.label),
     trailing:Text('RANK ${LevelCalculator.statRankFromExp(state.stats[s]??0)} · ${state.stats[s]??0} EXP'))
   ])),
   const SizedBox(height:18),
   Row(children:[
    Expanded(child:Panel(child:Text('🔥 ${controller.currentStreak} DAYS STREAK'))),
    const SizedBox(width:8),
    Expanded(child:Panel(child:Text('✅ ${state.completionCount} CLEARS'))),
   ]),
   const SizedBox(height:18),
   Text('TODAY\'S QUEST',style:Theme.of(context).textTheme.titleMedium),
   Panel(child:Column(children:[
    for(final q in quests)ListTile(title:Text(q.title),subtitle:Text(q.cadence.name.toUpperCase()),trailing:Text('+${q.totalExp} EXP')),
    if(quests.isEmpty)const Text('ALL QUESTS CLEARED!'),
   ])),
   const SizedBox(height:18),
   Text('BOSS ENCOUNTER',style:Theme.of(context).textTheme.titleMedium),
   Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('🐉 ${state.boss.title}'),
    LinearProgressIndicator(value:state.boss.hp/state.boss.maxHp,color:Colors.redAccent),
    Text('HP ${state.boss.hp} / ${state.boss.maxHp}  ·  DEFEATS ${state.boss.defeats}'),
   ])),
   const SizedBox(height:18),
   Text('RECENT ACHIEVEMENT',style:Theme.of(context).textTheme.titleMedium),
   Panel(child:state.achievements.isEmpty?const Text('NO ACHIEVEMENT YET'):Text('🏆 ${state.achievements.first.title}')),
  ]);
 }
}
