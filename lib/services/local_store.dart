import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/app_state.dart';

/// Atomic primary save plus one validated previous generation.
/// Initial publication uses a separate temporary file and a durable marker.
class LocalStore {
 LocalStore({Directory? directory}) : _directory = directory;
 final Directory? _directory;
 Future<void> _pending = Future<void>.value();
 static const fileName = 'level_me_state_v2.json';
 static const legacyFileName = 'level_me_state_v1.json';
 static const initialSuffix = '.initial.tmp';
 static const markerSuffix = '.initialized';

 Future<File> _file() async {
  final directory = _directory ?? await getApplicationSupportDirectory();
  return File('${directory.path}/$fileName');
 }

 AppStateData _decode(String raw) {
  final data = jsonDecode(raw);
  if (data is! Map<String, dynamic> ||
      data['totalExp'] is! int ||
      data['stats'] is! Map ||
      data['quests'] is! List) {
   throw const FormatException('Invalid player save structure');
  }
  return AppStateData.fromJson(data);
 }

 File _initial(File primary)=>File('${primary.path}$initialSuffix');
 File _marker(File primary)=>File('${primary.path}$markerSuffix');
 File _legacy(File primary)=>File('${primary.parent.path}/$legacyFileName');

 Future<bool> _hasRegularRecovery(File primary) async =>
  await File('${primary.path}.bak').exists() ||
  await File('${primary.path}.tmp').exists() ||
  await File('${primary.path}.bak.tmp').exists();

 Future<void> _ensureMarker(File primary) async {
  final marker=_marker(primary);
  if(!await marker.exists())await _atomicWrite(marker,'v2');
 }

 Future<T> _enqueue<T>(Future<T> Function() action) {
  final operation = _pending.then((_) => action());
  _pending = operation.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
  return operation;
 }

 Future<AppStateData> load()=>_enqueue(() async {
  final primary=await _file();
  if(await primary.exists()){
   final state=_decode(await primary.readAsString());
   await _discardInitial(primary);
   await _ensureMarker(primary);
   return state;
  }
  // Regular recovery evidence always takes precedence over initial staging.
  if(await _hasRegularRecovery(primary)){
   throw StateError('Primary save missing; recovery files exist');
  }
  if(await _marker(primary).exists()){
   final staged=_initial(primary);
   if(!await staged.exists())throw StateError('Established v2 save missing; explicit recovery required');
   // Marker is written only after the complete first snapshot is flushed.
   final state=_decode(await staged.readAsString());
   await staged.rename(primary.path);
   return state;
  }
  // A partial initial temp without a marker has not been published.
  // Re-read the original source rather than trusting partial bytes.
  final legacy=_legacy(primary);
  if(await legacy.exists())return _decode(await legacy.readAsString());
  if(await File('${legacy.path}.bak').exists()||await File('${legacy.path}.tmp').exists()||await File('${legacy.path}.bak.tmp').exists()){
   throw StateError('Legacy primary missing; recovery files exist');
  }
  return AppStateData.initial();
 });

 Future<void> save(AppStateData state) {
  final snapshot=jsonEncode(state.toJson());
  return _enqueue(()=>_write(snapshot));
 }

 Future<void> _atomicWrite(File destination,String raw) async {
  final temporary=File('${destination.path}.tmp');
  await temporary.writeAsString(raw,flush:true);
  await temporary.rename(destination.path);
 }

 Future<void> _discardInitial(File primary) async {
  final staged=_initial(primary);
  if(await staged.exists())await staged.delete();
 }

 Future<void> _publishInitial(File primary,String raw) async {
  final staged=_initial(primary);
  await staged.writeAsString(raw,flush:true);
  await _ensureMarker(primary);
  await staged.rename(primary.path);
 }

 Future<void> _write(String snapshot) async {
  _decode(snapshot);
  final primary=await _file();
  final backup=File('${primary.path}.bak');
  if(await primary.exists()){
   final previous=await primary.readAsString();
   _decode(previous);
   await _discardInitial(primary);
   await _ensureMarker(primary);
   if(previous==snapshot)return;
   await _atomicWrite(backup,previous);
   await _atomicWrite(primary,snapshot);
   return;
  }
  if(await _hasRegularRecovery(primary)||await _marker(primary).exists()){
   throw StateError('Primary save missing; recovery required');
  }
  final legacy=_legacy(primary);
  if(await legacy.exists()){
   _decode(await legacy.readAsString());
  }else if(await File('${legacy.path}.bak').exists()||await File('${legacy.path}.tmp').exists()||await File('${legacy.path}.bak.tmp').exists()){
   throw StateError('Legacy primary missing; recovery files exist');
  }
  await _publishInitial(primary,snapshot);
 }

 Future<File> _recoverySource(File primary) async {
  final backup=File('${primary.path}.bak');
  if(await primary.exists()||await _hasRegularRecovery(primary)||await _marker(primary).exists())return backup;
  return File('${primary.parent.path}/$legacyFileName.bak');
 }

 Future<bool> hasBackup()=>_enqueue(() async {
  final backup=await _recoverySource(await _file());
  if(!await backup.exists())return false;
  try{
   _decode(await backup.readAsString());
   return true;
  }catch(_){return false;}
 });

 /// Explicit rollback only. Preserve the original bytes for inspection.
 Future<void> restoreBackup()=>_enqueue(() async {
  final primary=await _file();
  final backup=await _recoverySource(primary);
  final raw=await backup.readAsString();
  final state=_decode(raw);
  if(await primary.exists()){
   await primary.copy('${primary.path}.recovery-${DateTime.now().microsecondsSinceEpoch}');
  }
  if(backup.path==File('${_legacy(primary).path}.bak').path){
   await _publishInitial(primary,jsonEncode(state.toJson()));
  }else{
   await _ensureMarker(primary);
   await _atomicWrite(primary,raw);
   await _discardInitial(primary);
  }
 });
}
