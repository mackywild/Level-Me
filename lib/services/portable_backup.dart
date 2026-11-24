import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/app_state.dart';
import 'fe_progress_store.dart';
import 'local_store.dart';

/// A portable, versioned snapshot of all current user data.
/// Restore uses a durable journal so an interrupted multi-file replacement
/// is completed before any player or FE data is loaded on the next startup.
class PortableBackup {
 PortableBackup({Directory? directory}):_directory=directory;
 final Directory? _directory;
 static const playerName=LocalStore.fileName;
 static const legacyPlayerName=LocalStore.legacyFileName;
 static const progressName='fe_progress_v1.json';
 static const flagsName='fe_review_flags_v1.json';
 static const names=[playerName,progressName,flagsName];
 static const journalName='level_me_restore_pending.json';
 static const maxBytes=20*1024*1024;
 Future<Directory> _dir() async=>_directory??await getApplicationSupportDirectory();
 File _file(Directory dir,String name)=>File('${dir.path}/$name');
 Future<void> _atomic(File file,String raw) async {
  final temp=File('${file.path}.tmp');
  await temp.writeAsString(raw,flush:true);
  await temp.rename(file.path);
 }
 static Map<String,dynamic> validate(String raw) {
  if(utf8.encode(raw).length>maxBytes)throw const FormatException('Backup too large');
  final data=jsonDecode(raw);
  if(data is! Map<String,dynamic>||data['format']!='level-me-backup'||(data['version']!=1&&data['version']!=2)) {
   throw const FormatException('Unsupported backup format');
  }
  final files=data['files'];
  final sourcePlayer=data['version']==1?legacyPlayerName:playerName;
  if(files is! Map<String,dynamic>||files.length!=names.length||[sourcePlayer,progressName,flagsName].any((n)=>!files.containsKey(n))) {
   throw const FormatException('Missing backup data');
  }
  final p=files[sourcePlayer];
  if(p is! Map<String,dynamic>||p['totalExp'] is! int||p['stats'] is! Map||p['quests'] is! List) {
   throw const FormatException('Invalid player data');
  }
  AppStateData.fromJson(p);
  FeProgressStore.decodeProgress(jsonEncode(files[progressName]));
  FeProgressStore.decodeFlags(jsonEncode(files[flagsName]));
  return {...data,'version':2,'files':{playerName:AppStateData.fromJson(p).toJson(),progressName:files[progressName],flagsName:files[flagsName]}};
 }
 Future<String> _snapshot(Directory dir) async {
  final files=<String,dynamic>{};
  for(final name in names) {
   final file=_file(dir,name);
   if(await file.exists()){
    files[name]=jsonDecode(await file.readAsString());
   }else{
    if(name==playerName||await File('${file.path}.bak').exists()||await File('${file.path}.tmp').exists()) {
     throw StateError('Missing save: $name');
    }
    files[name]=name==progressName?<String,dynamic>{}:<String>[];
   }
  }
  final raw=jsonEncode({'format':'level-me-backup','version':2,'createdAt':DateTime.now().toUtc().toIso8601String(),'files':files});
  validate(raw);
  return raw;
 }
 Future<String> export() => FeProgressStore.synchronized(() async {
  final dir=await _dir();
  if(await _file(dir,journalName).exists())throw StateError('Restore pending');
  return _snapshot(dir);
 });
 Future<void> restore(String raw) => FeProgressStore.synchronized(() async {
  validate(raw);
  final dir=await _dir();
  final journal=_file(dir,journalName);
  if(await journal.exists())throw StateError('Restore already pending');
  // Preserve all original bytes, even if corrupted, before committing import.
  final recovery=await dir.createTemp('level_me_before_import_');
  for(final name in [...names,legacyPlayerName]){
   for(final suffix in ['', '.bak', '.tmp', '.bak.tmp', LocalStore.initialSuffix, LocalStore.markerSuffix, '${LocalStore.markerSuffix}.tmp']){
    final file=_file(dir,'$name$suffix');
    if(await file.exists())await file.copy('${recovery.path}/$name$suffix');
   }
  }
  await _atomic(journal,raw);
  await _finish(dir,journal);
 });
 Future<void> resumePendingRestore()=>FeProgressStore.synchronized(() async {
  final dir=await _dir();
  final journal=_file(dir,journalName);
  if(await journal.exists())await _finish(dir,journal);
 });
 Future<void> _finish(Directory dir,File journal) async {
  final data=validate(await journal.readAsString());
  final files=data['files'] as Map<String,dynamic>;
  for(final name in names) {
   final file=_file(dir,name);
   final raw=jsonEncode(files[name]);
   await _atomic(file,raw);
   // A previous backup from another save must not silently undo this import.
   await _atomic(File('${file.path}.bak'),raw);
  }
  final staged=_file(dir,'$playerName${LocalStore.initialSuffix}');
  if(await staged.exists())await staged.delete();
  await journal.delete();
 }
}
