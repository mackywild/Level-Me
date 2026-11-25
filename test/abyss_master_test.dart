import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:level_me/world/abyss_inventory.dart';
import 'package:level_me/world/abyss_master.dart';
import 'package:level_me/world/abyss_summon.dart';

void main(){
 Map<String,dynamic> source()=>jsonDecode(File(AbyssMaster.assetPath).readAsStringSync()) as Map<String,dynamic>;
 test('同梱マスターは承認前のため排出無効',(){
  final json=source();
  expect(json['enabled'],false);
  expect((json['equipment'] as List).length,24);
  expect((json['supplies'] as List).length,8);
  final master=AbyssMaster.fromJson(jsonEncode(json));
  expect(master.enabled,false);
  expect(master.equipment.find('equipment:cloth_cap'),isNull);
  expect(master.supply('item:iron'),isNull);
  for(final pool in SummonPool.values){
   for(final rarity in EquipmentRarity.values){
    expect(master.summon.entries(pool,rarity),isEmpty);
   }
  }
 });
 test('承認後のマスターは序章の全プールに必要な希少度を備える',(){
  final master=AbyssMaster.fromJson(jsonEncode(source()..['enabled']=true));
  expect(master.enabled,true);
  expect(master.equipment.find('equipment:cloth_cap')!.defense,1);
  expect(master.supply('item:iron')!.name,'鉄');
  for(final pool in SummonPool.values){
   for(final rarity in EquipmentRarity.values.take(4)){
    expect(master.summon.entries(pool,rarity),isNotEmpty);
   }
  }
 });
 test('不正な排出参照・部位・素材種別・重複・性能を拒否する',(){
  final invalid=source();
  (invalid['summon'] as List).add({'pool':'supplies','masterId':'item:unknown'});
  expect(()=>AbyssMaster.fromJson(jsonEncode(invalid)),throwsFormatException);
  final wrong=source();
  (wrong['summon'] as List).first['pool']='relic';
  expect(()=>AbyssMaster.fromJson(jsonEncode(wrong)),throwsFormatException);
  final special=source();
  (special['supplies'] as List).first['category']='power';
  expect(()=>AbyssMaster.fromJson(jsonEncode(special)),throwsFormatException);
  final duplicate=source();
  (duplicate['summon'] as List).add((duplicate['summon'] as List).first);
  expect(()=>AbyssMaster.fromJson(jsonEncode(duplicate)),throwsFormatException);
  final negative=source();
  (negative['equipment'] as List).first['defense']=-1;
  expect(()=>AbyssMaster.fromJson(jsonEncode(negative)),throwsFormatException);
 });
 test('承認フラグを立てても不完全なプールは拒否される',(){
  final json=source()..['enabled']=true;
  (json['summon'] as List).removeWhere((e)=>e['pool']=='relic');
  expect(()=>AbyssMaster.fromJson(jsonEncode(json)),throwsFormatException);
 });
}
