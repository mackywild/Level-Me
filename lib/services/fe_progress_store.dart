import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class FeProgressStore {
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
}
