import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/world/abyss_ultimate_candidate.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';
import 'helpers/extended_world_catalog.dart';

class _FixedRandom implements Random {
 @override double nextDouble()=>0.5;
 @override bool nextBool()=>false;
 @override int nextInt(int max)=>0;
}

void main(){
 const now=1700000000000,limit=0x7fffffffffffffff;
 const extreme=WorldStats(hp:limit,physical:limit,magic:limit,defense:limit,physicalMax:limit,magicMax:limit,crit:1);
 const regular=WorldStats(hp:100,physical:40,magic:45,defense:10,physicalMax:27,magicMax:38,crit:0);
 late String master;
 setUpAll(()=>master=File(WorldCatalog.assetPath).readAsStringSync());
 setUp(()=>WorldCatalog.loadJson(master));
 tearDown(()=>WorldCatalog.loadJson(master));
 void change(String id,Map<String,dynamic> fields){
  final raw=jsonDecode(master) as Map<String,dynamic>;
  final row=(raw['encounters'] as List).singleWhere((e)=>e['id']==id) as Map<String,dynamic>;
  row.addAll(fields);
  WorldCatalog.loadJson(jsonEncode(raw));
 }
 test('通常の演算順・最小1・極端な倍率と整数変換の境界',(){
  final engine=WorldEngine();
  expect(engine.damage(40,0,1),40);
  expect(engine.damage(40,100,1),20);
  expect(engine.damage(1,1000,0.25),1);
  expect(engine.damage(0,0,1),1);
  for(final attack in [1,40,45,1000]){
   for(final defense in [0,10,100,1000]){
    for(final multiplier in [0.25,1.0,1.8,4.0,8.0]){
     for(final critical in [1.0,1.5]){
      for(final variance in [0.95,1.0,1.05]){
       final expected=max(1,(attack*multiplier*100/(100.0+defense)*critical*variance).floor());
       expect(engine.damage(attack,defense,multiplier,critical:critical,variance:variance),expected);
      }
     }
    }
   }
  }
  expect(engine.damage(limit,0,8,critical:1.5,variance:1.05),limit);
  expect(engine.damage(limit,0,1),limit);
  expect(engine.damage(limit,0,0.5),4611686018427387904);
  expect(engine.damage(limit,limit,1),100);
  expect(()=>engine.damage(-1,0,1),throwsStateError);
  expect(()=>engine.damage(1,-1,1),throwsStateError);
  for(final bad in [-1.0,double.nan,double.infinity]){
   expect(()=>engine.damage(1,0,bad),throwsStateError);
   expect(()=>engine.damage(1,0,1,critical:bad),throwsStateError);
   expect(()=>engine.damage(1,0,1,variance:bad),throwsStateError);
  }
  expect(()=>engine.damage(limit,0,double.maxFinite),throwsStateError);
 });
 test('自然回復の積と加算を上限前で止め、時刻余りも維持',(){
  final engine=WorldEngine();
  final w=WorldState(hp:limit-1,physical:limit-1,magic:limit-2,energyAt:1,hpAt:1);
  engine.refresh(w,extreme,limit);
  expect([w.hp,w.physical,w.magic],[limit,limit,limit]);
  expect(w.energyAt,1+(limit-1)~/WorldEngine.energyInterval*WorldEngine.energyInterval);
  expect(w.hpAt,1+(limit-1)~/WorldEngine.hpInterval*WorldEngine.hpInterval);
  expect(WorldState.fromJson(w.toJson()).toJson(),w.toJson());
  final partial=WorldState(hp:1,physical:0,magic:0,energyAt:1,hpAt:1);
  engine.refresh(partial,extreme,1+WorldEngine.hpInterval);
  expect(partial.hp,1+limit~/20);
  expect(partial.physical,3);
  expect(partial.magic,3);
  final reduced=WorldState(hp:limit,physical:limit,magic:limit,energyAt:now,hpAt:now);
  engine.refresh(reduced,regular,now);
  expect([reduced.hp,reduced.physical,reduced.magic],[100,27,38]);
 });
 test('戦闘中の保留回復・撤退後反映・直接回復で加算が桁あふれしない',(){
  final engine=WorldEngine(),w=WorldState();
  engine.start(w,extreme,'p01_main',now);
  w.physical=limit-1;w.magic=limit-2;
  engine.rewardEffort(w,extreme,now,physical:limit,magic:limit,levelUp:false);
  engine.rewardEffort(w,extreme,now,physical:limit,magic:limit,levelUp:false);
  expect([w.pendingPhysical,w.pendingMagic],[limit,limit]);
  expect([w.physical,w.magic],[limit-1,limit-2]);
  final restored=WorldState.fromJson(w.toJson());
  engine.act(restored,WorldCommand.retreat,restored.battle!.id,1,now);
  engine.refresh(restored,extreme,now);
  expect([restored.physical,restored.magic],[limit,limit]);
  expect([restored.pendingPhysical,restored.pendingMagic],[0,0]);
  engine.rewardEffort(restored,extreme,now,physical:limit,magic:limit,levelUp:false);
  expect([restored.physical,restored.magic],[limit,limit]);
  final before=jsonEncode(restored.toJson());
  expect(()=>engine.rewardEffort(restored,extreme,now,physical:-1,magic:0,levelUp:false),throwsStateError);
  expect(jsonEncode(restored.toJson()),before);
 });
 test('最大HPの敵に800%奥義・会心を適用し勝利と寿命を一括確定',(){
  loadExtendedWorldCatalog(21);
  final spec=WorldCollapseSkillCandidate.definition.execution!;
  // 拡張masterのまま敵HPだけ最大にした保存snapshotで試験する。
  final engine=WorldEngine(random:_FixedRandom()),w=WorldState(cleared:{'p21_main'},lifespan:BigInt.from(730));
  engine.start(w,extreme,'p01_main',now,activeSkills:[spec]);
  final raw=w.toJson(),battle=w.battle!.toJson();
  final snapshot={...(battle['encounterSnapshot'] as Map<String,dynamic>),'hp':limit};
  final restored=WorldState.fromJson({...raw,'battle':{...battle,'enemyHp':limit,'encounterSnapshot':snapshot}});
  engine.actActiveSkill(restored,spec.id,restored.battle!.id,1,now);
  expect(restored.battle,isNull);
  expect(restored.hp,limit);
  expect(restored.lifespan,BigInt.zero);
  expect(restored.gold,40);
  expect(restored.summonTickets,3);
 });
 test('極端な敵反撃と防御強化・致死耐性・継続回復を安全に処理',(){
  change('p01_main',{'attack':limit});
  final engine=WorldEngine(),w=WorldState();
  engine.start(w,extreme,'p01_main',now);
  final b=w.battle!,raw=w.toJson();
  final saved=WorldState.fromJson({...raw,'battle':{...b.toJson(),'buffs':{'defense':3,'regeneration':5}}});
  engine.act(saved,WorldCommand.guard,b.id,1,now);
  expect(saved.hp,limit);
  expect(saved.battle!.turn,2);
  final fragile=WorldState(hp:1,energyAt:now,hpAt:now);
  engine.start(fragile,regular,'p01_main',now);
  final low=fragile.battle!;
  // 防御で極端な反撃を受け、致死耐性の消費と次ターンの敗北を検証する。
  final guarded=WorldState.fromJson({...fragile.toJson(),'battle':{...low.toJson(),'buffs':{'lethalProtection':1}}});
  engine.act(guarded,WorldCommand.guard,low.id,1,now);
  expect(guarded.hp,1);
  expect(guarded.battle!.buffs.containsKey(BattleBuff.lethalProtection),false);
  engine.act(guarded,WorldCommand.guard,low.id,2,now);
  expect(guarded.hp,0);
  expect(guarded.battle,isNull);
 });
 test('実ファイル：最大敵攻撃を固定し再起動後の敗北を正常保存',() async{
  change('p01_main',{'attack':limit});
  final dir=await Directory.systemTemp.createTemp('battle-arithmetic-');
  addTearDown(()=>dir.delete(recursive:true));
  final c=AppController(LocalStore(directory:dir),clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  WorldCatalog.loadJson(master);
  final restored=AppController(LocalStore(directory:dir),clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.encounter.attack,limit);
  await restored.worldCommand(WorldCommand.guard,id,1,expectedGeneration:restored.restoreGeneration);
  expect(restored.state.world.battle,isNull);
  expect(restored.state.world.hp,0);
  expect(restored.state.world.gold,0);
  final again=AppController(LocalStore(directory:dir),clockMs:()=>now);
  addTearDown(again.dispose);
  await again.initialize();
  expect(again.state.world.hp,0);
  expect(again.state.world.battle,isNull);
 });
}
