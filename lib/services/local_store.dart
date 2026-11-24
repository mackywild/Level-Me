import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/app_state.dart';

/// Atomic primary save plus one validated previous generation.
class LocalStore {
 LocalStore({Directory? directory}) : _directory = directory;
 final Directory? _directory;
 Future<void> _pending = Future<void>.value();
 static const _fileName = 'level_me_state_v1.json';

 Future<File> _file() async {
  final directory = _directory ?? await getApplicationSupportDirectory();
  return File('${directory.path}/$_fileName');
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

 Future<AppStateData> load() async {
  await _pending;
  final file = await _file();
  if (!await file.exists()) {
   if (await File('${file.path}.bak').exists() ||
       await File('${file.path}.tmp').exists()) {
    throw StateError('Primary save missing; recovery files exist');
   }
   return AppStateData.initial();
  }
  return _decode(await file.readAsString());
 }

 Future<void> _enqueue(Future<void> Function() action) {
  final operation = _pending.then((_) => action());
  _pending = operation.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
  return operation;
 }

 Future<void> save(AppStateData state) {
  final snapshot = jsonEncode(state.toJson());
  return _enqueue(() => _write(snapshot));
 }

 Future<void> _atomicWrite(File destination, String raw) async {
  final temporary = File('${destination.path}.tmp');
  await temporary.writeAsString(raw, flush: true);
  await temporary.rename(destination.path);
 }

 Future<void> _write(String snapshot) async {
  _decode(snapshot);
  final file = await _file();
  final backup = File('${file.path}.bak');
  if (await file.exists()) {
   final previous = await file.readAsString();
   _decode(previous); // Never replace a damaged primary or valid backup silently.
   if (previous == snapshot) return;
   await _atomicWrite(backup, previous);
  } else if (await backup.exists() || await File('${file.path}.tmp').exists()) {
   throw StateError('Primary save missing; recovery files exist');
  }
  await _atomicWrite(file, snapshot);
 }

 Future<bool> hasBackup() async {
  await _pending;
  final file = await _file();
  final backup = File('${file.path}.bak');
  if (!await backup.exists()) return false;
  try {
   _decode(await backup.readAsString());
   return true;
  } catch (_) {
   return false;
  }
 }

 /// Explicit rollback only. Preserve the original bytes for later inspection.
 Future<void> restoreBackup() => _enqueue(() async {
  final file = await _file();
  final backup = File('${file.path}.bak');
  final raw = await backup.readAsString();
  _decode(raw);
  if (await file.exists()) {
   await file.copy('${file.path}.recovery-${DateTime.now().microsecondsSinceEpoch}');
  }
  await _atomicWrite(file, raw);
 });
}
