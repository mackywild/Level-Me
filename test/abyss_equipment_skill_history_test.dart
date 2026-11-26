import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_inventory.dart';

void main(){
 const skill='equipment_skill:test';
 StoredEquipmentSkill grant(int stage,{int level=7})=>StoredEquipmentSkill(milestone:stage,skillId:skill,level:level);
 AbyssInventory reload(AbyssInventory inv)=>AbyssInventory.fromJson(jsonDecode(jsonEncode(inv.toJson())) as Map<String,dynamic>);
 test('旧装備の過去枠を生成せず今後の段階のみ確定保存する',(){
  var inv=AbyssInventory();
  final item=inv.addEquipment('test',EquipmentSlot.hands,EquipmentRarity.gr);
  inv.addStack('item:iron',20);
  for(var i=0;i<5;i++){inv.enhanceWithMaterial(item.id,i,'item:iron',1);}
  inv=reload(inv);
  expect(inv.equipmentSkillHistories,isEmpty);
  inv.beginEquipmentSkillHistory(item.id,5);
  inv.enhanceWithMaterial(item.id,5,'item:iron',1,skillGrant:grant(6));
  inv=reload(inv);
  final history=inv.equipmentSkillHistories[item.id]!;
  expect(history.startEnhancement,5);
  expect(history.grants.single.milestone,6);
  expect(history.grants.single.level,7);
  expect(history.grants.single.skillId,skill);
  expect(history.grants.single.ruleVersion,1);
  expect(()=>history.grants.clear(),throwsUnsupportedError);
  expect(()=>inv.equipmentSkillHistories.clear(),throwsUnsupportedError);
  expect(()=>inv.beginEquipmentSkillHistory(item.id,6),throwsStateError);
  inv.setFavorite(item.id,true);inv.setFavorite(item.id,false);
  inv.equip(item.id);inv.unequip(item.slot);
  for(var i=6;i<9;i++){inv.enhanceWithMaterial(item.id,i,'item:iron',1,skillGrant:i==8?grant(9,level:10):null);}
  final restored=reload(inv);
  expect(restored.equipmentSkillHistories[item.id]!.grants.map((g)=>g.level),[7,10]);
  expect(restored.equipmentSkillHistories[item.id]!.grants.map((g)=>g.skillId),[skill,skill]);
  restored.removeEquipment(item.id,9);
  expect(restored.equipmentSkillHistories,isEmpty);
 });
 test('付与欠落・重複段階・不正Lv・規則版は素材消費前に拒否',(){
  final inv=AbyssInventory();
  final item=inv.addEquipment('test',EquipmentSlot.hands,EquipmentRarity.gr);
  inv.addStack('item:iron',20);
  inv.beginEquipmentSkillHistory(item.id,0);
  void reject(StoredEquipmentSkill? value,int current){
   final before=jsonEncode(inv.toJson());
   expect(()=>inv.enhanceWithMaterial(item.id,current,'item:iron',1,skillGrant:value),throwsFormatException);
   expect(jsonEncode(inv.toJson()),before);
  }
  reject(grant(3),0);
  inv.enhanceWithMaterial(item.id,0,'item:iron',1);
  inv.enhanceWithMaterial(item.id,1,'item:iron',1);
  reject(null,2);reject(grant(3,level:11),2);reject(grant(6),2);
  reject(const StoredEquipmentSkill(milestone:3,skillId:skill,level:1,ruleVersion:2),2);
  inv.enhanceWithMaterial(item.id,2,'item:iron',1,skillGrant:grant(3));
  reject(grant(3),3);
 });
 test('不正保存履歴の欠落枠・個体・版・開始値を拒否する',(){
  final inv=AbyssInventory();
  final item=inv.addEquipment('test',EquipmentSlot.hands,EquipmentRarity.gr);
  inv.addStack('item:iron',3);inv.beginEquipmentSkillHistory(item.id,0);
  inv.enhanceWithMaterial(item.id,0,'item:iron',1);
  inv.enhanceWithMaterial(item.id,1,'item:iron',1);
  inv.enhanceWithMaterial(item.id,2,'item:iron',1,skillGrant:grant(3));
  Map<String,dynamic> raw()=>jsonDecode(jsonEncode(inv.toJson())) as Map<String,dynamic>;
  for(final field in ['version','owner','start','missing']){
   final data=raw();final root=data['equipmentSkills'] as Map;final items=root['items'] as Map;
   final history=items[item.id] as Map;
   switch(field){
    case 'version':root['version']=2;break;
    case 'owner':items['unknown']=items.remove(item.id);break;
    case 'start':history['startEnhancement']=4;break;
    case 'missing':(history['grants'] as List).clear();break;
   }
   expect(()=>AbyssInventory.fromJson(data),throwsFormatException);
  }
 });
 test('EXは個別定義接続まで初期化拒否、素材履歴保護は独立',(){
  final inv=AbyssInventory();
  final ex=inv.addEquipment('test',EquipmentSlot.hands,EquipmentRarity.ex);
  expect(()=>inv.beginEquipmentSkillHistory(ex.id,0),throwsUnsupportedError);
  final old=inv.addEquipment('old',EquipmentSlot.hands,EquipmentRarity.r);
  inv.enhance(old.id,0);inv.beginEquipmentSkillHistory(old.id,1);
  inv.addStack('item:iron',10);
  expect(()=>inv.enhanceWithMaterial(old.id,1,'item:iron',1),throwsStateError);
 });
}
