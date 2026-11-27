import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../world/world_catalog.dart';
import '../world/world_engine.dart';
import '../world/abyss_inventory.dart';
import 'abyss_summon_screen.dart';
import 'abyss_forge_screen.dart';
import 'abyss_inventory_screen.dart';
import 'abyss_shop_screen.dart';
import 'abyss_compendium_screen.dart';
import 'abyss_skill_screen.dart';
import 'ex_skill_slots.dart';

String _activeSkillDescription(AppController c,WorldState w,ActiveSkillSpec spec){
 final cost=spec.lifeCost>0?'寿命 ${spec.lifeCost}日':'物理 ${c.worldEngine.activeSkillCost(w,spec)}';
 final effect=switch(spec.effect){
  ActiveSkillEffect.foresight=>'次の反撃無効',
  ActiveSkillEffect.repairHp=>'HP ${spec.repairPercent}%回復',
  ActiveSkillEffect.timeCleanse=>'毒を浄化',
  ActiveSkillEffect.stopAttack=>'威力${spec.powerPercent}% / 時間停止（耐性あり）',
  ActiveSkillEffect.crimsonAwakening=>'物攻 +${spec.rules.awakeningPercent}% / ${spec.rules.awakeningDuration}ターン',
  ActiveSkillEffect.rewindHp=>'前ターンHP復元（記録：${w.battle?.previousTurnHp??"なし"}）',
  ActiveSkillEffect.physical||ActiveSkillEffect.accelerationAttack||ActiveSkillEffect.ultimateAttack=>'威力${spec.powerPercent}%${spec.hits==1?'':' × ${spec.hits}'}',
 };
 return '$cost / $effect';
}

