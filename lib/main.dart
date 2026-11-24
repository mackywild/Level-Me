import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'controllers/app_controller.dart';
import 'screens/achievements_screen.dart';
import 'screens/boss_screen.dart';
import 'screens/home_screen.dart';
import 'screens/quests_screen.dart';
import 'services/local_store.dart';
import 'services/portable_backup.dart';
import 'theme/app_theme.dart';
void main(){
 WidgetsFlutterBinding.ensureInitialized();
 final controller=AppController(LocalStore(),portableBackup:PortableBackup());
 runApp(LevelMeApp(controller:controller));
}
class LevelMeApp extends StatelessWidget{
 const LevelMeApp({super.key,required this.controller});
 final AppController controller;
 @override Widget build(BuildContext context)=>MaterialApp(title:'LEVEL ME',debugShowCheckedModeBanner:false,theme:AppTheme.dark(),home:StartupGate(controller:controller));
}
class StartupGate extends StatefulWidget {
 const StartupGate({super.key,required this.controller});
 final AppController controller;
 @override State<StartupGate> createState()=>_StartupGateState();
}
class _StartupGateState extends State<StartupGate> {
 late Future<void> _loading;
 bool _backupBusy=false;
 @override void initState(){super.initState();_start();}
 void _start(){
  _loading=widget.controller.initialize();
 }
 Future<void> _restore() async {
  final confirmed=await showDialog<bool>(
   context:context,
   builder:(dialogContext)=>AlertDialog(
    title:const Text('直前のバックアップに戻しますか？'),
    content:const Text('最後の保存以降の変更は失われる場合があります。現在の保存ファイルは別名で保全します。'),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('取消')),
     FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('復元')),
    ],
   ),
  );
  if(!mounted||confirmed!=true)return;
  setState(() { _loading=widget.controller.restoreBackup(); });
 }
 Future<void> _backupAction(String action) async {
  if(_backupBusy)return;
  setState(()=>_backupBusy=true);
  try {
   if(action=='export'){
    final raw=await widget.controller.exportPortableBackup();
    final stamp=DateTime.now().toIso8601String().replaceAll(':','-');
    final saved=await FilePicker.platform.saveFile(
     fileName:'level-me-$stamp.json',
     type:FileType.custom,allowedExtensions:['json'],
     bytes:Uint8List.fromList(utf8.encode(raw)),
    );
    if(mounted&&saved!=null)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('バックアップを保存しました。')));
   }else{
    final result=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']);
    if(result==null||!mounted)return;
    final path=result.files.single.path;
    if(path==null)throw StateError('ファイルを読み込めません');
    final file=File(path);
    if(await file.length()>PortableBackup.maxBytes)throw const FormatException('バックアップが20MBを超えています');
    final raw=await file.readAsString();
    final data=PortableBackup.validate(raw);
    if(!mounted)return;
    final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
     title:const Text('バックアップを復元しますか？'),
     content:Text('作成日時: ${data['createdAt']??'不明'}\n現在のデータを置き換えます。復元前のファイルは端末内に退避します。'),
     actions:[
      TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('取消')),
      FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('復元')),
     ],
    ));
    if(!mounted||confirmed!=true)return;
    setState(() { _loading=widget.controller.importPortableBackup(raw); });
   }
  }catch(error){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('バックアップ操作失敗: $error')));
  }finally{
   if(mounted)setState(()=>_backupBusy=false);
  }
 }
 @override Widget build(BuildContext context)=>FutureBuilder<void>(
  future:_loading,
  builder:(context,snapshot){
   if(snapshot.connectionState==ConnectionState.done && !snapshot.hasError){
    return LevelMeShell(controller:widget.controller,onBackupAction:_backupAction,backupBusy:_backupBusy);
   }
   if(snapshot.connectionState==ConnectionState.done && snapshot.hasError){
    return Scaffold(body:SafeArea(child:Center(child:Padding(
     padding:const EdgeInsets.all(24),
     child:Column(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.error_outline,size:54,color:Colors.orangeAccent),
      const SizedBox(height:16),
      const Text('STARTUP FAILED',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
      const SizedBox(height:12),
      const Text('保存データは削除していません。起動処理に失敗しました。'),
      const SizedBox(height:12),
      SelectableText('${snapshot.error}',textAlign:TextAlign.center),
      const SizedBox(height:20),
      FilledButton(onPressed:_backupBusy?null:()=>setState(_start),child:const Text('RETRY')),
      OutlinedButton(onPressed:_backupBusy?null:()=>_backupAction('import'),child:const Text('外部バックアップから復元')),
      FutureBuilder<bool>(future:widget.controller.hasBackup(),builder:(context,backup){
       if(backup.data!=true)return const SizedBox.shrink();
       return OutlinedButton(onPressed:_backupBusy?null:_restore,child:const Text('直前のバックアップを復元'));
      }),
     ])))));
   }
   return const Scaffold(body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
    CircularProgressIndicator(),SizedBox(height:24),
    Text('LEVEL ME',style:TextStyle(fontSize:30,fontWeight:FontWeight.bold,letterSpacing:3)),
    SizedBox(height:12),Text('LOADING PLAYER DATA...'),
   ])));
  });
}
class LevelMeShell extends StatefulWidget{
 const LevelMeShell({super.key,required this.controller,required this.onBackupAction,required this.backupBusy});
 final AppController controller;
 final Future<void> Function(String) onBackupAction;
 final bool backupBusy;
 @override State<LevelMeShell> createState()=>_LevelMeShellState();
}
class _LevelMeShellState extends State<LevelMeShell> with WidgetsBindingObserver {
 Timer? _dayTimer;
 @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_dayTimer=Timer.periodic(const Duration(seconds:30),(_)=>_refresh());}
 Future<void> _refresh() async {try {await widget.controller.refreshDay();} catch(error){debugPrint('Day refresh failed: $error');}}
 @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed){_refresh();}}
 @override void dispose(){_dayTimer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
 int index=0;
 @override Widget build(BuildContext context)=>ListenableBuilder(listenable:widget.controller,builder:(context,_){
  final screens=[
   HomeScreen(controller:widget.controller),
   QuestsScreen(controller:widget.controller),
   BossScreen(controller:widget.controller),
   AchievementsScreen(controller:widget.controller)
  ];
  return Scaffold(appBar:AppBar(title:const Text('LEVEL ME',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:2)),backgroundColor:Colors.transparent,actions:[PopupMenuButton<String>(tooltip:'データ管理',enabled:!widget.backupBusy,onSelected:widget.onBackupAction,itemBuilder:(_)=>const [PopupMenuItem(value:'export',child:Text('バックアップを保存')),PopupMenuItem(value:'import',child:Text('バックアップを復元'))])]),
   body:screens[index],
   bottomNavigationBar:NavigationBar(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),destinations:const [
    NavigationDestination(icon:Icon(Icons.person),label:'STATUS'),
    NavigationDestination(icon:Icon(Icons.task_alt),label:'QUESTS'),
    NavigationDestination(icon:Icon(Icons.shield),label:'BATTLE'),
    NavigationDestination(icon:Icon(Icons.emoji_events),label:'TROPHIES')
   ]));
 });
}
