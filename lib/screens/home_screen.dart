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
  final quests=state.quests.where((q)=>!q.archived&&!q.isCompleted).take(4);
  final now=DateTime.now();
  final days=List.generate(7,(i)=>DateTime(now.year,now.month,now.day-6+i));
  int secondsFor(DateTime day,bool workout)=>state.sessionHistory.where((h){final d=DateTime.tryParse(h['finishedAt']?.toString()??'')?.toLocal();return d!=null&&d.year==day.year&&d.month==day.month&&d.day==day.day&&(h['questId']=='starter-workout')==workout;}).fold<int>(0,(sum,h)=>sum+(h['seconds'] as int? ?? 0));
  final study=days.map((d)=>secondsFor(d,false)).toList(),workout=days.map((d)=>secondsFor(d,true)).toList();
  final maxSeconds=[60,...List.generate(7,(i)=>study[i]+workout[i])].reduce((a,b)=>a>b?a:b);
  String duration(int s)=>'${s~/60}分${s%60}秒';
  return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,120),children:[
   Text('プレイヤー情報',style:Theme.of(context).textTheme.titleMedium),
   const SizedBox(height:8),
   Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[Text('LV ${progress.level}',style:Theme.of(context).textTheme.headlineLarge),const Spacer(),Text('${state.totalExp} TOTAL EXP')]),
    LinearProgressIndicator(value:progress.ratio.clamp(0.0,1.0),minHeight:10),
    Text('${progress.expIntoLevel} / ${progress.expToNextLevel} EXP'),
   ])),
   const SizedBox(height:18),
   Text('ステータス',style:Theme.of(context).textTheme.titleMedium),
   Panel(child:Column(children:[
    for(final s in StatType.values)ListTile(
     contentPadding:EdgeInsets.zero,leading:Text(s.icon),title:Text(s.label),
     trailing:Text('ランク ${LevelCalculator.statRankFromExp(state.stats[s]??0)} · ${state.stats[s]??0} EXP'))
   ])),
   const SizedBox(height:18),
   Row(children:[
    Expanded(child:Panel(child:Text('🔥 ${controller.currentStreak}日連続'))),
    const SizedBox(width:8),
    Expanded(child:Panel(child:Text('✅ ${state.completionCount}件達成'))),
   ]),
   const SizedBox(height:18),
   Text('TODAY\'S QUEST',style:Theme.of(context).textTheme.titleMedium),
   Panel(child:Column(children:[
    for(final q in quests)ListTile(title:Text(q.id=='starter-study'?'基本情報技術者の勉強をする':q.title),subtitle:Text(q.cadence.name.toUpperCase()),trailing:Text('+${q.totalExp} EXP')),
    if(quests.isEmpty)const Text('すべてのクエストを達成しました！'),
   ])),
   const SizedBox(height:18),
   Text('ボス戦',style:Theme.of(context).textTheme.titleMedium),
   Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('🐉 ${state.boss.title}'),
    LinearProgressIndicator(value:state.boss.hp/state.boss.maxHp,color:Colors.redAccent),
    Text('HP ${state.boss.hp} / ${state.boss.maxHp}  ·  DEFEATS ${state.boss.defeats}'),
   ])),
   const SizedBox(height:18),
   Text('LIFE LOG — 直近7日間',style:Theme.of(context).textTheme.titleMedium),
   Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('学習 ${duration(study.fold<int>(0,(a,b)=>a+b))} / 運動 ${duration(workout.fold<int>(0,(a,b)=>a+b))}'),
    const SizedBox(height:12),
    for(var i=0;i<days.length;i++)Padding(padding:const EdgeInsets.only(bottom:10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Text('${days[i].month}/${days[i].day}  学習 ${duration(study[i])}・運動 ${duration(workout[i])}'),
     const SizedBox(height:4),
     LayoutBuilder(builder:(context,box)=>Row(children:[
      Container(width:box.maxWidth*study[i]/maxSeconds,height:8,color:Colors.lightBlueAccent),
      Container(width:box.maxWidth*workout[i]/maxSeconds,height:8,color:Colors.amberAccent),
     ])),
    ])),
    const Text('青：学習　黄：運動'),
    const Divider(),
    const Text('最近のセッション'),
    if(state.sessionHistory.isEmpty)const Text('記録はまだありません。'),
    for(final h in state.sessionHistory.reversed.take(5))ListTile(
     contentPadding:EdgeInsets.zero,
     leading:Icon(h['questId']=='starter-workout'?Icons.fitness_center:Icons.menu_book),
     title:Text(h['questId']=='starter-workout'?'筋トレ':'基本情報・学習'),
     subtitle:Text(h['finishedAt']?.toString().split('T').first??''),
     trailing:Text(duration(h['seconds'] as int? ?? 0)),
    ),
   ])),
   const SizedBox(height:18),
   Text('最近の実績',style:Theme.of(context).textTheme.titleMedium),
   Panel(child:state.achievements.isEmpty?const Text('実績はまだありません'):Text('🏆 ${state.achievements.first.title}')),
  ]);
 }
}