class WorldScreen extends StatefulWidget {
 const WorldScreen({super.key,required this.controller});
 final AppController controller;
 @override State<WorldScreen> createState()=>_WorldScreenState();
}
class _WorldScreenState extends State<WorldScreen>{
 int? selectedStage;
 bool busy=false;
 static const crimson=Color(0xffdc405b);
 static const gold=Color(0xffd5b36e);
 Future<void> run(Future<void> Function() action) async {
  if(busy)return;
  setState(()=>busy=true);
  try {await action();}
  catch(error){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('操作失敗: $error')));}
  finally{if(mounted)setState(()=>busy=false);}
 }
 Widget meter(String label,int value,int max,Color color)=>Padding(
  padding:const EdgeInsets.symmetric(vertical:5),
  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(label),Text('$value / $max')]),
   const SizedBox(height:5),
   TweenAnimationBuilder<double>(tween:Tween(end:max>0?(value/max).clamp(0.0,1.0).toDouble():0.0),duration:const Duration(milliseconds:240),
    builder:(context,ratio,child)=>LinearProgressIndicator(value:ratio,color:color,minHeight:7,backgroundColor:const Color(0xff302634))),
  ]),
 );
 Widget panel(List<Widget> children)=>Container(
  margin:const EdgeInsets.only(bottom:14),padding:const EdgeInsets.all(16),
  decoration:BoxDecoration(color:const Color(0xff1b1520),borderRadius:BorderRadius.circular(16),border:Border.all(color:const Color(0xff49303f))),
  child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:children),
 );
 String label(WorldCommand command)=>switch(command){
  WorldCommand.claw=>'紅爪',
  WorldCommand.heavyClaw=>'連爪',
  WorldCommand.magic=>'魔力撃',
  WorldCommand.guard=>'防御',
  WorldCommand.slow=>'時間遅延',
  WorldCommand.accelerate=>'自己加速',
  WorldCommand.stopTime=>'時間停止',
  WorldCommand.compositeClaw=>'複合爪撃',
  WorldCommand.retreat=>'撤退',
 };
 String cost(WorldCommand command,WorldState w)=>switch(command){
  WorldCommand.claw=>w.physical>=widget.controller.worldEngine.energyCost(w,command)?'物理 ${widget.controller.worldEngine.energyCost(w,command)}':'消費なし・威力25%',
  WorldCommand.heavyClaw=>'物理 ${widget.controller.worldEngine.energyCost(w,command)}',
  WorldCommand.magic=>'魔法 ${widget.controller.worldEngine.energyCost(w,command)}',
  WorldCommand.guard=>'被ダメージ半減',
  WorldCommand.slow=>'寿命 3日',
  WorldCommand.accelerate=>'寿命 7日 / 紅爪2回強化',
  WorldCommand.stopTime=>'寿命 30日 / 敵行動停止',
  WorldCommand.compositeClaw=>'寿命 90日 / 威力400%・敵行動停止',
  WorldCommand.retreat=>'報酬なし',
 };
 @override Widget build(BuildContext context)=>ListenableBuilder(listenable:widget.controller,builder:(context,child){
  final c=widget.controller,w=c.state.world,b=w.battle,s=b?.stats??c.worldStats;
  final generation=c.restoreGeneration;
  final stage=selectedStage??WorldCatalog.titles.keys.firstWhere((i)=>!w.cleared.contains(WorldCatalog.mainId(i)),orElse:()=>WorldCatalog.titles.keys.last);
  final enemy=b?.encounter;
  return ListView(padding:const EdgeInsets.fromLTRB(16,16,16,32),children:[
   Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(
    gradient:const LinearGradient(colors:[Color(0xff401525),Color(0xff16111f)]),borderRadius:BorderRadius.circular(20),border:Border.all(color:crimson.withValues(alpha:0.45))),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     const Text('MACKY MYTHOLOGY',style:TextStyle(color:gold,letterSpacing:3,fontSize:11,fontWeight:FontWeight.bold)),
     const SizedBox(height:8),
     Text(b==null?'RED AWAKENING':'BATTLE  /  TURN ${b.turn}',style:const TextStyle(fontSize:25,fontWeight:FontWeight.w900,color:Colors.white)),
     const Text('序章 — 紅き覚醒',style:TextStyle(color:Color(0xffd8aab7))),
     const SizedBox(height:12),
     Text('寿命  ${w.lifespan} 日',style:const TextStyle(fontSize:19,color:gold,fontWeight:FontWeight.bold)),
     Text('${w.gold} G   |   武装券 ${w.summonTickets}   |   物資券 ${w.supplyTickets}'),
    ])),
   const SizedBox(height:14),
   panel([const Text('MACKY WILD',style:TextStyle(color:crimson,letterSpacing:2,fontWeight:FontWeight.bold)),
    meter('HP',w.hp,s.hp,crimson),meter('物理エネルギー',w.physical,s.physicalMax,gold),meter('魔法エネルギー',w.magic,s.magicMax,Colors.lightBlueAccent)]),
   if(w.lastResult.isNotEmpty)panel([Text(w.lastResult,style:const TextStyle(color:gold,fontWeight:FontWeight.bold))]),
   if(b!=null&&enemy!=null)...[
    panel([Text('RANK ${enemy.rank}',style:const TextStyle(color:gold,letterSpacing:2)),
     const SizedBox(height:8),Center(child:Icon(Icons.security,size:76,color:crimson.withValues(alpha:0.85))),
     Center(child:Text(enemy.enemy,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:21))),
     meter('ENEMY HP',b.enemyHp,enemy.hp,Colors.deepPurpleAccent),
     if(enemy.regenerationPercent>0)Text('敵再生：最大HPの ${enemy.regenerationPercent}% / 行動終了時'),
     if(b.acceleratedClaws>0)Text('自己加速：紅爪 残り ${b.acceleratedClaws} 回'),
     if(b.stopCooldown>0)Text('停止系共通：CD ${b.stopCooldown}'),
     if(b.slowTurns>0)Text('時間遅延：残り ${b.slowTurns} ターン'),
     const SizedBox(height:8),const Text('次の行動：通常攻撃',style:TextStyle(color:gold))]),
    panel([const Text('COMMAND / 1ターン1コマンド',style:TextStyle(fontWeight:FontWeight.bold)),
     const SizedBox(height:8),
     for(final command in WorldCommand.values)
      Padding(padding:const EdgeInsets.only(bottom:6),child:OutlinedButton(
       onPressed:busy||c.inventoryBusy||c.worldEngine.unavailable(w,command)!=null?null:()=>run(()=>c.worldCommand(command,b.id,b.turn,expectedGeneration:generation)),
       child:Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Row(children:[
        Expanded(child:Text(label(command))),Flexible(child:Text(c.worldEngine.unavailable(w,command)??cost(command,w),textAlign:TextAlign.end,style:const TextStyle(fontSize:11))),
       ])),
      )),
    ]),
    if(b.activeSkills.isNotEmpty)panel([
     const Text('SKILL / 能動スキル',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),
     for(final spec in b.activeSkills)
      Builder(builder:(context){
       final reason=c.worldEngine.activeSkillUnavailable(w,spec.id);
       final battleId=b.id,turn=b.turn,generation=c.restoreGeneration;
       return OutlinedButton(
        key:ValueKey('active-skill-${spec.id}'),
        onPressed:busy||c.inventoryBusy||reason!=null?null:()=>run(()=>c.useBattleActiveSkill(spec.id,battleId,turn,expectedGeneration:generation)),
        child:Text('${spec.name} / ${_activeSkillDescription(c,w,spec)} / ${spec.usesStopCooldown?'共有CD':'CD'} ${c.worldEngine.activeSkillCooldown(b,spec)}${reason==null?'':' / $reason'}'),
       );
      }),
    ]),
    if(b.exAttacks.isNotEmpty)ExBattleSkillPanel(controller:c,busy:busy,run:run),
    panel([const Text('ITEM / 回復アイテム',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),
     if(c.inventoryBusy)const LinearProgressIndicator(),
     if(!c.recoveryItems.any((item)=>(c.state.inventory.stacks[item.id]??0)>0))const Text('使用可能な回復アイテムなし'),
     for(final item in c.recoveryItems.where((item)=>(c.state.inventory.stacks[item.id]??0)>0))
      Builder(builder:(context){
       final evaluation=c.evaluateBattleRecovery(item.id);
       final sequence=w.itemUseSequence,generation=c.restoreGeneration,battleId=b.id,turn=b.turn;
       return OutlinedButton(
        onPressed:busy||c.inventoryBusy||evaluation.amount==null?null:()=>run(() async {
         final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
          title:const Text('回復アイテムを使用しますか？'),
          content:Text('${item.name} × 1 / 回復予定：${evaluation.amount}\n1ターンを消費し、敵の反撃を受けます。'),
          actions:[
           TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('キャンセル')),
           FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('使用を確定')),
          ],
         ));
         if(!mounted||confirmed!=true)return;
         await c.useBattleRecoveryItem(item.id,battleId,turn,sequence,expectedGeneration:generation);
        }),
        child:Text('${item.name} × ${c.state.inventory.stacks[item.id]} / ${evaluation.reason??'回復予定：${evaluation.amount}'}'),
       );
      }),
    ]),
    panel([const Text('BUFF / 状態効果',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),
     if(b.awakeningTurns>0)Text('紅き覚醒：物攻 +${b.awakeningRules.awakeningPercent}% / 残り ${b.awakeningTurns}ターン'),
     if(b.buffs.isEmpty&&b.awakeningTurns==0)const Text('発動中のバフなし'),
     for(final entry in b.buffs.entries)
      Text(entry.key.isCharge?'${entry.key.label}：残り ${entry.value} 回（戦闘終了まで）':'${entry.key.label}：残り ${entry.value} ターン'),
     if(!c.buffItems.any((item)=>(c.state.inventory.stacks[item.id]??0)>0))const Text('所持バフアイテムなし'),
     for(final item in c.buffItems.where((item)=>(c.state.inventory.stacks[item.id]??0)>0))
      Builder(builder:(context){
       final reason=c.battleBuffUnavailable(item.id);
       final sequence=w.itemUseSequence,generation=c.restoreGeneration,battleId=b.id,turn=b.turn;
       final effect=item.kind.description;
       return OutlinedButton(
        key:ValueKey('buff-${item.id}'),
        onPressed:busy||c.inventoryBusy||reason!=null?null:()=>run(() async {
         final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
          title:const Text('バフアイテムを使用しますか？'),
          content:Text('${item.name} × 1\n$effect\n1ターンを消費し、敵の反撃判定が発生します。'),
          actions:[
           TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('キャンセル')),
           FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('使用を確定')),
          ],
         ));
         if(!mounted||confirmed!=true)return;
         await c.useBattleBuffItem(item.id,battleId,turn,sequence,expectedGeneration:generation);
        }),
        child:Text('${item.name} × ${c.state.inventory.stacks[item.id]} / ${reason??effect}'),
       );
      }),
    ]),
    panel([const Text('STATUS / 状態異常',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),
     if(b.statuses.isEmpty)const Text('状態異常なし'),
     for(final entry in b.statuses.entries)
      Text('${entry.key.label}：残り ${entry.value} ターン'),
     for(final item in c.purificationItems.where((item)=>(c.state.inventory.stacks[item.id]??0)>0))
      Builder(builder:(context){
       final reason=c.battlePurificationUnavailable(item.id);
       final sequence=w.itemUseSequence,generation=c.restoreGeneration,battleId=b.id,turn=b.turn;
       final targets=b.statuses.keys.map((kind)=>kind.label).join('・');
       return OutlinedButton(
        key:ValueKey('purification-${item.id}'),
        onPressed:busy||c.inventoryBusy||reason!=null?null:()=>run(() async {
         final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
          title:const Text('浄化アイテムを使用しますか？'),
          content:Text('${item.name} × 1\n解除対象：$targets\n1ターンを消費し、敵の反撃を受けます。'),
          actions:[
           TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('キャンセル')),
           FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('使用を確定')),
          ],
         ));
         if(!mounted||confirmed!=true)return;
         await c.useBattlePurificationItem(item.id,battleId,turn,sequence,expectedGeneration:generation);
        }),
        child:Text('${item.name} × ${c.state.inventory.stacks[item.id]} / ${reason??targets}'),
       );
      }),
    ]),
    panel([const Text('BATTLE LOG',style:TextStyle(color:gold,letterSpacing:2)),const SizedBox(height:8),for(final line in b.log)Padding(padding:const EdgeInsets.symmetric(vertical:3),child:Text(line))]),
   ]else...[
    panel([const Text('ABYSS SUMMON',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),
     FilledButton(onPressed:busy?null:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AbyssSummonScreen(controller:c))),child:const Text('深淵召喚へ')),
    ]),
    panel([const Text('ABYSS EQUIPMENT',style:TextStyle(color:gold,fontWeight:FontWeight.bold)),
     Text('物攻 ${s.physical} / 魔攻 ${s.magic} / 防御 ${s.defense}'),
     FilledButton(onPressed:busy?null:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AbyssForgeScreen(controller:c))),child:const Text('深淵鍛造へ')),
     FilledButton(onPressed:busy?null:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AbyssInventoryScreen(controller:c))),child:const Text('深淵所持品へ')),
     FilledButton(onPressed:busy||!c.ready?null:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AbyssCompendiumScreen(controller:c))),child:const Text('深淵図鑑へ')),
     FilledButton(onPressed:busy||!c.ready?null:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AbyssSkillScreen(controller:c))),child:const Text('スキル管理へ')),
     FilledButton(onPressed:busy?null:()=>Navigator.of(context).push<void>(MaterialPageRoute(builder:(_)=>AbyssShopScreen(controller:c))),child:const Text('深淵商店へ')),
     for(final slot in EquipmentSlot.values)
      Row(children:[Expanded(child:Text('${slot.name}: ${c.equipmentCatalog.find(c.state.inventory.equipment[c.state.inventory.equipped[slot]]?.masterId??'')?.name??'未装着'}')),
       if(c.state.inventory.equipped.containsKey(slot))TextButton(onPressed:busy||c.inventoryBusy||!c.ready?null:()=>run(()=>c.unequipWorldItem(slot,expectedGeneration:generation)),child:const Text('解除'))]),
     if(c.state.inventory.equipment.isEmpty)const Text('所持装備なし'),
     for(final item in c.state.inventory.equipment.values)
      if(c.equipmentCatalog.find(item.masterId)!=null&&!c.state.inventory.equipped.containsValue(item.id))
       OutlinedButton(onPressed:busy||c.inventoryBusy||c.exEquipUnavailable(item)!=null?null:()=>run(()=>c.equipWorldItem(item.id,expectedGeneration:generation)),child:Text('${c.equipmentCatalog.find(item.masterId)!.name} / ${item.id} を装着${c.exEquipUnavailable(item)==null?'':' / ${c.exEquipUnavailable(item)}'}')),
    ]),
    if(c.exManualPlanningAvailable)ExManualSlotPanel(controller:c,busy:busy,run:run),
    if(c.exBattleUnavailable() case final reason?)Text(reason),
    panel([Text('PROLOGUE   ${w.cleared.where((id)=>id.endsWith("_main")).length} / 21',style:const TextStyle(color:gold,letterSpacing:2)),
     const SizedBox(height:10),
     for(final entry in WorldCatalog.titles.entries)
      Padding(padding:const EdgeInsets.only(bottom:8),child:ListTile(
       shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(10),side:BorderSide(color:stage==entry.key?crimson:const Color(0xff49303f))),
       selected:stage==entry.key,onTap:()=>setState(()=>selectedStage=entry.key),
       leading:Icon(w.cleared.contains(WorldCatalog.mainId(entry.key))?Icons.check_circle:entry.key==1||w.cleared.contains(WorldCatalog.mainId(entry.key-1))?Icons.flash_on:Icons.lock,color:crimson),
       title:Text('STAGE ${entry.key.toString().padLeft(2,"0")}'),subtitle:Text(entry.value),
       trailing:const Icon(Icons.chevron_right))),
     const Text('STAGE 04〜21 は後続アップデートで解放',style:TextStyle(color:Colors.white54,fontSize:12)),
    ]),
    for(final e in WorldCatalog.encounters.where((e)=>e.stage==stage))
     panel([Text(e.main?'MAIN STORY':'FREE QUEST',style:const TextStyle(color:gold,letterSpacing:2,fontSize:11)),
      const SizedBox(height:5),Text(e.title,style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
      Text('${e.enemy}  /  RANK ${e.rank}'),
      Text('HP ${e.hp}   報酬 ${e.gold} G${e.lifeDays>0?' / 寿命 +${e.lifeDays}日':''}'),
      const SizedBox(height:10),
      SizedBox(width:double.infinity,child:FilledButton(
       onPressed:busy||c.inventoryBusy||c.exBattleUnavailable()!=null||w.hp==0||!c.worldEngine.isUnlocked(w,e)||c.worldEngine.victoryRewardUnavailable(w,e)!=null?null:()=>run(()=>c.startWorldBattle(e.id)),
       child:Text(e.main&&w.cleared.contains(e.id)?'クリア済み':!c.worldEngine.isUnlocked(w,e)?'未解放':w.hp==0?'HP回復待ち':c.worldEngine.victoryRewardUnavailable(w,e)??'戦闘開始'))),
     ]),
   ],
  ]);
 });
}
