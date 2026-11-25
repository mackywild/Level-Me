import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';
import 'package:level_me/world/abyss_buff.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _FixedRandom implements Random {
 @override double nextDouble()=>0.5;
 @override bool nextBool()=>false;
 @override int nextInt(int max)=>0;
}
class _DelayedStore extends LocalStore {
 _DelayedStore(Directory dir):super(directory:dir);
 Completer<void>? gate,entered;
 bool fail=false;
 @override Future<void> save(AppStateData state) async {
  if(gate!=null){entered!.complete();await gate!.future;}
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}
void main(){
 const now=1700000000000;
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 const item=BuffItem(id:'item:regen_test',name:'試験再生薬',kind:BattleBuff.regeneration);
 final catalog=BuffCatalog(const [item]);
 final stats=WorldStats.fromRanks(level:1,fitness:1,intelligence:1,discipline:1,creativity:1);
 test('再生は使用ターンに発生せず、次ターンから経過し重複不可',(){
  final s=AppStateData.initial();
  final engine=WorldEngine();
  engine.start(s.world,stats,'p01_main',now);
  final b=s.world.battle!;
  s.inventory.addStack(item.id,2);
  s.world.hp=60;
  final attack=engine.damage(WorldCatalog.byId(b.encounterId).attack,stats.defense,1);
  catalog.use(world:s.world,inventory:s.inventory,id:item.id,expectedSequence:0,battleId:b.id,turn:1,engine:engine,now:now);
  expect(s.world.hp,60-attack);
  expect(b.buffs[BattleBuff.regeneration],5);
  final before=jsonEncode(s.toJson());
  expect(()=>catalog.use(world:s.world,inventory:s.inventory,id:item.id,expectedSequence:1,battleId:b.id,turn:2,engine:engine,now:now),throwsStateError);
  expect(jsonEncode(s.toJson()),before);
  final restored=AppStateData.fromJson(jsonDecode(before) as Map<String,dynamic>);
  expect(restored.world.battle!.buffs[BattleBuff.regeneration],5);
  engine.act(s.world,WorldCommand.guard,b.id,2,now);
  expect(b.buffs[BattleBuff.regeneration],4);
  expect(s.world.hp,60-attack-engine.damage(WorldCatalog.byId(b.encounterId).attack,stats.defense,0.5)+5);
 });
 test('旧戦闘セーブと不正な効果を検証する',(){
  final s=AppStateData.initial();
  WorldEngine().start(s.world,stats,'p01_main',now);
  final raw=s.world.battle!.toJson()..remove('buffs');
  expect(WorldBattle.fromJson(raw).buffs,isEmpty);
  for(final invalid in [null,{'attack':0},{'defense':4},{'unknown':1},{'regeneration':1.5}]){
   expect(()=>WorldBattle.fromJson({...raw,'buffs':invalid}),throwsFormatException);
  }
 });
 test('実ファイル保存と再起動後の二重使用拒否',() async {
  final dir=await Directory.systemTemp.createTemp('battle-buff-');
  addTearDown(()=>dir.delete(recursive:true));
  final c=AppController(LocalStore(directory:dir),buffCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.inventory.addStack(item.id,2);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id;
  await c.useBattleBuffItem(item.id,id,1,0,expectedGeneration:c.restoreGeneration);
  final restored=AppController(LocalStore(directory:dir),buffCatalog:catalog,clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.buffs[BattleBuff.regeneration],5);
  expect(restored.state.inventory.stacks[item.id],1);
  expect(restored.state.world.itemUseSequence,1);
  await expectLater(restored.useBattleBuffItem(item.id,id,1,0,expectedGeneration:restored.restoreGeneration),throwsStateError);
 });
 test('未承認効果を起動・外部import・端末内復元・journalで拒否する',() async {
  final dir=await Directory.systemTemp.createTemp('buff-approval-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=LocalStore(directory:dir);
  final portable=PortableBackup(directory:dir);
  final c=AppController(store,portableBackup:portable,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  await c.startWorldBattle('p01_main');
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final bytes=await primary.readAsString();
  final raw=jsonDecode(await c.exportPortableBackup()) as Map<String,dynamic>;
  final player=raw['files'][PortableBackup.playerName] as Map<String,dynamic>;
  player['world']['battle']['buffs']={'regeneration':5};
  final rejected=jsonEncode(raw);
  await expectLater(c.importPortableBackup(rejected),throwsFormatException);
  expect(await primary.readAsString(),bytes);
  final backup=File('${primary.path}.bak');
  await backup.writeAsString(jsonEncode(player));
  await expectLater(c.restoreBackup(),throwsFormatException);
  expect(await primary.readAsString(),bytes);
  final journal=File('${dir.path}/${PortableBackup.journalName}');
  await journal.writeAsString(rejected);
  final blocked=AppController(LocalStore(directory:dir),portableBackup:PortableBackup(directory:dir),clockMs:()=>now);
  addTearDown(blocked.dispose);
  await expectLater(blocked.initialize(),throwsFormatException);
  expect(await primary.readAsString(),bytes);
  expect(await journal.readAsString(),rejected);
  await journal.delete();
  await primary.writeAsString(jsonEncode(player));
  await expectLater(blocked.initialize(),throwsFormatException);
  expect(await primary.readAsString(),jsonEncode(player));
  final allowed=AppController(LocalStore(directory:dir),portableBackup:PortableBackup(directory:dir),buffCatalog:catalog,clockMs:()=>now);
  addTearDown(allowed.dispose);
  await allowed.initialize();
  expect(allowed.state.world.battle!.buffs[BattleBuff.regeneration],5);
  await allowed.importPortableBackup(rejected);
  expect(allowed.state.world.battle!.buffs[BattleBuff.regeneration],5);
 });
 test('攻撃補正は紅爪・連爪・魔法・複合爪撃と加速に適用される',(){
  for(final command in [WorldCommand.claw,WorldCommand.heavyClaw,WorldCommand.magic,WorldCommand.compositeClaw]){
   for(final accelerated in [false,true]){
    for(final buffed in [false,true]){
     final engine=WorldEngine(random:_FixedRandom());
     final s=AppStateData.initial();
     const low=WorldStats(hp:100,physical:5,magic:5,defense:10,physicalMax:27,magicMax:38,crit:0);
     engine.start(s.world,low,'p01_main',now);
     final b=s.world.battle!;
     s.world.cleared.addAll(['p06_main','p12_main']);
     s.world.lifespan=BigInt.from(100);
     if(buffed)engine.finishBuffTurn(s.world,BattleBuff.attack,b.id,b.turn,now,'攻撃強化');
     if(accelerated)b.acceleratedClaws=2;
     final enemy=WorldCatalog.byId(b.encounterId);
     final old=b.enemyHp;
     final multiplier=switch(command){
      WorldCommand.claw=>accelerated?2.0:1.0,
      WorldCommand.heavyClaw=>1.8,
      WorldCommand.magic=>1.2,
      WorldCommand.compositeClaw=>4.0,
      _=>throw StateError('Unexpected command'),
     };
     final expected=engine.damage(5,enemy.defense,multiplier*(buffed?1.25:1.0));
     engine.act(s.world,command,b.id,b.turn,now);
     expect(b.enemyHp,max(0,old-expected));
    }
   }
  }
 });
 test('防御は発動時と次3ターンに適用され、異種併用・満了を処理する',(){
  final engine=WorldEngine();
  final s=AppStateData.initial();
  engine.start(s.world,stats,'p01_main',now);
  final b=s.world.battle!;
  final enemy=WorldCatalog.byId(b.encounterId);
  b.slowTurns=2;
  engine.finishBuffTurn(s.world,BattleBuff.defense,b.id,b.turn,now,'防御');
  expect(s.world.hp,100-engine.damage(enemy.attack,14,0.7));
  expect(b.buffs[BattleBuff.defense],3);
  final before=s.world.hp;
  engine.act(s.world,WorldCommand.guard,b.id,b.turn,now);
  expect(s.world.hp,before-engine.damage(enemy.attack,14,0.7*0.5));
  engine.finishBuffTurn(s.world,BattleBuff.attack,b.id,b.turn,now,'攻撃');
  expect(b.buffs[BattleBuff.defense],1);
  expect(b.buffs[BattleBuff.attack],3);
  engine.act(s.world,WorldCommand.guard,b.id,b.turn,now);
  expect(b.buffs.containsKey(BattleBuff.defense),false);
  expect(b.buffs[BattleBuff.attack],2);
  engine.act(s.world,WorldCommand.retreat,b.id,b.turn,now);
  expect(s.world.battle,isNull);
 });
 test('再生は5回で満了し停止中も経過、敗北時は発動しない',(){
  final engine=WorldEngine();
  final s=AppStateData.initial();
  engine.start(s.world,stats,'p01_main',now);
  final b=s.world.battle!;
  s.world.hp=90;
  engine.finishBuffTurn(s.world,BattleBuff.regeneration,b.id,b.turn,now,'再生');
  s.world.cleared.add('p12_main');
  s.world.lifespan=BigInt.from(100);
  for(var i=0;i<5;i++){
   s.world.hp=90;
   final command=i==0?WorldCommand.stopTime:WorldCommand.guard;
   engine.act(s.world,command,b.id,b.turn,now);
   expect(b.buffs[BattleBuff.regeneration],i==4?null:4-i);
   expect(b.log.last,contains('継続回復'));
  }
  engine.finishBuffTurn(s.world,BattleBuff.regeneration,b.id,b.turn,now,'再生');
  s.world.hp=1;
  engine.finishRecoveryTurn(s.world,b.id,b.turn,now,'試験',1);
  expect(s.world.battle,isNull);
  expect(s.world.hp,0);
 });
 test('遅延保存失敗と通常コマンド競合・復元世代拒否',() async {
  final dir=await Directory.systemTemp.createTemp('buff-transaction-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_DelayedStore(dir);
  final c=AppController(store,portableBackup:PortableBackup(directory:dir),buffCatalog:catalog,clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  c.state.inventory.addStack(item.id,2);
  await c.startWorldBattle('p01_main');
  final id=c.state.world.battle!.id,generation=c.restoreGeneration;
  final raw=await c.exportPortableBackup();
  final before=jsonEncode(c.state.toJson());
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final bytes=await primary.readAsString();
  store.gate=Completer<void>();
  store.entered=Completer<void>();
  store.fail=true;
  final failed=expectLater(c.useBattleBuffItem(item.id,id,1,0,expectedGeneration:generation),throwsStateError);
  await store.entered!.future;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  await expectLater(c.useBattleBuffItem(item.id,id,1,0,expectedGeneration:generation),throwsStateError);
  store.gate!.complete();
  await failed;
  expect(jsonEncode(c.state.toJson()),before);
  expect(await primary.readAsString(),bytes);
  store.gate=null;
  store.fail=false;
  final action=c.useBattleBuffItem(item.id,id,1,0,expectedGeneration:generation);
  final stale=expectLater(c.worldCommand(WorldCommand.guard,id,1),throwsStateError);
  await action;
  await stale;
  expect(c.state.world.battle!.turn,2);
  expect(c.state.inventory.stacks[item.id],1);
  await c.importPortableBackup(raw);
  await expectLater(c.useBattleBuffItem(item.id,id,1,0,expectedGeneration:generation),throwsStateError);
  expect(c.state.inventory.stacks[item.id],2);
  expect(c.state.world.battle!.buffs,isEmpty);
 });
}
