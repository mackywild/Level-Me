import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../models/achievement_catalog.dart';
import '../models/stat_type.dart';
class AchievementsScreen extends StatelessWidget{
 const AchievementsScreen({super.key,required this.controller});
 final AppController controller;
 @override Widget build(BuildContext context){
  final unlocked=controller.state.achievements;
  return Scaffold(backgroundColor:Colors.transparent,
   body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,120),children:[
    Text('ACHIEVEMENT COLLECTION',style:Theme.of(context).textTheme.titleLarge),
    Text('${achievementCatalog.where((r)=>unlocked.any((a)=>a.id==r.id)).length} / ${achievementCatalog.length} UNLOCKED'),
    const SizedBox(height:12),
    for(final rule in achievementCatalog)Builder(builder:(context){
     final done=unlocked.any((a)=>a.id==rule.id);
     final value=controller.achievementMetric(rule).clamp(0,rule.target);
     return Card(child:ListTile(
      leading:Text(done?rule.icon:'🔒',style:const TextStyle(fontSize:28)),
      title:Text(rule.title),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
       Text(rule.description),LinearProgressIndicator(value:value/rule.target,minHeight:4),
       Text('$value / ${rule.target}  ·  ${rule.stat.shortLabel} +${rule.reward} EXP'),
      ]),trailing:done?const Icon(Icons.verified,color:Colors.amber):null));
    }),
    const SizedBox(height:16),
    Text('PERSONAL MILESTONES',style:Theme.of(context).textTheme.titleMedium),
    for(final a in unlocked.where((a)=>!achievementCatalog.any((r)=>r.id==a.id)))
     Card(child:ListTile(title:Text(a.title),subtitle:Text('${a.description} · ${a.stat.shortLabel} +${a.exp} EXP'))),
   ]),
   floatingActionButton:FloatingActionButton.extended(onPressed:()=>showMilestone(context),icon:const Icon(Icons.add),label:const Text('MILESTONE')));
 }
 Future<void> showMilestone(BuildContext context) async{
  final title=TextEditingController(),description=TextEditingController();
  var stat=StatType.intelligence,exp=50;
  await showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(sheet)=>StatefulBuilder(builder:(context,setModal)=>Padding(
   padding:EdgeInsets.fromLTRB(20,20,20,MediaQuery.of(context).viewInsets.bottom+20),
   child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Text('PERSONAL MILESTONE',style:Theme.of(context).textTheme.titleLarge),
    TextField(controller:title,decoration:const InputDecoration(labelText:'TITLE')),
    TextField(controller:description,decoration:const InputDecoration(labelText:'DESCRIPTION')),
    DropdownButtonFormField<StatType>(initialValue:stat,items:StatType.values.map((s)=>DropdownMenuItem(value:s,child:Text('${s.icon} ${s.label}'))).toList(),onChanged:(v)=>setModal(()=>stat=v??stat)),
    Text('EXP +$exp'),Slider(value:exp.toDouble(),min:25,max:200,divisions:7,onChanged:(v)=>setModal(()=>exp=v.round())),
    FilledButton(onPressed:() async{
     if(title.text.trim().isEmpty)return;
     await controller.unlockAchievement(title:title.text,description:description.text,stat:stat,exp:exp);
     if(sheet.mounted)Navigator.pop(sheet);
    },child:const Text('UNLOCK')),
   ]))));
  title.dispose();description.dispose();
 }
}
