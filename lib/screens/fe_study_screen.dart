import 'dart:async';
import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/quest.dart';
import '../models/stat_type.dart';

/// Timed FE learning. EXP is based on elapsed active study time, not questions.
class FeStudyScreen extends StatefulWidget {
 const FeStudyScreen({super.key, required this.controller, required this.quest});
 final AppController controller;
 final Quest quest;
 @override State<FeStudyScreen> createState()=>_FeStudyScreenState();
}
class _FeStudyScreenState extends State<FeStudyScreen> {
 final Stopwatch _watch=Stopwatch();
 Timer? _ticker;
 bool _finished=false;
 int _incorrect=0;
 int _flagged=0;
 @override void initState(){
  super.initState();
  _ticker=Timer.periodic(const Duration(seconds:1),(_){if(mounted)setState((){});});
 }
 @override void dispose(){_ticker?.cancel();_watch.stop();super.dispose();}
 String get _clock {
  final s=_watch.elapsed.inSeconds;
  return '${(s~/3600).toString().padLeft(2,'0')}:${((s~/60)%60).toString().padLeft(2,'0')}:${(s%60).toString().padLeft(2,'0')}';
 }
 Future<void> _finish() async {
  if(_finished)return;
  _watch.stop();
  final seconds=_watch.elapsed.inSeconds;
  if(seconds<60){
   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('学習時間が1分未満です。1分以上学習してから終了してください。')));
   return;
  }
  setState(()=>_finished=true);
  // A review quest is only awarded when actually completed in a later session.
  if(_incorrect+_flagged>0){
   await widget.controller.addQuest(
    title:'基本情報：見直し（誤答 $_incorrect 件・要確認 $_flagged 件）',
    cadence:QuestCadence.oneTime,
    rewards:const [QuestReward(stat:StatType.intelligence,exp:10),
      QuestReward(stat:StatType.discipline,exp:3)]);
  }
  // Reward the original daily quest only for a measured study session.
  await widget.controller.completeQuest(widget.quest);
  if(mounted)Navigator.of(context).pop();
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('基本情報技術者・学習セッション')),
  body:ListView(padding:const EdgeInsets.all(20),children:[
   const Text('STUDY TIMER',style:TextStyle(letterSpacing:3)),
   const SizedBox(height:16),
   Center(child:Text(_clock,style:const TextStyle(fontSize:44,fontWeight:FontWeight.bold,fontFeatures:[FontFeature.tabularFigures()]))),
   const SizedBox(height:12),
   Text(_watch.isRunning?'学習中':_watch.elapsed==Duration.zero?'開始待ち':'一時停止中',textAlign:TextAlign.center),
   const SizedBox(height:20),
   FilledButton.icon(onPressed:()=>setState((){_watch.isRunning?_watch.stop():_watch.start();}),
    icon:Icon(_watch.isRunning?Icons.pause:Icons.play_arrow),
    label:Text(_watch.isRunning?'PAUSE':'START / RESUME')),
   const SizedBox(height:20),
   const Text('学習終了時に、誤答・要確認の件数を記録してください。見直しクエストが作成されます。'),
   const SizedBox(height:14),
   _counter('誤答',_incorrect,(v)=>setState(()=>_incorrect=v)),
   _counter('要確認',_flagged,(v)=>setState(()=>_flagged=v)),
   const SizedBox(height:18),
   FilledButton(onPressed:_finished?null:_finish,child:const Text('学習を終了して記録')),
   const SizedBox(height:16),
   const Text('※問題集は現在制作中です。この画面は時間計測と見直しタスク生成の先行実装です。'),
  ]),
 );
 Widget _counter(String label,int value,ValueChanged<int> change)=>Row(children:[
  Expanded(child:Text(label)),
  IconButton(onPressed:value>0?()=>change(value-1):null,icon:const Icon(Icons.remove_circle_outline)),
  Text('$value'),
  IconButton(onPressed:()=>change(value+1),icon:const Icon(Icons.add_circle_outline)),
 ]);
}
