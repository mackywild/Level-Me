import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/controllers/app_controller.dart';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';
import 'package:level_me/services/portable_backup.dart';
import 'package:level_me/world/abyss_equipment.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_skill.dart';
import 'package:level_me/world/world_catalog.dart';
import 'package:level_me/world/world_engine.dart';

class _Store extends LocalStore {
 _Store(Directory dir):super(directory:dir);
 bool fail=false;
 @override Future<void> save(AppStateData state) async{
  if(fail)throw StateError('Simulated save failure');
  await super.save(state);
 }
}

void main(){
 const now=1700000000000;
 const a=SkillDefinition(id:'skill:test_power',name:'試験物攻',kind:SkillKind.passive,passiveBonus:PassiveStatBonus(physical:10,defense:2));
 const b=SkillDefinition(id:'skill:test_magic',name:'試験魔攻',kind:SkillKind.passive,passiveBonus:PassiveStatBonus(magic:15));
 const p=SkillDefinition(id:'skill:test_empty',name:'効果未定',kind:SkillKind.passive);
 final catalog=SkillCatalog(const [a,b,p]);
 const base=WorldStats(hp:100,physical:40,magic:45,defense:10,physicalMax:27,magicMax:38,crit:0.05);
 setUpAll(()=>WorldCatalog.loadJson(File(WorldCatalog.assetPath).readAsStringSync()));
 test('習得のみでは無効、装着順非依存、解除後は補正を除く',(){
  final w=WorldState(),s=SkillState();
  for(final def in catalog.definitions){catalog.learn(w,s,def.id);}
  expect(catalog.applyPassive(base,s).toJson(),base.toJson());
  catalog.equip(w,s,a.id);
  catalog.equip(w,s,b.id);
  catalog.equip(w,s,p.id);
  final before=jsonEncode(s.toJson());
  final expected={...base.toJson(),'physical':50,'magic':60,'defense':12};
  expect(catalog.applyPassive(base,s).toJson(),expected);
  expect(catalog.applyPassive(base,s).toJson(),expected);
  expect(jsonEncode(s.toJson()),before);
  final reverse=SkillState();
  for(final def in catalog.definitions){catalog.learn(w,reverse,def.id);}
  for(final def in catalog.definitions.reversed){catalog.equip(w,reverse,def.id);}
  expect(catalog.applyPassive(base,reverse).toJson(),expected);
  catalog.unequip(w,s,a.id);
  expect(catalog.applyPassive(base,s).toJson(),{...base.toJson(),'magic':60});
  expect(s.learned.containsKey(a.id),true);
 });
 test('装備強化補正の後に固定値を加算し、上限系は維持',(){
  final inv=AbyssInventory();
  const equipment=EquipmentDefinition(id:'equipment:test',name:'試験装備',slot:EquipmentSlot.head,rarity:EquipmentRarity.n,physical:20,magic:10,defense:4);
  final item=inv.addEquipment(equipment.id,equipment.slot,equipment.rarity);
  inv.enhance(item.id,0);
  inv.equip(item.id);
  final equipped=EquipmentCatalog(const [equipment]).apply(base,inv,scaling:const EnhancementScaling.proposed());
  final w=WorldState(),s=SkillState();
  catalog.learn(w,s,a.id);
  catalog.equip(w,s,a.id);
  final result=catalog.applyPassive(equipped,s);
  expect(result.toJson(),{...base.toJson(),'physical':71,'magic':55,'defense':16});
 });
 test('不正補正・能動への誤設定・整数上限を拒否',(){
  for(final bonus in const [PassiveStatBonus(physical:-1),PassiveStatBonus(magic:1000001),PassiveStatBonus(defense:-1)]){
   expect(()=>SkillCatalog([SkillDefinition(id:'skill:bad',name:'不正',kind:SkillKind.passive,passiveBonus:bonus)]),throwsFormatException);
  }
  expect(()=>SkillCatalog(const [SkillDefinition(id:'skill:bad',name:'不正',kind:SkillKind.active,passiveBonus:PassiveStatBonus(physical:1))]),throwsFormatException);
  final w=WorldState(),s=SkillState();
  catalog.learn(w,s,a.id);
  catalog.equip(w,s,a.id);
  const huge=WorldStats(hp:100,physical:0x7fffffffffffffff,magic:45,defense:10,physicalMax:27,magicMax:38,crit:0.05);
  expect(()=>catalog.applyPassive(huge,s),throwsStateError);
  expect(()=>SkillCatalog.production.applyPassive(base,s),throwsFormatException);
 });
 test('実ファイル：装着保存失敗・戦闘開始固定・再起動と外部復元',() async{
  final dir=await Directory.systemTemp.createTemp('passive-skill-');
  addTearDown(()=>dir.delete(recursive:true));
  final store=_Store(dir);
  final c=AppController(store,skillCatalog:catalog,portableBackup:PortableBackup(directory:dir),clockMs:()=>now);
  addTearDown(c.dispose);
  await c.initialize();
  final initial=await c.exportPortableBackup();
  final gen=c.restoreGeneration,original=c.worldStats.toJson();
  await c.learnWorldSkill(a.id,expectedGeneration:gen,expectedRevision:0);
  expect(c.worldStats.toJson(),original);
  final primary=File('${dir.path}/${LocalStore.fileName}');
  final before=await primary.readAsString();
  store.fail=true;
  await expectLater(c.equipWorldSkill(a.id,expectedGeneration:gen,expectedRevision:1),throwsStateError);
  expect(c.state.skills.revision,1);
  expect(c.worldStats.toJson(),original);
  expect(await primary.readAsString(),before);
  store.fail=false;
  await c.equipWorldSkill(a.id,expectedGeneration:gen,expectedRevision:1);
  final boosted=c.worldStats.toJson();
  expect(boosted['physical'],(original['physical'] as int)+10);
  expect(boosted['defense'],(original['defense'] as int)+2);
  await c.startWorldBattle('p01_main');
  final snapshot=c.state.world.battle!.stats.toJson();
  expect(snapshot,boosted);
  await expectLater(c.unequipWorldSkill(a.id,expectedGeneration:gen,expectedRevision:2),throwsStateError);
  final restored=AppController(LocalStore(directory:dir),skillCatalog:catalog,portableBackup:PortableBackup(directory:dir),clockMs:()=>now);
  addTearDown(restored.dispose);
  await restored.initialize();
  expect(restored.state.world.battle!.stats.toJson(),snapshot);
  expect(restored.worldStats.toJson(),boosted);
  final battleId=restored.state.world.battle!.id;
  await restored.worldCommand(WorldCommand.guard,battleId,1,expectedGeneration:restored.restoreGeneration);
  expect(restored.state.world.battle!.stats.toJson(),snapshot);
  await restored.worldCommand(WorldCommand.retreat,battleId,2,expectedGeneration:restored.restoreGeneration);
  await restored.unequipWorldSkill(a.id,expectedGeneration:restored.restoreGeneration,expectedRevision:2);
  expect(restored.worldStats.toJson(),original);
  await restored.importPortableBackup(initial);
  expect(restored.state.skills.learned,isEmpty);
  expect(restored.worldStats.toJson(),original);
 });
}
