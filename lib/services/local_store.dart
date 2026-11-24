import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/app_state.dart';

/// Durable JSON save file, independent of the Android shared_preferences plugin.
/// Never delete or reset the old preferences storage.
class LocalStore {
 LocalStore();
 Future<void> _pending = Future<void>.value();
 static const _fileName = 'level_me_state_v1.json';

 Future<File> _file() async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/$_fileName');
 }

 Future<AppStateData> load() async {
  final file = await _file();
  if (!await file.exists()) return AppStateData.initial();
  final raw = await file.readAsString();
  if (raw.isEmpty) return AppStateData.initial();
  // Do not silently overwrite a corrupt save with fresh state.
  return AppStateData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
 }

 Future<void> save(AppStateData state) {
  final snapshot = jsonEncode(state.toJson());
  final operation = _pending.then((_) => _write(snapshot));
  _pending = operation.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
  return operation;
 }
 Future<void> _write(String snapshot) async {
  final file = await _file();
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(snapshot, flush: true);
  // Same-directory rename replaces the file atomically on Android/Linux.
  await temporary.rename(file.path);
 }
}
