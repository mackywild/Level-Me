import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/fe_question.dart';

class FeQuestionScreen extends StatefulWidget {
 const FeQuestionScreen({super.key});
 @override State<FeQuestionScreen> createState()=>_FeQuestionScreenState();
}
class _FeQuestionScreenState extends State<FeQuestionScreen>{
 late final Future<List<FeQuestion>> _questions=_load();
 int index=0,correct=0;
 int? selected;
 Future<List<FeQuestion>> _load() async{
  final raw=await rootBundle.loadString('assets/questions/fe_seed.json');
  return (jsonDecode(raw) as List).map((e)=>FeQuestion.fromJson(e as Map<String,dynamic>)).toList();
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('基本情報・問題演習')),
  body:FutureBuilder<List<FeQuestion>>(future:_questions,builder:(context,snapshot){
   if(snapshot.hasError)return Center(child:Text('問題読込失敗: ${snapshot.error}'));
   if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
   final questions=snapshot.data!;
   if(index>=questions.length)return Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
    Text('演習完了  $correct / ${questions.length}',style:Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height:16),
    FilledButton(onPressed:()=>setState((){index=0;correct=0;selected=null;}),child:const Text('もう一度'))
   ]));
   final q=questions[index];
   return ListView(padding:const EdgeInsets.all(20),children:[
    Text('科目${q.section} · ${q.domain}  |  ${index+1}/${questions.length}'),
    const SizedBox(height:16),
    Text(q.stem,style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:16),
    for(var i=0;i<q.options.length;i++)Padding(padding:const EdgeInsets.only(bottom:8),
     child:OutlinedButton(onPressed:selected==null?()=>setState((){selected=i;if(i==q.answerIndex)correct++;}):null,
      child:Align(alignment:Alignment.centerLeft,child:Padding(padding:const EdgeInsets.symmetric(vertical:12),
       child:Text('${i+1}. ${q.options[i]}'))))),
    if(selected!=null)...[
     const SizedBox(height:12),
     Text(selected==q.answerIndex?'正解！':'不正解',style:Theme.of(context).textTheme.titleMedium),
     Text('正解：${q.options[q.answerIndex]}'),
     Text(q.explanation),
     const SizedBox(height:16),
     FilledButton(onPressed:()=>setState((){index++;selected=null;}),child:const Text('次の問題')),
    ]
   ]);
  }));
}
