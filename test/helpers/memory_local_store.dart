import 'dart:convert';
import 'package:level_me/models/app_state.dart';
import 'package:level_me/services/local_store.dart';

/// Widgetテストのfake async内で実ファイルI/Oを待たない。
/// 実ファイルの永続化検証は通常のtestでLocalStoreを使用する。
class MemoryLocalStore extends LocalStore {
 String? _data;
 @override Future<AppStateData> load() async=>_data==null?AppStateData.initial():AppStateData.fromJson(jsonDecode(_data!) as Map<String,dynamic>);
 @override Future<void> save(AppStateData state) async{
  _data=jsonEncode(state.toJson());
 }
}
