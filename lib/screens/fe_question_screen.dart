import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/fe_question.dart';
import '../services/fe_progress_store.dart';

enum FePracticeMode { all, incorrect, sectionA, sectionB }

class FeQuestionScreen extends StatefulWidget {
 const FeQuestionScreen({super.key});
 @override State<FeQuestionScreen> createState()=>_FeQuestionScreenState();
}
class _FeQuestionScreenState extends State<FeQuestionScreen>{
 final _store=FeProgressStore();
 late Future<void> _loading;
 List<FeQuestion> all=[];
 Map<String,List<bool>> history={};
 List<FeQuestion> questions=[];
 FePracticeMode mode=FePracticeMode.all;
 int index=0,correct=0;
 int? selected;
 bool saving=false;
 @override void initState(){super.initState();_loading=_load();}
 Future<void> _load() async {
  final raw=await rootBundle.loadString('assets/questions/fe_seed.json');
  all=(jsonDecode(raw) as List).map((e)=>FeQuestion.fromJson(e as Map<String,dynamic>)).toList();
  history=await _store.load();
  _filter();
 }
 void _filter(){
  questions=switch(mode){
   FePracticeMode.all=>List.of(all),
   FePracticeMode.incorrect=>all.where((q)=>history[q.id]?.lastOrNull==false).toList(),
   FePracticeMode.sectionA=>all.where((q)=>q.section=='A').toList(),
   FePracticeMode.sectionB=>all.where((q)=>q.section=='B').toList(),
  };
  index=0;correct=0;selected=null;
 }
 Future<void> _answer(int choice,FeQuestion question) async {
  if(selected!=null||saving)return;
  setState(()=>saving=true);
  final result=choice==question.answerIndex;
  try{
   await _store.record(question.id,result);
   history.putIfAbsent(question.id,()=>[]).add(result);
   if(!mounted)return;
   setState((){selected=choice;if(result)correct++;saving=false;});
  }catch(error){
   if(!mounted)return;
   setState(()=>saving=false);
   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('解答履歴を保存できません: $error')));
  }
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('基本情報・問題演習')),
  body:FutureBuilder<void>(future:_loading,builder:(context,snapshot){
   if(snapshot.hasError){return Center(child:Text('問題読込失敗: ${snapshot.error}'));}
   if(snapshot.connectionState!=ConnectionState.done){return const Center(child:CircularProgressIndicator());}
   final answered=history.values.where((h)=>h.isNotEmpty).length;
   final mistakes=all.where((q)=>history[q.id]?.lastOrNull==false).length;
   return ListView(padding:const EdgeInsets.all(20),children:[
    Text('学習済み $answered / ${all.length}問　要復習 $mistakes問'),
    const SizedBox(height:12),
    DropdownButtonFormField<FePracticeMode>(
     initialValue:mode,
     items:const [
      DropdownMenuItem(value:FePracticeMode.all,child:Text('全問題')),
      DropdownMenuItem(value:FePracticeMode.incorrect,child:Text('間違えた問題')),
      DropdownMenuItem(value:FePracticeMode.sectionA,child:Text('科目A')),
      DropdownMenuItem(value:FePracticeMode.sectionB,child:Text('科目B')),
     ],
     onChanged:(v){if(v!=null){setState((){mode=v;_filter();});}},
    ),
    const SizedBox(height:16),
    if(questions.isEmpty)
     const Text('この条件に該当する問題はありません。')
    else if(index>=questions.length)...[
     Text('演習完了　$correct / ${questions.length}',style:Theme.of(context).textTheme.headlineSmall),
     const SizedBox(height:12),
     FilledButton(onPressed:()=>setState(_filter),child:const Text('もう一度')),
    ]else ...[
     LinearProgressIndicator(value:index/questions.length),
     const SizedBox(height:12),
     Text('科目${questions[index].section} · ${questions[index].domain}　${index+1}/${questions.length}'),
     const SizedBox(height:16),
     Text(questions[index].stem,style:Theme.of(context).textTheme.titleLarge),
     const SizedBox(height:16),
     for(var i=0;i<questions[index].options.length;i++)
      Padding(padding:const EdgeInsets.only(bottom:8),child:OutlinedButton(
       onPressed:selected==null&&!saving?()=>_answer(i,questions[index]):null,
       child:Align(alignment:Alignment.centerLeft,child:Padding(
        padding:const EdgeInsets.symmetric(vertical:12),
        child:Text('${i+1}. ${questions[index].options[i]}'))))),
     if(selected!=null)...[
      const SizedBox(height:12),
      Text(selected==questions[index].answerIndex?'正解！':'不正解',style:Theme.of(context).textTheme.titleMedium),
      Text('正解：${questions[index].options[questions[index].answerIndex]}'),
      const SizedBox(height:8),
      Text(questions[index].explanation),
      const SizedBox(height:16),
      FilledButton(onPressed:()=>setState((){index++;selected=null;}),child:const Text('次の問題')),
     ],
    ],
   ]);
  }));
}
