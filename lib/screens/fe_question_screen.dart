import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/fe_question.dart';
import '../services/fe_progress_store.dart';
import '../services/fe_question_selector.dart';

enum FePracticeMode { all, incorrect, review, unseen, weak, sectionA, sectionB, examB }

class FeQuestionScreen extends StatefulWidget {
 const FeQuestionScreen({super.key, this.initialMode=FePracticeMode.all,
  this.initialQuestionIds, this.onAnswerRecorded, this.onReviewFlagChanged});
 final FePracticeMode initialMode;
 final Set<String>? initialQuestionIds;
 final void Function(String id,bool correct)? onAnswerRecorded;
 final void Function(String id,bool flagged)? onReviewFlagChanged;
 @override State<FeQuestionScreen> createState()=>_FeQuestionScreenState();
}
class _FeQuestionScreenState extends State<FeQuestionScreen>{
 final _store=FeProgressStore();
 late Future<void> _loading;
 List<FeQuestion> all=[];
 Map<String,List<bool>> history={};
 Set<String> flaggedIds={};
 List<FeQuestion> questions=[];
 late FePracticeMode mode;
 int index=0,correct=0;
 int? selected;
 bool saving=false;
 bool shuffle=true;
 String? domainFilter;
 int limit=10;
 final Random _random=Random();
 @override void initState(){
  super.initState();
  mode=widget.initialMode;
  if(widget.initialQuestionIds!=null)limit=0;
  _loading=_load();
 }
 Future<void> _load() async {
  final raw=await rootBundle.loadString('assets/questions/fe_seed.json');
  all=(jsonDecode(raw) as List).map((e)=>FeQuestion.fromJson(e as Map<String,dynamic>)).toList();
  history=await _store.load();
  flaggedIds=await _store.loadFlags();
  _filter();
 }
 void _filter(){
  questions=switch(mode){
   FePracticeMode.all=>List.of(all),
   FePracticeMode.incorrect=>all.where((q)=>history[q.id]?.lastOrNull==false).toList(),
   FePracticeMode.review=>FeQuestionSelector.selectForReview(
    all,history,flaggedIds,targetIds:widget.initialQuestionIds),
   FePracticeMode.unseen=>all.where((q)=>history[q.id]?.isEmpty??true).toList(),
   FePracticeMode.weak=>all.where((q){
    final h=history[q.id];
    return h!=null&&h.isNotEmpty&&h.where((v)=>!v).length*2>=h.length;
   }).toList(),
   FePracticeMode.sectionA=>all.where((q)=>q.section=='A').toList(),
   FePracticeMode.sectionB=>all.where((q)=>q.section=='B').toList(),
   FePracticeMode.examB=>FeQuestionSelector.selectBExamSet(all,random:_random),
  };
  if(domainFilter!=null&&mode!=FePracticeMode.examB){questions=questions.where((q)=>q.domain==domainFilter).toList();}
  if(mode==FePracticeMode.weak){
   questions.sort((a,b){
    double score(FeQuestion q){final h=history[q.id]!;return h.where((v)=>!v).length/h.length;}
    return score(b).compareTo(score(a));
   });
  }else if(shuffle||mode==FePracticeMode.examB){questions.shuffle(_random);}
  if(mode!=FePracticeMode.examB&&limit>0 && questions.length>limit){questions=questions.take(limit).toList();}
  index=0;correct=0;selected=null;
 }
 Future<void> _answer(int choice,FeQuestion question) async {
  if(selected!=null||saving)return;
  setState(()=>saving=true);
  final result=choice==question.answerIndex;
  try{
   await _store.record(question.id,result);
   history.putIfAbsent(question.id,()=>[]).add(result);
   widget.onAnswerRecorded?.call(question.id,result);
   if(!mounted)return;
   setState((){selected=choice;if(result)correct++;saving=false;});
  }catch(error){
   if(!mounted)return;
   setState(()=>saving=false);
   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('解答履歴を保存できません: $error')));
  }
 }
 Future<void> _toggleReviewFlag(FeQuestion question) async {
  final flagged=!flaggedIds.contains(question.id);
  try{
   await _store.setFlag(question.id,flagged);
   if(!mounted)return;
   setState(()=>flagged?flaggedIds.add(question.id):flaggedIds.remove(question.id));
   widget.onReviewFlagChanged?.call(question.id,flagged);
  }catch(error){
   if(!mounted)return;
   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('見直し設定を保存できません: $error')));
  }
 }
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('基本情報・問題演習')),
  body:FutureBuilder<void>(future:_loading,builder:(context,snapshot){
   if(snapshot.hasError){return Center(child:Text('問題読込失敗: ${snapshot.error}'));}
   if(snapshot.connectionState!=ConnectionState.done){return const Center(child:CircularProgressIndicator());}
   final answered=history.values.where((h)=>h.isNotEmpty).length;
   final reviewCount=FeQuestionSelector.selectForReview(all,history,flaggedIds).length;
   final domains=all.map((q)=>q.domain).toSet().toList()..sort();
   return ListView(padding:const EdgeInsets.all(20),children:[
    Text('学習済み $answered / ${all.length}問　要復習 $reviewCount問'),
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
     key:ValueKey(mode),
     initialValue:mode,
     items:const [
      DropdownMenuItem(value:FePracticeMode.all,child:Text('全問題')),
      DropdownMenuItem(value:FePracticeMode.incorrect,child:Text('間違えた問題')),
      DropdownMenuItem(value:FePracticeMode.review,child:Text('要復習（間違えた・要確認）')),
      DropdownMenuItem(value:FePracticeMode.unseen,child:Text('未学習の問題')),
      DropdownMenuItem(value:FePracticeMode.weak,child:Text('苦手問題を優先（誤答率50%以上）')),
      DropdownMenuItem(value:FePracticeMode.sectionA,child:Text('科目A')),
      DropdownMenuItem(value:FePracticeMode.sectionB,child:Text('科目B')),
      DropdownMenuItem(value:FePracticeMode.examB,child:Text('科目B 模擬構成（20問・16/4）')),
     ],
     onChanged:(v){if(v!=null){setState((){mode=v;if(v==FePracticeMode.examB){domainFilter=null;limit=20;}_filter();});}},
    ),
    if(mode==FePracticeMode.examB) const Padding(padding:EdgeInsets.only(bottom:12),child:Text('本試験の科目B構成に合わせ、アルゴリズム16問と情報セキュリティ4問を出題します。')),
    const SizedBox(height:12),
    DropdownButtonFormField<String>(
     key:ValueKey(domainFilter),
     initialValue:domainFilter,
     decoration:const InputDecoration(labelText:'分野で絞り込む'),
     items:[const DropdownMenuItem<String>(value:null,child:Text('全分野')),
      for(final domain in domains) DropdownMenuItem(value:domain,child:Text(domain))],
     onChanged:mode==FePracticeMode.examB?null:(v)=>setState((){domainFilter=v;_filter();}),
    ),
    SwitchListTile(title:const Text('問題順をシャッフル'),value:shuffle,onChanged:mode==FePracticeMode.examB?null:(v)=>setState((){shuffle=v;_filter();})),
    DropdownButtonFormField<int>(
     key:ValueKey(mode==FePracticeMode.examB?20:limit),
     initialValue:mode==FePracticeMode.examB?20:limit,
     decoration:const InputDecoration(labelText:'1回の演習問題数'),
     items:const [
      DropdownMenuItem(value:10,child:Text('10問')),
      DropdownMenuItem(value:20,child:Text('20問')),
      DropdownMenuItem(value:0,child:Text('全件')),
     ],
     onChanged:mode==FePracticeMode.examB?null:(v){if(v!=null){setState((){limit=v;_filter();});}},
    ),
    const SizedBox(height:16),
    if(questions.isEmpty)
     const Text('この条件に該当する問題はありません。')
    else if(index>=questions.length)...[
     Text(mode==FePracticeMode.examB?'科目B模擬構成の演習完了　$correct / ${questions.length}':'演習完了　$correct / ${questions.length}',style:Theme.of(context).textTheme.headlineSmall),
     Text('今回の正答率 ${(correct/questions.length*100).toStringAsFixed(1)}%'),
     const SizedBox(height:8),
     Text('誤答した問題は「間違えた問題」から復習できます。'),
     const SizedBox(height:12),
     FilledButton.tonal(onPressed:()=>setState((){mode=FePracticeMode.review;_filter();}),child:const Text('要復習問題を解く')),

     const SizedBox(height:12),
     FilledButton(onPressed:()=>setState(_filter),child:const Text('もう一度')),
    ]else ...[
     LinearProgressIndicator(value:index/questions.length),
     const SizedBox(height:12),
     Text('科目${questions[index].section} · ${questions[index].domain}　${index+1}/${questions.length}'),
     const SizedBox(height:16),
     Text(questions[index].stem,style:Theme.of(context).textTheme.titleLarge),
     const SizedBox(height:16),
     Align(alignment:Alignment.centerLeft,child:TextButton.icon(
      onPressed:()=>_toggleReviewFlag(questions[index]),
      icon:Icon(flaggedIds.contains(questions[index].id)?Icons.bookmark:Icons.bookmark_border),
      label:Text(flaggedIds.contains(questions[index].id)?'要確認から外す':'あとで見直す'))),
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
