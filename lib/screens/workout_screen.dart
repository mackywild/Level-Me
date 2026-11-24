import 'dart:async';
import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/quest.dart';

class WorkoutScreen extends StatefulWidget {
 const WorkoutScreen({super.key,required this.controller,required this.quest});
 final AppController controller;
 final Quest quest;
 @override State<WorkoutScreen> createState()=>_WorkoutScreenState();
}
class _WorkoutScreenState extends State<WorkoutScreen> with WidgetsBindingObserver {
 final Stopwatch _watch=Stopwatch();
 int _restored=0;
 bool _busy=false,_finished=false;
 Timer? _ticker;
 int get _seconds=>_restored+_watch.elapsed.inSeconds;
 String get _clock=>'${(_seconds~/3600).toString().padLeft(2,'0')}:${((_seconds~/60)%60).toString().padLeft(2,'0')}:${(_seconds%60).toString().padLeft(2,'0')}';
 @override void initState(){
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  _restored=widget.controller.sessionFor(widget.quest.id)?['seconds'] as int? ?? 0;
  _ticker=Timer.periodic(const Duration(seconds:1),(timer){
   if(mounted)setState((){});
   if(_watch.isRunning&&timer.tick%10==0)_save();
  });
 }
 Future<void> _save() async {
  if(_finished||_busy||_seconds==0)return;
  try {await widget.controller.saveSession(widget.quest.id,{'seconds':_seconds});}
  catch(error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('途中記録の保存失敗: $error')));}
 }
 @override void didChangeAppLifecycleState(AppLifecycleState state){
  if(state!=AppLifecycleState.resumed){_watch.stop();_save();}
  if(mounted)setState((){});
 }
 @override void dispose(){
  _ticker?.cancel();_watch.stop();WidgetsBinding.instance.removeObserver(this);_save();super.dispose();
 }
 Future<void> _finish() async {
  if(_busy||_seconds<60)return;
  _watch.stop();
  setState(()=>_busy=true);
  try {
   await widget.controller.completeQuest(widget.quest,activeSeconds:_seconds);
   _finished=true;
   if(mounted)Navigator.pop(context);
  } catch(error){
   if(!mounted)return;
   setState(()=>_busy=false);
   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('保存失敗: $error')));
  }
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('筋トレセッション')),
  body:ListView(padding:const EdgeInsets.all(24),children:[
   const Icon(Icons.fitness_center,size:72,color:Colors.amberAccent),
   const SizedBox(height:24),
   Text(_clock,textAlign:TextAlign.center,style:const TextStyle(fontSize:48,fontWeight:FontWeight.bold)),
   Text(_watch.isRunning?'運動中':_seconds>0?'一時停止中':'開始待ち',textAlign:TextAlign.center),
   const SizedBox(height:24),
   FilledButton.icon(onPressed:_busy?null:(){setState((){_watch.isRunning?_watch.stop():_watch.start();});_save();},icon:Icon(_watch.isRunning?Icons.pause:Icons.play_arrow),label:Text(_watch.isRunning?'PAUSE':_seconds>0?'RESUME':'START')),
   const SizedBox(height:12),
   OutlinedButton(onPressed:_busy||_seconds<60?null:_finish,child:const Text('運動を終了して記録')),
   const SizedBox(height:16),
   const Text('1分以上で記録できます。25分を標準報酬とし、1回の報酬計算は120分まで。同一日の追加運動も時間を記録できます。'),
  ]),
 );
}
