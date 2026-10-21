import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class FeProgressStore {
 Future<File> _flagsFile() async {
  final dir=await getApplicationSupportDirectory();
  return File('${dir.path}/fe_review_flags_v1.json');
 }

 Future<File> _file() async {
  final dir=await getApplicationSupportDirectory();
  return File('${dir.path}/fe_progress_v1.json');
 }
 Future<Map<String,List<bool>>> load() async {
  final file=await _file();
  if(!await file.exists())return {};
  final data=jsonDecode(await file.readAsString()) as Map<String,dynamic>;
  return data.map((key,value)=>MapEntry(key,(value as List).cast<bool>()));
 }
 Future<void> record(String id,bool correct) async {
  final data=await load();
  data.putIfAbsent(id,()=>[]).add(correct);
  final file=await _file();
  final temp=File('${file.path}.tmp');
  await temp.writeAsString(jsonEncode(data),flush:true);
  await temp.rename(file.path);
 }

 Future<Set<String>> loadFlags() async {
  final file=await _flagsFile();
  if(!await file.exists())return {};
  final data=jsonDecode(await file.readAsString()) as List<dynamic>;
  return data.cast<String>().toSet();
 }

 Future<void> setFlag(String id,bool flagged) async {
  final flags=await loadFlags();
  if(flagged){flags.add(id);}else{flags.remove(id);}
  final file=await _flagsFile();
  final temp=File('${file.path}.tmp');
  await temp.writeAsString(jsonEncode(flags.toList()..sort()),flush:true);
  await temp.rename(file.path);
 }
}
