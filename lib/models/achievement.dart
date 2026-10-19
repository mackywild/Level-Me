import 'stat_type.dart';
class Achievement {
 const Achievement({required this.id, required this.title, required this.description, required this.stat, required this.exp, required this.unlockedAt});
 final String id, title, description;
 final StatType stat;
 final int exp;
 final DateTime unlockedAt;
 Map<String,dynamic> toJson() => {'id':id,'title':title,'description':description,'stat':stat.name,'exp':exp,'unlockedAt':unlockedAt.toIso8601String()};
 factory Achievement.fromJson(Map<String,dynamic> j) => Achievement(id:j['id'] as String,title:j['title'] as String,description:j['description'] as String,stat:StatType.values.byName(j['stat'] as String),exp:j['exp'] as int,unlockedAt:DateTime.parse(j['unlockedAt'] as String));
}
