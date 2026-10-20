import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/fe_question.dart';
import '../services/fe_progress_store.dart';

enum FePracticeMode { all, incorrect, unseen, weak, sectionA, sectionB }

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
 bool shuffle=true;
 String? domainFilter;
 int limit=10;
 final Random _random=Random();
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
   FePracticeMode.unseen=>all.where((q)=>history[q.id]?.isEmpty??true).toList(),
   FePracticeMode.weak=>all.where((q){
    final h=history[q.id];
    return h!=null&&h.isNotEmpty&&h.where((v)=>!v).length*2>=h.length;
   }).toList(),
   FePracticeMode.sectionA=>all.where((q)=>q.section=='A').toList(),
   FePracticeMode.sectionB=>all.where((q)=>q.section=='B').toList(),
  };
  if(domainFilter!=null){questions=questions.where((q)=>q.domain==domainFilter).toList();}
  if(mode==FePracticeMode.weak){
   questions.sort((a,b){
    double score(FeQuestion q){final h=history[q.id]!;return h.where((v)=>!v).length/h.length;}
    return score(b).compareTo(score(a));
   });
  }else if(shuffle){questions.shuffle(_random);}
  if(limit>0 && questions.length>limit){questions=questions.take(limit).toList();}
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
   final domains=all.map((q)=>q.domain).toSet().toList()..sort();
   return ListView(padding:const EdgeInsets.all(20),children:[
    Text('学習済み $answered / ${all.length}問　要復習 $mistakes問'),
    const Text('演習設定を変更すると現在の演習は最初からになります。'),
    const SizedBox(height:12),
    ExpansionTile(title:const Text('分野別の学習分析'),children:[
     for(final domain in domains) Builder(builder:(context){
      final ids=all.where((q)=>q.domain==domain).map((q)=>q.id).toList();
      final attempted=ids.where((id)=>history[id]?.isNotEmpty??false).length;
      final attempts=ids.expand((id)=>history[id]??<bool>[]).toList();
      final correctAttempts=attempts.where((result)=>result).length;
      final rate=attempts.isEmpty?0.0:correctAttempts/attempts.length;
      return Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text('$domain　学習済み $attempted / ${ids.length}問　解答正答率 ${attempts.isEmpty?'—':'${(rate*100).toStringAsFixed(1)}%'}'),
       const SizedBox(height:6),
       LinearProgressIndicator(value:rate),
      ]));
     }),
    ]),
    const SizedBox(height:12),
    DropdownButtonFormField<FePracticeMode>(
     initialValue:mode,
     items:const [
      DropdownMenuItem(value:FePracticeMode.all,child:Text('全問題')),
      DropdownMenuItem(value:FePracticeMode.incorrect,child:Text('間違えた問題')),
      DropdownMenuItem(value:FePracticeMode.unseen,child:Text('未学習の問題')),
      DropdownMenuItem(value:FePracticeMode.weak,child:Text('苦手問題を優先（誤答率50%以上）')),
      DropdownMenuItem(value:FePracticeMode.sectionA,child:Text('科目A')),
      DropdownMenuItem(value:FePracticeMode.sectionB,child:Text('科目B')),
     ],
     onChanged:(v){if(v!=null){setState((){mode=v;_filter();});}},
    ),
    const SizedBox(height:12),
    DropdownButtonFormField<String>(
     key:ValueKey(domainFilter),
     initialValue:domainFilter,
     decoration:const InputDecoration(labelText:'分野で絞り込む'),
     items:[const DropdownMenuItem<String>(value:null,child:Text('全分野')),
      for(final domain in domains) DropdownMenuItem(value:domain,child:Text(domain))],
     onChanged:(v)=>setState((){domainFilter=v;_filter();}),
    ),
    SwitchListTile(title:const Text('問題をシャッフル'),value:shuffle,onChanged:(v)=>setState((){shuffle=v;_filter();})),
    DropdownButtonFormField<int>(
     initialValue:limit,
     decoration:const InputDecoration(labelText:'1回の演習問題数'),
     items:const [
      DropdownMenuItem(value:10,child:Text('10問')),
      DropdownMenuItem(value:20,child:Text('20問')),
      DropdownMenuItem(value:0,child:Text('全件')),
     ],
     onChanged:(v){if(v!=null){setState((){limit=v;_filter();});}},
    ),
    const SizedBox(height:16),
    if(questions.isEmpty)
     const Text('この条件に該当する問題はありません。')
    else if(index>=questions.length)...[
     Text('演習完了　$correct / ${questions.length}',style:Theme.of(context).textTheme.headlineSmall),
     Text('今回の正答率 ${(correct/questions.length*100).toStringAsFixed(1)}%'),
     const SizedBox(height:8),
     Text('誤答した問題は「間違えた問題」から復習できます。'),
     const SizedBox(height:12),
     FilledButton.tonal(onPressed:()=>setState((){mode=FePracticeMode.incorrect;_filter();}),child:const Text('間違えた問題を復習する')),

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
