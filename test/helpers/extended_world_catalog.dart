import 'dart:convert';
import 'dart:io';
import 'package:level_me/world/world_catalog.dart';

/// 本番マスターを変更せず、未公開ステージの解放条件を試験する。
/// ST01〜03の実データを維持し、後続はST01を複製した試験専用遭遇。
void loadExtendedWorldCatalog(int throughStage){
 final root=jsonDecode(File(WorldCatalog.assetPath).readAsStringSync()) as Map<String,dynamic>;
 final encounters=(root['encounters'] as List).cast<Map<String,dynamic>>();
 final template=encounters.where((e)=>e['stage']==1).toList();
 final lastStage=encounters.map((e)=>e['stage'] as int).reduce((a,b)=>a>b?a:b);
 for(var stage=lastStage+1;stage<=throughStage;stage++){
  final prefix=WorldCatalog.mainId(stage).split('_').first;
  for(final entry in template){
   encounters.add({...entry,'stage':stage,'id':(entry['id'] as String).replaceFirst('p01',prefix),'title':'試験 STAGE $stage','lifeDays':0});
  }
 }
 WorldCatalog.loadJson(jsonEncode(root));
}
