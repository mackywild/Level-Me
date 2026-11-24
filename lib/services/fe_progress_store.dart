import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class FeProgressStore {
 FeProgressStore({Directory? directory}):_directory=directory;
 final Directory? _directory;
 // Shared across screen instances in the main isolate.
 static Future<void> _pending=Future<void>.value();
 static Future<T> synchronized<T>(Future<T> Function() action) {
  final operation=_pending.then((_)=>action());
  _pending=operation.then<void>((_) {},onError:(Object e,StackTrace st){});
  return operation;
 }
 Future<File> _file(String name) async {
  final dir=_directory??await getApplicationSupportDirectory();
  return File('${dir.path}/$name');
 }
 static Map<String,List<bool>> decodeProgress(String raw) {
  final data=jsonDecode(raw);
  if(data is! Map<String,dynamic>)throw const FormatException('Invalid FE progress');
  return data.map((key,value){
   if(value is! List||value.any((e)=>e is! bool))throw const FormatException('Invalid FE answers');
   return MapEntry(key,List<bool>.from(value));
  });
 }
 static Set<String> decodeFlags(String raw) {
  final data=jsonDecode(raw);
  if(data is! List||data.any((e)=>e is! String))throw const FormatException('Invalid FE flags');
  return data.cast<String>().toSet();
 }
 Future<String> _read(File file,String empty,void Function(String) validate) async {
  if(!await file.exists()){
   if(await File('${file.path}.bak').exists()||await File('${file.path}.tmp').exists()) {
    throw StateError('FE save missing; recovery files exist');
   }
   return empty;
  }
  final raw=await file.readAsString();
  validate(raw);
  return raw;
 }
 Future<void> _atomic(File file,String raw) async {
  final temp=File('${file.path}.tmp');
  await temp.writeAsString(raw,flush:true);
  await temp.rename(file.path);
 }
 Future<void> _write(File file,String raw,String previous) async {
  if(raw==previous)return;
  if(await file.exists())await _atomic(File('${file.path}.bak'),previous);
  await _atomic(file,raw);
 }
 Future<Map<String,List<bool>>> load()=>synchronized(() async {
  final file=await _file('fe_progress_v1.json');
  return decodeProgress(await _read(file,'{}',decodeProgress));
 });
 Future<void> record(String id,bool correct)=>synchronized(() async {
  final file=await _file('fe_progress_v1.json');
  final raw=await _read(file,'{}',decodeProgress);
  final data=decodeProgress(raw);
  data.putIfAbsent(id,()=>[]).add(correct);
  await _write(file,jsonEncode(data),raw);
 });
 Future<Set<String>> loadFlags()=>synchronized(() async {
  final file=await _file('fe_review_flags_v1.json');
  return decodeFlags(await _read(file,'[]',decodeFlags));
 });
 Future<void> setFlag(String id,bool flagged)=>synchronized(() async {
  final file=await _file('fe_review_flags_v1.json');
  final raw=await _read(file,'[]',decodeFlags);
  final flags=decodeFlags(raw);
  if(flagged){flags.add(id);}else{flags.remove(id);}
  await _write(file,jsonEncode(flags.toList()..sort()),raw);
 });
}
