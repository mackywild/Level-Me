import 'package:flutter/material.dart';
class AppTheme {
 const AppTheme._();
 static ThemeData dark(){
  final scheme=ColorScheme.fromSeed(seedColor:const Color(0xFF79F7A5),brightness:Brightness.dark);
  return ThemeData(useMaterial3:true,colorScheme:scheme,scaffoldBackgroundColor:const Color(0xFF090D10),
  cardTheme:const CardThemeData(elevation:0,margin:EdgeInsets.zero,color:Color(0xFF11181D)),
  inputDecorationTheme:InputDecorationTheme(filled:true,fillColor:const Color(0xFF11181D),border:OutlineInputBorder(borderRadius:BorderRadius.circular(12))));
 }
}
