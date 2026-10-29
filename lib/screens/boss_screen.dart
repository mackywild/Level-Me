import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../controllers/app_controller.dart';
import '../widgets/panel.dart';

class BossScreen extends StatefulWidget {
 const BossScreen({super.key,required this.controller});
 final AppController controller;
 @override State<BossScreen> createState()=>_BossScreenState();
}
class _BossScreenState extends State<BossScreen> with SingleTickerProviderStateMixin {
 late final AnimationController _animation=AnimationController(vsync:this,duration:const Duration(milliseconds:700));
 bool busy=false;
 String event='クエストで力を蓄え、攻撃のタイミングを決めよう。';
 @override void dispose(){_animation.dispose();super.dispose();}
 Future<void> _attack(bool magic) async{
  if(busy)return;
  setState((){busy=true;event=magic?'魔法を詠唱中…':'攻撃を繰り出す…';});
  await _animation.forward(from:0);
  if(!mounted)return;
  final result=await widget.controller.attackBoss(magic:magic);
  if(!mounted)return;
  if(result==null){setState((){busy=false;event='体力か攻撃エネルギーが足りません。';});return;}
  setState(()=>event=result.defeated
   ?'討伐成功！ ${result.damage}ダメージ。討伐報酬を獲得！'
   :'敵に${result.damage}ダメージ！ 反撃で${result.counterDamage}ダメージを受けた。');
  await Future<void>.delayed(const Duration(milliseconds:500));
  if(mounted)setState(()=>busy=false);
 }
 Future<void> _draw() async{
  if(busy)return;
  setState(()=>busy=true);
  final reward=await widget.controller.drawBattleReward();
  if(!mounted)return;
  setState((){busy=false;event=reward??'ガチャ券がありません。';});
  if(reward!=null){await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
   title:const Text('戦闘報酬を獲得！'),content:Text(reward),
   actions:[FilledButton(onPressed:()=>Navigator.pop(ctx),child:const Text('受け取る'))]));}
 }
 @override Widget build(BuildContext context){
  final state=widget.controller.state,b=state.boss;
  final alive=state.playerHp>0;
  return ListView(padding:const EdgeInsets.fromLTRB(16,12,16,120),children:[
   Text('ボス戦',style:Theme.of(context).textTheme.headlineSmall),
   const SizedBox(height:12),
   Panel(child:Column(children:[
    SizedBox(height:240,width:double.infinity,child:AnimatedBuilder(
     animation:_animation,builder:(context,child)=>Transform.translate(
      offset:Offset(math.sin(_animation.value*math.pi*5)*(_animation.isAnimating?8:0),0),
      child:CustomPaint(painter:_ShadowDragonPainter(glow:_animation.value))),
    )),
    Text(b.title,textAlign:TextAlign.center,style:Theme.of(context).textTheme.titleLarge),
    Text(b.description,textAlign:TextAlign.center),
    const SizedBox(height:14),
    Row(children:[const Text('ボスの体力'),const Spacer(),Text('${b.hp} / ${b.maxHp}')]),
    LinearProgressIndicator(value:(b.hp/b.maxHp).clamp(0,1),minHeight:12,color:Colors.redAccent),
    const SizedBox(height:12),
    Row(children:[const Text('あなたの体力'),const Spacer(),Text('${state.playerHp} / ${state.maxPlayerHp}')]),
    LinearProgressIndicator(value:(state.playerHp/state.maxPlayerHp).clamp(0,1),minHeight:12,color:Colors.greenAccent),
    const SizedBox(height:12),
    Text('攻撃エネルギー ${state.attackEnergy}　／　討伐数 ${b.defeats}'),
   ])),
   const SizedBox(height:12),
   Card(child:Padding(padding:const EdgeInsets.all(16),child:Text(event,textAlign:TextAlign.center))),
   const SizedBox(height:12),
   if(!alive)const Padding(padding:EdgeInsets.all(12),child:Text('戦闘不能：翌日かレベルアップで全回復します。タスクは引き続き達成できます。')),
   Row(children:[
    Expanded(child:FilledButton.icon(onPressed:busy||!alive||state.attackEnergy<1?null:()=>_attack(false),
     icon:const Icon(Icons.sports_martial_arts),label:const Text('物理攻撃'))),
    const SizedBox(width:10),
    Expanded(child:FilledButton.tonalIcon(onPressed:busy||!alive||state.attackEnergy<1?null:()=>_attack(true),
     icon:const Icon(Icons.auto_fix_high),label:const Text('魔法攻撃'))),
   ]),
   const SizedBox(height:12),
   OutlinedButton.icon(onPressed:busy||state.gachaTickets<1?null:_draw,
    icon:const Icon(Icons.card_giftcard),label:Text('戦闘報酬ガチャ（残り${state.gachaTickets}回）')),
   const SizedBox(height:12),
   const Text('タスク達成で攻撃エネルギーとガチャ券を獲得。筋トレで体力が回復し、最大体力も成長します。知力が高いほど魔法攻撃が強力になります。'),
  ]);
 }
}
class _ShadowDragonPainter extends CustomPainter{
 const _ShadowDragonPainter({required this.glow});
 final double glow;
 @override void paint(Canvas canvas,Size size){
  final c=Offset(size.width/2,size.height/2);
  canvas.save();
  canvas.translate(c.dx,c.dy);
  final scale=math.min(size.width/320,size.height/230);
  canvas.scale(scale);
  final aura=Paint()..shader=RadialGradient(colors:[
   Color.lerp(const Color(0xFF7D35E9),const Color(0xFFFF324B),glow)!.withValues(alpha:.48),
   const Color(0x00210040)]).createShader(const Rect.fromLTWH(-160,-110,320,220));
  canvas.drawOval(const Rect.fromLTWH(-155,-112,310,220),aura);
  final wing=Paint()..color=const Color(0xFF39295D)..style=PaintingStyle.fill;
  final left=Path()..moveTo(-22,20)..quadraticBezierTo(-95,-120,-155,-83)
   ..lineTo(-132,-30)..lineTo(-153,9)..lineTo(-92,-5)..lineTo(-113,56)..close();
  canvas.drawPath(left,wing);
  canvas.save();canvas.scale(-1,1);canvas.drawPath(left,wing);canvas.restore();
  final body=Paint()..shader=const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,
   colors:[Color(0xFF8A6ABD),Color(0xFF1B1834),Color(0xFF0B0C18)])
   .createShader(const Rect.fromLTWH(-90,-95,180,210));
  final torso=Path()..moveTo(-37,-38)..lineTo(-66,32)..lineTo(-40,96)..lineTo(0,111)
   ..lineTo(40,96)..lineTo(66,32)..lineTo(37,-38)..close();
  canvas.drawPath(torso,body);
  final head=Path()..moveTo(-53,-52)..lineTo(-73,-105)..lineTo(-27,-79)
   ..lineTo(0,-94)..lineTo(27,-79)..lineTo(73,-105)..lineTo(53,-52)
   ..lineTo(39,-11)..lineTo(0,8)..lineTo(-39,-11)..close();
  canvas.drawPath(head,body);
  final ridge=Paint()..color=const Color(0xFF9E7BD9)..strokeWidth=3..style=PaintingStyle.stroke;
  canvas.drawLine(const Offset(0,-79),const Offset(0,80),ridge);
  final eyes=Paint()..color=const Color(0xFFFF465E);
  canvas.drawOval(const Rect.fromLTWH(-36,-45,21,8),eyes);
  canvas.drawOval(const Rect.fromLTWH(15,-45,21,8),eyes);
  final horn=Paint()..color=const Color(0xFFB4A0D9);
  for(final side in [-1.0,1.0]){
   final p=Path()..moveTo(side*43,-70)..lineTo(side*84,-124)..lineTo(side*53,-48)..close();
   canvas.drawPath(p,horn);
  }
  canvas.restore();
 }
 @override bool shouldRepaint(covariant _ShadowDragonPainter old)=>old.glow!=glow;
}
