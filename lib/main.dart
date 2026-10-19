import 'package:flutter/material.dart';
import 'controllers/app_controller.dart';
import 'screens/achievements_screen.dart';
import 'screens/boss_screen.dart';
import 'screens/home_screen.dart';
import 'screens/quests_screen.dart';
import 'services/local_store.dart';
import 'theme/app_theme.dart';
Future<void> main() async{
 WidgetsFlutterBinding.ensureInitialized();
 final controller=AppController(LocalStore());
 await controller.initialize();
 runApp(LevelMeApp(controller:controller));
}
class LevelMeApp extends StatelessWidget{
 const LevelMeApp({super.key,required this.controller});
 final AppController controller;
 @override Widget build(BuildContext context)=>MaterialApp(title:'LEVEL ME',debugShowCheckedModeBanner:false,theme:AppTheme.dark(),home:LevelMeShell(controller:controller));
}
class LevelMeShell extends StatefulWidget{
 const LevelMeShell({super.key,required this.controller});
 final AppController controller;
 @override State<LevelMeShell> createState()=>_LevelMeShellState();
}
class _LevelMeShellState extends State<LevelMeShell>{
 int index=0;
 @override Widget build(BuildContext context)=>ListenableBuilder(listenable:widget.controller,builder:(context,_){
  final screens=[
   HomeScreen(controller:widget.controller),
   QuestsScreen(controller:widget.controller),
   BossScreen(controller:widget.controller),
   AchievementsScreen(controller:widget.controller)
  ];
  return Scaffold(appBar:AppBar(title:const Text('LEVEL ME',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:2)),backgroundColor:Colors.transparent),
   body:screens[index],
   bottomNavigationBar:NavigationBar(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),destinations:const [
    NavigationDestination(icon:Icon(Icons.person),label:'STATUS'),
    NavigationDestination(icon:Icon(Icons.task_alt),label:'QUESTS'),
    NavigationDestination(icon:Icon(Icons.shield),label:'BATTLE'),
    NavigationDestination(icon:Icon(Icons.emoji_events),label:'TROPHIES')
   ]));
 });
}
