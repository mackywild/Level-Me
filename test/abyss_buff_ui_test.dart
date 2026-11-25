import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/screens/world_screen.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_buff.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Rolls implements Random {
 _Rolls(this.values);
 final List<double> values;
 int reads=0;
 @override double nextDouble()=>values[reads++];
 @override bool nextBool()=>false;
 @override int nextInt(int max)=>0;
}
class _Store extends LocalStore {
 String? data;
 @override Future<AppStateData> load() async=>data==null?AppStateData.initial():AppStateData.fromJson(jsonDecode(data!) as Map<String,dynamic>);
 @override Future<void> save(AppStateData state) async{data=jsonEncode(state.toJson());}
}
void main(){
 const now=1700000000000;
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const stats=WorldStats(hp:100,physical:2,magic:2,defense:10,physicalMax:27,magicMax:38,crit:0.05);
 test('会心率の加算境界と非発動時の乱数消費',(){
  for(final buffed in [false,true]){
   for(final roll in [0.299,0.301]){
    final rng=_Rolls([roll,0.5]);
    final engine=WorldEngine(random:rng);
    final s=AppStateData.initial();
    engine.start(s.world,stats,'p01_main',now);
    final b=s.world.battle!;
    if(buffed)engine.finishBuffTurn(s.world,BattleBuff.critical,b.id,b.turn,now,'会心');
    engine.act(s.world,WorldCommand.claw,b.id,b.turn,now);
    expect(b.log.any((line)=>line.contains('会心！')),buffed&&roll<0.30);
    expect(rng.reads,2);
   }
  }
 });
 test('回避境界と発動ターン、満了、無バフ時の乱数非消費',(){
  final rng=_Rolls([0.199,0.20,0.199]);
  final engine=WorldEngine(random:rng);
  final s=AppStateData.initial();
  engine.start(s.world,stats,'p01_main',now);
  final b=s.world.battle!;
  engine.finishBuffTurn(s.world,BattleBuff.evasion,b.id,b.turn,now,'回避');
  expect(s.world.hp,100);
  expect(b.buffs[BattleBuff.evasion],2);
  engine.act(s.world,WorldCommand.guard,b.id,b.turn,now);
  expect(s.world.hp,lessThan(100));
  final hp=s.world.hp;
  engine.act(s.world,WorldCommand.guard,b.id,b.turn,now);
  expect(s.world.hp,hp);
  expect(b.buffs.containsKey(BattleBuff.evasion),false);
  engine.act(s.world,WorldCommand.guard,b.id,b.turn,now);
  expect(rng.reads,3);
 });
 test('候補7種は非公開、無断有効化・ID衝突・性能不一致を拒否',(){
  Map<String,dynamic> raw()=>jsonDecode(File(AbyssMaster.assetPath).readAsStringSync()) as Map<String,dynamic>;
  final root=raw();
  expect((root['buffs'] as List).length,7);
  root['enabled']=true;
  expect(AbyssMaster.fromJson(jsonEncode(root)).buffs.items,isEmpty);
  for(final change in <void Function(Map<String,dynamic>)>[
   (j){j['buffEnabled']=true;},
   (j){(j['buffs'] as List).first['id']='item:iron';},
   (j){(j['buffs'] as List).first['id']=(j['recovery'] as List).first['id'];},
   (j){(j['buffs'] as List).first['percent']=999;},
   (j){(j['buffs'] as List).first['percent']=25.0;},
   (j){(j['buffs'] as List).first['duration']=3.0;},
   (j){(j['buffs'] as List).first['kind']='unknown';},
   (j){(j['summon'] as List).add({'pool':'supplies','masterId':(j['buffs'] as List).first['id']});},
  ]){
   final j=raw();change(j);
   expect(()=>AbyssMaster.fromJson(jsonEncode(j)),throwsFormatException);
  }
 });
 testWidgets('バフ確認取消・確定・残りターン表示と重複禁止',(tester) async{
  const item=BuffItem(id:'item:buff_test',name:'試験攻撃薬',kind:BattleBuff.attack);
  final c=AppController(_Store(),buffCatalog:BuffCatalog(const [item]),clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.inventory.addStack(item.id,2);
  await c.startWorldBattle('p01_main');
  await tester.pumpWidget(MaterialApp(home:Scaffold(body:WorldScreen(controller:c))));
  final button=find.byKey(const ValueKey('buff-item:buff_test'));
  await tester.scrollUntilVisible(button,300);
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.text('キャンセル'));
  await tester.pumpAndSettle();
  expect(c.state.inventory.stacks[item.id],2);
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.text('使用を確定'));
  await tester.pumpAndSettle();
  expect(c.state.inventory.stacks[item.id],1);
  expect(c.state.world.battle!.turn,2);
  expect(find.text('攻撃強化：残り 3 ターン'),findsOneWidget);
  expect(tester.widget<OutlinedButton>(button).onPressed,isNull);
  expect(tester.takeException(),isNull);
 });
}
