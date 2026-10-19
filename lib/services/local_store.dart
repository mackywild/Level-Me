import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_state.dart';
class LocalStore {
 LocalStore():_prefs=SharedPreferencesAsync();
 static const _stateKey='level_me_state_v1';
 final SharedPreferencesAsync _prefs;
 Future<AppStateData> load() async {
  final raw=await _prefs.getString(_stateKey);
  if(raw==null||raw.isEmpty)return AppStateData.initial();
  try{return AppStateData.fromJson(jsonDecode(raw) as Map<String,dynamic>);}
  catch(_){return AppStateData.initial();}
 }
 Future<void> save(AppStateData state) async=>_prefs.setString(_stateKey,jsonEncode(state.toJson()));
}
