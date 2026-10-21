import 'dart:async';
import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/quest.dart';
import '../models/stat_type.dart';
import 'fe_question_screen.dart';

/// Timed study flow launched from the daily study quest.
class FeStudyScreen extends StatefulWidget {
 const FeStudyScreen({super.key, required this.controller, required this.quest,
  this.reviewOnly=false});
 final AppController controller;
 final Quest quest;
 final bool reviewOnly;
 static const reviewQuestPrefix='基本情報：見直し';
 @override State<FeStudyScreen> createState()=>_FeStudyScreenState();
}

class _FeStudyScreenState extends State<FeStudyScreen> {
 final Stopwatch _watch=Stopwatch();
 final Set<String> _answeredIds={};
 final Set<String> _incorrectIds={};
 final Set<String> _flaggedIds={};
 Timer? _ticker;
 bool _finished=false;
 bool _openingQuestions=false;

 bool get _isReviewQuest=>widget.reviewOnly||widget.quest.title.startsWith(FeStudyScreen.reviewQuestPrefix);

 @override void initState(){
  super.initState();
  _ticker=Timer.periodic(const Duration(seconds:1),(_){if(mounted)setState((){});});
 }

 @override void dispose(){_ticker?.cancel();_watch.stop();super.dispose();}

 String get _clock {
  final s=_watch.elapsed.inSeconds;
  return '${(s~/3600).toString().padLeft(2,'0')}:${((s~/60)%60).toString().padLeft(2,'0')}:${(s%60).toString().padLeft(2,'0')}';
 }

 Future<void> _openQuestions() async {
  if(_openingQuestions||_finished)return;
  setState(()=>_openingQuestions=true);
  final route = MaterialPageRoute<void>(
   builder: (_) => FeQuestionScreen(
   initialMode:_isReviewQuest?FePracticeMode.review:FePracticeMode.all,
   initialQuestionIds:widget.quest.reviewQuestionIds.isEmpty
    ?null:widget.quest.reviewQuestionIds.toSet(),
   onAnswerRecorded:(id,correct){
    if(!mounted)return;
    setState((){
     _answeredIds.add(id);
     if(!correct)_incorrectIds.add(id);
    });
   },
   onReviewFlagChanged:(id,flagged){
    if(!mounted)return;
    setState((){
     if(flagged){_flaggedIds.add(id);}else{_flaggedIds.remove(id);}
    });
   },
   ),
  );
  await Navigator.of(context).push<void>(route);
  if(mounted)setState(()=>_openingQuestions=false);
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
  final reviewIds={..._incorrectIds,..._flaggedIds};
  if(reviewIds.isNotEmpty){
   await widget.controller.addQuest(
    title:'${FeStudyScreen.reviewQuestPrefix}（対象 ${reviewIds.length}問）',
    cadence:QuestCadence.oneTime,
    reviewQuestionIds:reviewIds.toList()..sort(),
    rewards:const [QuestReward(stat:StatType.intelligence,exp:10),
      QuestReward(stat:StatType.discipline,exp:3)]);
  }
  await widget.controller.completeQuest(widget.quest);
  if(mounted)Navigator.of(context).pop();
 }

 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:Text(_isReviewQuest?'基本情報・復習セッション':'基本情報・デイリー学習')),
  body:ListView(padding:const EdgeInsets.all(20),children:[
   const Text('TODAY\'S STUDY QUEST',style:TextStyle(letterSpacing:3)),
   const SizedBox(height:12),
   Text('学習時間を記録しながら、科目A・科目Bの問題演習に取り組めます。問題数は達成条件ではありません。'),
   const SizedBox(height:20),
   Center(child:Text(_clock,style:const TextStyle(fontSize:44,fontWeight:FontWeight.bold))),
   const SizedBox(height:12),
   Text(_watch.isRunning?'学習中':_watch.elapsed==Duration.zero?'開始待ち':'一時停止中',textAlign:TextAlign.center),
   const SizedBox(height:20),
   FilledButton.icon(onPressed:()=>setState((){_watch.isRunning?_watch.stop():_watch.start();}),
    icon:Icon(_watch.isRunning?Icons.pause:Icons.play_arrow),
    label:Text(_watch.isRunning?'PAUSE':'START / RESUME')),
   const SizedBox(height:20),
   Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(_isReviewQuest?'今回の復習':'今日の問題演習',style:Theme.of(context).textTheme.titleMedium),
    const SizedBox(height:8),
    Text('解答 ${_answeredIds.length}問　誤答 ${_incorrectIds.length}問　要確認 ${_flaggedIds.length}問'),
    const SizedBox(height:12),
    SizedBox(width:double.infinity,child:OutlinedButton.icon(
     onPressed:_finished||_openingQuestions?null:_openQuestions,
     icon:const Icon(Icons.quiz),
     label:Text(_openingQuestions?'演習を開いています…':_isReviewQuest?'復習問題を解く':'問題演習を始める'))),
   ]))),
   const SizedBox(height:12),
   const Text('学習時間はタイマーが動いている間だけ計測します。問題に「あとで見直す」を付けると、終了時に復習タスクへ引き継がれます。'),
   const SizedBox(height:18),
   FilledButton(onPressed:_finished?null:_finish,child:const Text('学習を終了して記録')),
  ]),
 );
}
