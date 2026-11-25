import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../world/abyss_skill.dart';

class AbyssSkillScreen extends StatefulWidget {
 const AbyssSkillScreen({super.key,required this.controller});
 final AppController controller;
 @override State<AbyssSkillScreen> createState()=>_AbyssSkillScreenState();
}
class _AbyssSkillScreenState extends State<AbyssSkillScreen>{
 SkillKind _kind=SkillKind.active;
 bool _confirming=false;
 String? _message;
 Future<void> _change(SkillDefinition def,String action,int revision,int generation) async{
  if(_confirming)return;
  final c=widget.controller;
  setState(()=>_confirming=true);
  try{
   final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:Text('${def.name}を$actionしますか？'),
    content:Text(action=='習得'?'${_requirements(def)}\n習得費用と習得記録を保存します。':'スキル構成の変更を保存します。'),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('キャンセル')),
     FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('確定')),
    ],
   ));
   if(!mounted||confirmed!=true)return;
   switch(action){
    case '習得':await c.learnWorldSkill(def.id,expectedGeneration:generation,expectedRevision:revision);break;
    case '装着':await c.equipWorldSkill(def.id,expectedGeneration:generation,expectedRevision:revision);break;
    case '解除':await c.unequipWorldSkill(def.id,expectedGeneration:generation,expectedRevision:revision);break;
   }
   if(mounted)setState(()=>_message='$actionしました');
  }catch(_){
   if(mounted)setState(()=>_message='変更できませんでした。現在のスキル構成を確認してください。');
  }finally{
   if(mounted)setState(()=>_confirming=false);
  }
 }
 String _requirements(SkillDefinition def){
  final rule=def.acquisition;
  final parent=rule.prerequisiteId;
  final parentName=parent==null?null:widget.controller.skillDefinitions.firstWhere((d)=>d.id==parent).name;
  return [
   '必要プレイヤーLv.${rule.playerLevel}',
   if(def.execution?.usesStopCooldown==true&&def.id=='skill:chrono_combo')'STAGE 06クリア',
   if(rule.clearedStage>0)'STAGE ${rule.clearedStage}クリア',
   if(parentName!=null)'$parentName Lv.${rule.prerequisiteLevel}',
   '費用：${rule.gold} G / 魔晶石 ${rule.magicCrystals}',
  ].join(' / ');
 }
 String _label(SkillKind kind)=>kind==SkillKind.active?'能動':'パッシブ';
 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('スキル管理')),
  body:ListenableBuilder(listenable:widget.controller,builder:(context,child){
   final c=widget.controller;
   if(!c.ready)return const Center(child:Text('初期化中'));
   final state=c.state.skills;
   final revision=state.revision,generation=c.restoreGeneration;
   final defs=c.skillDefinitions;
   final names={for(final def in defs)def.id:def.name};
   final locked=_confirming||c.inventoryBusy||c.state.world.battle!=null;
   return ListView(padding:const EdgeInsets.all(16),children:[
    const Text('ABYSS SKILL',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:Color(0xffd5b36e))),
    for(final kind in SkillKind.values)...[
     Text('${_label(kind)}スキル：${(kind==SkillKind.active?state.active:state.passive).length} / ${SkillState.limit(kind)}'),
     for(var i=0;i<SkillState.limit(kind);i++)
      ListTile(dense:true,leading:const Icon(Icons.auto_awesome),title:Text('枠 ${i+1}：${i<(kind==SkillKind.active?state.active:state.passive).length?names[(kind==SkillKind.active?state.active:state.passive)[i]]??'不明':'空き枠'}')),
    ],
    if(defs.any((def)=>def.passiveBonus!=null))
     Text('現在の能力値：物攻 ${c.worldStats.physical} / 魔攻 ${c.worldStats.magic} / 防御 ${c.worldStats.defense}'),
    if(c.state.world.battle!=null)const Text('戦闘中は変更できません'),
    if(defs.isNotEmpty)Text('所持：${c.state.world.gold} G / 魔晶石 ${c.state.world.magicCrystals}'),
    if(c.inventoryBusy)const LinearProgressIndicator(),
    if(_message!=null)Text(_message!),
    if(defs.isEmpty)const Text('公開済みスキルなし')
    else...[
     Wrap(spacing:8,children:[
      for(final kind in SkillKind.values)ChoiceChip(label:Text(_label(kind)),selected:_kind==kind,onSelected:(_)=>setState(()=>_kind=kind)),
     ]),
     for(final def in defs.where((d)=>d.kind==_kind))
      Builder(builder:(context){
       final learned=state.learned.containsKey(def.id);
       final slots=def.kind==SkillKind.active?state.active:state.passive;
       final equipped=slots.contains(def.id);
       final action=equipped?'解除':learned?'装着':'習得';
       final full=learned&&!equipped&&slots.length>=SkillState.limit(def.kind);
       final reason=learned?null:c.skillLearnUnavailable(def.id);
       return Card(child:ListTile(
        title:Text(def.name),subtitle:Text([
         equipped?'装着中':learned?'習得済み':'未習得',
         if(!learned)_requirements(def),
         ?reason,
         if(learned&&def.execution!=null)'Lv.${SkillMastery.level(state.learned[def.id]!)} / 熟練度 ${state.learned[def.id]} / ${SkillMastery.maxUses}',
         if(def.lifeRewardBonus case final reward?)'戦闘勝利時の寿命報酬 +${reward.percent}%',
         if(def.passiveBonus case final bonus?)'物攻 +${bonus.physical} / 魔攻 +${bonus.magic} / 防御 +${bonus.defense}',
        ].join('\n')),
        trailing:OutlinedButton(key:ValueKey('skill-${def.id}'),onPressed:locked||full||reason!=null?null:()=>_change(def,action,revision,generation),child:Text(full?'枠満杯':action)),
       ));
      }),
    ],
   ]);
  }),
 );
}
