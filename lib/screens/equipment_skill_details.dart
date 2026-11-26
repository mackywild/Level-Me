import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../world/abyss_inventory.dart';
import '../world/abyss_equipment_skill_policy.dart';
import '../world/abyss_equipment_skill_master.dart';
import '../world/abyss_equipment_skill_pool.dart';
import '../world/abyss_equipment_effects.dart';

/// 保存済み結果だけを表示する。抽選・履歴生成・書き込みは行わない。
class EquipmentSkillDetails extends StatelessWidget {
 const EquipmentSkillDetails({super.key,required this.controller,required this.item,required this.generation});
 final AppController controller;
 final EquipmentInstance item;
 final int generation;

 static String effectName(EquipmentEffect effect)=>switch(effect){
  EquipmentEffect.physicalPercent=>'物理攻撃力',
  EquipmentEffect.magicPercent=>'魔法攻撃力',
  EquipmentEffect.defensePercent=>'防御力',
  EquipmentEffect.damageReduction=>'被ダメージ軽減',
  EquipmentEffect.extraAttackChance=>'追加攻撃発生率',
  EquipmentEffect.energyDiscount=>'エネルギー消費軽減',
  EquipmentEffect.cooldownReduction=>'CD短縮',
  EquipmentEffect.criticalChance=>'会心率',
  EquipmentEffect.penetration=>'貫通',
  EquipmentEffect.hpPercent=>'最大HP',
  EquipmentEffect.evasionChance=>'回避率',
  EquipmentEffect.resistance=>'耐性',
  EquipmentEffect.naturalRecovery=>'自然回復',
  EquipmentEffect.rewardPercent=>'報酬補正',
 };
 static String rarityName(EquipmentSkillRarity rarity)=>switch(rarity){
  EquipmentSkillRarity.common=>'一般',
  EquipmentSkillRarity.rare=>'希少',
  EquipmentSkillRarity.ultraRare=>'超希少',
 };
 static String percent(int value){
  final whole=value~/100,part=value%100;
  if(part==0)return '$whole%';
  return '$whole.${part.toString().padLeft(2,'0')}%';
 }
 static Future<void> show(BuildContext context,AppController controller,EquipmentInstance item){
  final generation=controller.restoreGeneration;
  return showDialog<void>(
  context:context,builder:(ctx)=>AlertDialog(
   title:const Text('装備スキル詳細'),
   content:SingleChildScrollView(child:EquipmentSkillDetails(controller:controller,item:item,generation:generation)),
   actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('閉じる'))],
  ),
 );
 }

 @override Widget build(BuildContext context)=>ListenableBuilder(listenable:controller,builder:(context,child){
  final inv=controller.state.inventory;
  final current=inv.equipment[item.id];
  if(generation!=controller.restoreGeneration||current==null||current.masterId!=item.masterId||current.slot!=item.slot||current.rarity!=item.rarity){
   return const Text('装備情報が更新されました。詳細を開き直してください。');
  }
  final history=inv.equipmentSkillHistories[current.id];
  final master=controller.equipmentSkillMaster;
  final equipped=inv.equipped.containsValue(current.id);
  final active=inv.equipmentSkillSeed!=null&&master!=null;
  final entries=<String,EquipmentSkillMasterEntry>{for(final entry in master?.entries??const <EquipmentSkillMasterEntry>[])entry.id:entry};
  final grants=<int,StoredEquipmentSkill>{for(final grant in history?.grants??const <StoredEquipmentSkill>[])grant.milestone:grant};
  final milestones=current.rarity==EquipmentRarity.ex?const <int>[]:EquipmentSkillPolicy.milestones(current.rarity);
  final theme=Theme.of(context);
  final definition=controller.equipmentCatalog.find(current.masterId);
  final validDefinition=definition!=null&&definition.slot==current.slot&&definition.rarity==current.rarity;
  return Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
   Text('${controller.summonRewardName(current.masterId)} +${current.enhancement}',style:theme.textTheme.titleMedium),
   Text('${current.rarity.name.toUpperCase()} / ${current.id} / ${equipped?'装着中':'未装着'}'),
   if(validDefinition)...[
    Text('装備性能：物攻 ${controller.enhancementScaling.apply(definition.physical,current.enhancement)} / 魔攻 ${controller.enhancementScaling.apply(definition.magic,current.enhancement)} / 防御 ${controller.enhancementScaling.apply(definition.defense,current.enhancement)}'),
   ],
   const Divider(),
   if(current.rarity==EquipmentRarity.ex)const Text('EX固有・ランダム枠は未対応')
   else if(milestones.isEmpty)const Text('スキル付与枠なし')
   else...[
    Text('確定済み ${grants.length} / ${milestones.length} 枠'),
    if(!active)const Text('装備スキル機能未有効化'),
    if(!equipped)const Text('未装着のため戦闘効果は適用されません'),
    if(history!=null&&history.startEnhancement>0)Text('履歴開始：+${history.startEnhancement}（過去枠の再抽選なし）'),
    for(final stage in milestones)
     Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(grants[stage] case final grant?)...[
       Text('+$stage 確定済み：Lv${grant.level}'),
       Text(grant.skillId),
       if(entries[grant.skillId] case final entry?)...[
        Text('${rarityName(entry.rarity)} / ${effectName(entry.effect)} ${percent(entry.perLevel*grant.level)}'),
        const Text('個別性能（重複・上限適用前）'),
        if(entry.effect==EquipmentEffect.resistance)const Text('状態異常耐性：判定基盤のみ（敵の付与能力は未接続）'),
        if(entry.effect==EquipmentEffect.rewardPercent)const Text('報酬補正：G接続済み・素材ドロップ未接続'),
        if(!battleConnectedEquipmentEffects.contains(entry.effect))const Text('戦闘未接続（装着時は戦闘開始不可の場合あり）'),
       ]else const Text('性能定義未確認'),
      ]else if(stage<=current.enhancement)
       Text('+$stage ${history==null||stage<=history.startEnhancement?'旧枠・抽選対象外':'履歴不整合'}')
      else Text('+$stage 未解放'),
     ])),
   ],
  ]);
 });
}
