import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_state.dart';

/// Uses the legacy Android SharedPreferences API to avoid the
/// SharedPreferencesAsync Pigeon/Android binary linkage crash.
/// Keep the same key and do not clear user data.
class LocalStore {
 LocalStore();
 static const _stateKey='level_me_state_v1';

 Future<AppStateData> load() async {
  final prefs=await SharedPreferences.getInstance();
  final raw=prefs.getString(_stateKey);
  if(raw==null||raw.isEmpty)return AppStateData.initial();
  try{return AppStateData.fromJson(jsonDecode(raw) as Map<String,dynamic>);}
  catch(_){return AppStateData.initial();}
 }
 Future<void> save(AppStateData state) async {
  final prefs=await SharedPreferences.getInstance();
  final saved=await prefs.setString(_stateKey,jsonEncode(state.toJson()));
  if(!saved)throw StateError('Failed to persist player data');
 }
}
