import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../world/abyss_inventory.dart';
import '../world/abyss_ex_equipment_master.dart';
import '../world/abyss_ex_battle_attack.dart';

String _percent(int bps)=>'${bps~/100}${bps%100==0?'':'.${(bps%100).toString().padLeft(2,'0')}'}%';
String exManualSpecText(ExManualSkillSpec s)=>'基本消費：物理 ${s.physicalCost} / 魔法 ${s.magicCost} / HP ${_percent(s.hpCostBps)} / 寿命 ${s.lifeDays}日\nCD ${s.cooldown} / 初期CD ${s.initialCooldown} / 回数 ${s.maxUses??'無制限'}\nCD短縮 ${s.cooldownReduction?'対象':'対象外'} / 消費軽減 ${s.energyDiscount?'対象':'対象外'}${s.maxHpBps==null?'':' / HP ${_percent(s.maxHpBps!)}以下'}';

/// Explicit selection from equipped registered fixed skills; no writes on render.
class ExManualSlotPanel extends StatelessWidget {
 const ExManualSlotPanel({super.key,required this.controller,required this.busy,required this.run});
 final AppController controller;
 final bool busy;
 final Future<void> Function(Future<void> Function()) run;
 @override Widget build(BuildContext context){
  final inv=controller.state.inventory,master=controller.exEquipmentMaster;
  if(master==null||!controller.exManualPlanningAvailable)return const SizedBox.shrink();
  final generation=controller.restoreGeneration;
  final locked=busy||controller.inventoryBusy||!controller.ready||controller.state.world.battle!=null;
  final candidates=<({ExManualSkillSlot selection,String name,ExManualSkillSpec spec})>[];
  for(final id in inv.equipped.values){
   final item=inv.equipment[id]!;
   if(item.rarity!=EquipmentRarity.ex)continue;
   if(controller.exEquipUnavailable(item)!=null)continue;
   for(final fixed in master.resolveFixedSkills(item)){
    final spec=fixed.skill.manualSpec;
    if(fixed.skill.activation!=ExSkillActivation.manual||spec==null)continue;
    final selection=ExManualSkillSlot(instanceId:id,skillId:fixed.skill.id);
    if(controller.exManualSelectionUnavailable(selection)==null)candidates.add((selection:selection,name:'${fixed.skill.name} Lv${fixed.level} / ${controller.summonRewardName(item.masterId)} / $id',spec:spec));
   }
  }
  return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   const Text('EX専用スキル枠（3枠）',style:TextStyle(fontWeight:FontWeight.bold)),
   if(candidates.isEmpty)const Text('登録可能な装着済みEXスキルなし'),
   for(var slot=0;slot<AbyssInventory.exManualSlotCount;slot++)
    Builder(builder:(context){
     final index=slot;
     final current=inv.exManualSlots[index];
     final available=candidates.where((candidate)=>!inv.exManualSlots.entries.any((e)=>e.key!=index&&e.value.skillId==candidate.selection.skillId)).toList();
     final selected=available.indexWhere((candidate)=>candidate.selection.instanceId==current?.instanceId&&candidate.selection.skillId==current?.skillId);
     return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('専用枠 ${index+1}'),
      DropdownButton<int>(
       key:ValueKey('ex-slot-$index'),isExpanded:true,value:selected<0?-1:selected,
       items:[const DropdownMenuItem(value:-1,child:Text('未登録')),for(var i=0;i<available.length;i++)DropdownMenuItem(value:i,child:Text(available[i].name,overflow:TextOverflow.ellipsis))],
       onChanged:locked?null:(value){
        if(value==null)return;
        final selection=value<0?null:available[value].selection;
        run(()=>controller.setExManualSkillSlot(index,instanceId:selection?.instanceId,skillId:selection?.skillId,expectedGeneration:generation));
       },
      ),
      if(selected>=0)Text(exManualSpecText(available[selected].spec)),
     ]);
    }),
   if(!controller.exManualExecutionAvailable)const Text('任意発動は未接続'),
  ])));
 }
}

class ExBattleSkillPanel extends StatelessWidget {
 const ExBattleSkillPanel({super.key,required this.controller,required this.busy,required this.run});
 final AppController controller;
 final bool busy;
 final Future<void> Function(Future<void> Function()) run;
 @override Widget build(BuildContext context){
  final w=controller.state.world,b=w.battle;
  if(b==null||b.exAttacks.isEmpty)return const SizedBox.shrink();
  final generation=controller.restoreGeneration,battleId=b.id,turn=b.turn;
  return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   const Text('EX / 装備専用スキル',style:TextStyle(fontWeight:FontWeight.bold)),
   for(final a in b.exAttacks)
    Builder(builder:(context){
     final reason=controller.exManualExecutionAvailable?controller.worldEngine.exAttackUnavailable(w,a.slot):'任意発動未接続';
     final cost=controller.worldEngine.exAttackCosts(w,a);
     final name=controller.exEquipmentMaster?.fixedSkills[a.skillId]?.name??a.skillId;
     final effect=switch(a.attribute){
      ExAttackAttribute.physical=>'物理攻撃 威力 ${_percent(a.powerBps)}',
      ExAttackAttribute.magic=>'魔法攻撃 威力 ${_percent(a.powerBps)}',
      ExAttackAttribute.hpRecovery=>'HP回復 ${_percent(a.powerBps)}${reason==null?' / 回復予定 ${cost.recovery}（反撃前）':''}',
     };
     return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('専用枠 ${a.slot+1} / $name Lv${a.level} / ${a.instanceId}'),
      Text(effect),
      Text('実消費：物理 ${cost.physical} / 魔法 ${cost.magic} / HP ${cost.hp} / 寿命 ${cost.life}日'),
      Text('CD ${a.remaining(turn)} / 残回数 ${a.maxUses==null?'無制限':a.maxUses!-a.uses}${a.maxHpBps==null?'':' / HP ${_percent(a.maxHpBps!)}以下'}'),
      OutlinedButton(key:ValueKey('ex-battle-${a.slot}'),onPressed:busy||controller.inventoryBusy||!controller.ready||reason!=null?null:()=>run(()=>controller.useBattleExSkill(a.slot,battleId,turn,expectedGeneration:generation)),child:Text(reason??'発動（1ターン）')),
     ]);
    }),
  ])));
 }
}
