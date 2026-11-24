import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/quest.dart';
import '../models/stat_type.dart';
import 'fe_study_screen.dart';
import 'workout_screen.dart';
class QuestsScreen extends StatefulWidget{
 const QuestsScreen({super.key,required this.controller});
 final AppController controller;
 @override State<QuestsScreen> createState()=>_QuestsScreenState();
}
class _QuestsScreenState extends State<QuestsScreen>{
 QuestCadence? filter;
 bool archived=false;
 Future<void> _run(Future<void> Function() action) async {try{await action();}catch(error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('操作失敗: $error')));}}
 String label(QuestCadence c)=>switch(c){
  QuestCadence.oneTime=>'一度だけ',QuestCadence.daily=>'毎日',QuestCadence.weekly=>'毎週'};
 @override Widget build(BuildContext context){
  final quests=widget.controller.state.quests.where((q)=>q.archived==archived&&(filter==null||q.cadence==filter)).toList();
  return Scaffold(backgroundColor:Colors.transparent,body:Column(children:[
   SizedBox(height:58,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.all(8),children:[
    FilterChip(label:const Text('保管済み'),selected:archived,onSelected:(v)=>setState(()=>archived=v)),
    ChoiceChip(label:const Text('すべて'),selected:filter==null,onSelected:(_)=>setState(()=>filter=null)),
    for(final c in QuestCadence.values)Padding(padding:const EdgeInsets.only(left:8),child:
     ChoiceChip(label:Text(label(c)),selected:filter==c,onSelected:(_)=>setState(()=>filter=c))),
   ])),
   if(!archived)const Padding(padding:EdgeInsets.symmetric(horizontal:16),child:Text('クエストを長押しして編集・保管')),
   Expanded(child:ListView.builder(padding:const EdgeInsets.fromLTRB(16,8,16,120),itemCount:quests.length,itemBuilder:(context,i){
    final q=quests[i],done=q.isCompleted;
    final isStudyQuest=q.id=='starter-study';
    final isWorkout=q.id=='starter-workout';
    final isReviewQuest=q.title.startsWith(FeStudyScreen.reviewQuestPrefix);
    final startsStudy=isStudyQuest||isReviewQuest;
    if(q.archived)return Card(child:ListTile(title:Text(q.title),subtitle:const Text('達成履歴は保持されています'),trailing:TextButton(onPressed:()=>_run(()=>widget.controller.restoreQuest(q.id)),child:const Text('復元'))));
    return Card(child:ListTile(
     onLongPress:widget.controller.canManageQuest(q)?()=>_manage(q):null,
     leading:Icon(done?Icons.check_circle:Icons.bolt,color:done?Colors.greenAccent:Colors.amberAccent),
     title:Text(isStudyQuest?'基本情報技術者の勉強をする':q.title,style:TextStyle(decoration:done?TextDecoration.lineThrough:null)),
     subtitle:Text(isStudyQuest
      ?'${label(q.cadence)} | タイマー記録・問題演習つき'
      :'${label(q.cadence)} | ${q.rewards.map((r)=>'${r.stat.shortLabel} +${r.exp}').join(' / ')}'),
     trailing:isWorkout?FilledButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>WorkoutScreen(controller:widget.controller,quest:q))),child:Text(done?'追加運動':'筋トレする')):done
      ?isStudyQuest?OutlinedButton(
       onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>FeStudyScreen(
        controller:widget.controller,quest:q,
       ))),child:const Text('問題を解く'))
       :const Text('達成済み')
      :FilledButton(
       onPressed:startsStudy?()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>FeStudyScreen(
        controller:widget.controller,quest:q,
        reviewOnly:isReviewQuest,
       ))):()=>_run(()=>widget.controller.completeQuest(q)),
       child:Text(isStudyQuest?'学習する':isReviewQuest?'復習する':'達成する'))
    ));
   })),
  ]),
  floatingActionButton:FloatingActionButton.extended(onPressed:()=>showQuestForm(context),icon:const Icon(Icons.add),label:const Text('クエストを追加')));
 }
 Future<void> _manage(Quest q) async {
  final action=await showModalBottomSheet<String>(context:context,builder:(ctx)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
   ListTile(leading:const Icon(Icons.edit),title:const Text('編集'),onTap:()=>Navigator.pop(ctx,'edit')),
   ListTile(leading:const Icon(Icons.archive),title:const Text('保管（一覧から削除）'),onTap:()=>Navigator.pop(ctx,'archive')),
  ])));
  if(!mounted)return;
  if(action=='edit'){await showQuestForm(context,q);}
  if(action=='archive'){
   final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('クエストを保管しますか？'),content:const Text('獲得済みEXPと達成履歴は保持されます。保管済み一覧から復元できます。'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('取消')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('保管'))]));
   if(confirmed==true)await _run(()=>widget.controller.archiveQuest(q.id));
  }
 }
 Future<void> showQuestForm(BuildContext context,[Quest? existing]) async{
  final title=TextEditingController(text:existing?.title??'');
  final rewards=<StatType,int>{if(existing==null)StatType.intelligence:10,for(final r in existing?.rewards??<QuestReward>[])r.stat:r.exp};
  var cadence=existing?.cadence??QuestCadence.daily,busy=false;
  final locked=existing!=null&&(existing.completedAt!=null||existing.completionKeys.isNotEmpty);
  await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(sheet)=>StatefulBuilder(builder:(context,setModal)=>SafeArea(child:SingleChildScrollView(
   padding:EdgeInsets.fromLTRB(20,20,20,MediaQuery.of(context).viewInsets.bottom+20),
   child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Text(existing==null?'クエストを作成':'クエストを編集',style:Theme.of(context).textTheme.titleLarge),
    TextField(controller:title,enabled:!busy,decoration:const InputDecoration(labelText:'クエスト名')),
    DropdownButtonFormField<QuestCadence>(initialValue:cadence,items:QuestCadence.values.map((c)=>DropdownMenuItem(value:c,child:Text(label(c)))).toList(),onChanged:locked||busy?null:(v)=>setModal(()=>cadence=v??cadence)),
    if(locked)const Text('達成履歴があるため頻度は変更できません。'),
    const SizedBox(height:12),
    const Text('報酬ステータス（複数選択可）'),
    for(final stat in StatType.values)...[
     CheckboxListTile(contentPadding:EdgeInsets.zero,title:Text('${stat.icon} ${stat.label}'),value:rewards.containsKey(stat),onChanged:busy?null:(v)=>setModal((){if(v==true){rewards[stat]=10;}else{rewards.remove(stat);}})),
     if(rewards.containsKey(stat))Row(children:[Expanded(child:Slider(value:rewards[stat]!.clamp(1,50).toDouble(),min:1,max:50,divisions:49,onChanged:busy?null:(v)=>setModal(()=>rewards[stat]=v.round()))),Text('+${rewards[stat]} EXP')]),
    ],
    Text('合計 ${rewards.values.fold<int>(0,(a,b)=>a+b)} EXP'),
    FilledButton(onPressed:busy||rewards.isEmpty?null:() async{
     if(title.text.trim().isEmpty)return;
     setModal(()=>busy=true);
     final items=rewards.entries.map((e)=>QuestReward(stat:e.key,exp:e.value)).toList();
     try {
      if(existing==null){await widget.controller.addQuest(title:title.text,rewards:items,cadence:cadence);}
      else{await widget.controller.editQuest(existing.id,title:title.text,rewards:items,cadence:cadence);}
      if(sheet.mounted)Navigator.pop(sheet);
     }catch(error){if(sheet.mounted){setModal(()=>busy=false);ScaffoldMessenger.of(sheet).showSnackBar(SnackBar(content:Text('保存失敗: $error')));}}
    },child:Text(busy?'保存中…':'保存する')),
   ])))));
  title.dispose();
 }
}
