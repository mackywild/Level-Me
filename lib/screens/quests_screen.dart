import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/quest.dart';
import '../models/stat_type.dart';
import 'fe_study_screen.dart';
class QuestsScreen extends StatefulWidget{
 const QuestsScreen({super.key,required this.controller});
 final AppController controller;
 @override State<QuestsScreen> createState()=>_QuestsScreenState();
}
class _QuestsScreenState extends State<QuestsScreen>{
 QuestCadence? filter;
 String label(QuestCadence c)=>switch(c){
  QuestCadence.oneTime=>'ONE TIME',QuestCadence.daily=>'DAILY',QuestCadence.weekly=>'WEEKLY'};
 @override Widget build(BuildContext context){
  final quests=widget.controller.state.quests.where((q)=>filter==null||q.cadence==filter).toList();
  return Scaffold(backgroundColor:Colors.transparent,body:Column(children:[
   SizedBox(height:58,child:ListView(scrollDirection:Axis.horizontal,padding:const EdgeInsets.all(8),children:[
    ChoiceChip(label:const Text('ALL'),selected:filter==null,onSelected:(_)=>setState(()=>filter=null)),
    for(final c in QuestCadence.values)Padding(padding:const EdgeInsets.only(left:8),child:
     ChoiceChip(label:Text(label(c)),selected:filter==c,onSelected:(_)=>setState(()=>filter=c))),
   ])),
   Expanded(child:ListView.builder(padding:const EdgeInsets.fromLTRB(16,8,16,120),itemCount:quests.length,itemBuilder:(context,i){
    final q=quests[i],done=q.isCompleted;
    return Card(child:ListTile(
     leading:Icon(done?Icons.check_circle:Icons.bolt,color:done?Colors.greenAccent:Colors.amberAccent),
     title:Text(q.title,style:TextStyle(decoration:done?TextDecoration.lineThrough:null)),
     subtitle:Text('${label(q.cadence)} | ${q.rewards.map((r)=>'${r.stat.shortLabel} +${r.exp}').join(' / ')}'),
     trailing:done?const Text('CLEARED'):FilledButton(onPressed:()=>q.id=='starter-study' ? Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>FeStudyScreen(controller:widget.controller,quest:q))) : widget.controller.completeQuest(q),child:Text(q.id=='starter-study'?'START':'CLEAR'))
    ));
   })),
  ]),
  floatingActionButton:FloatingActionButton.extended(onPressed:()=>showQuestForm(context),icon:const Icon(Icons.add),label:const Text('NEW QUEST')));
 }
 Future<void> showQuestForm(BuildContext context) async{
  final title=TextEditingController();
  var stat=StatType.intelligence,exp=10,cadence=QuestCadence.daily;
  await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(sheet)=>StatefulBuilder(builder:(context,setModal)=>Padding(
   padding:EdgeInsets.fromLTRB(20,20,20,MediaQuery.of(context).viewInsets.bottom+20),
   child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Text('CREATE QUEST',style:Theme.of(context).textTheme.titleLarge),
    TextField(controller:title,decoration:const InputDecoration(labelText:'QUEST NAME')),
    DropdownButtonFormField<QuestCadence>(initialValue:cadence,items:QuestCadence.values.map((c)=>DropdownMenuItem(value:c,child:Text(label(c)))).toList(),onChanged:(v)=>setModal(()=>cadence=v??cadence)),
    DropdownButtonFormField<StatType>(initialValue:stat,items:StatType.values.map((s)=>DropdownMenuItem(value:s,child:Text('${s.icon} ${s.label}'))).toList(),onChanged:(v)=>setModal(()=>stat=v??stat)),
    Text('EXP +$exp'),
    Slider(value:exp.toDouble(),min:5,max:50,divisions:9,onChanged:(v)=>setModal(()=>exp=v.round())),
    FilledButton(onPressed:() async{
     if(title.text.trim().isEmpty)return;
     await widget.controller.addQuest(title:title.text,rewards:[QuestReward(stat:stat,exp:exp)],cadence:cadence);
     if(sheet.mounted)Navigator.pop(sheet);
    },child:const Text('REGISTER')),
   ]))));
  title.dispose();
 }
}
