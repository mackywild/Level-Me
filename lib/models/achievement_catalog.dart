import 'stat_type.dart';
class AchievementRule {
 const AchievementRule(this.id,this.title,this.description,this.icon,this.stat,this.reward,this.target,this.metric);
 final String id,title,description,icon,metric;
 final StatType stat;
 final int reward,target;
}
const achievementCatalog=<AchievementRule>[
 AchievementRule('first-step','THE FIRST STEP','クエストを1回完了','👣',StatType.discipline,10,1,'quests'),
 AchievementRule('quest-hunter','QUEST HUNTER','クエストを10回完了','⚔️',StatType.discipline,40,10,'quests'),
 AchievementRule('quest-veteran','QUEST VETERAN','クエストを50回完了','🛡️',StatType.discipline,100,50,'quests'),
 AchievementRule('first-blood','FIRST BLOOD','ボスを1体討伐','🐉',StatType.fitness,40,1,'bosses'),
 AchievementRule('monster-slayer','MONSTER SLAYER','ボスを5体討伐','💀',StatType.fitness,100,5,'bosses'),
 AchievementRule('consistency','SEVEN DAYS','7日連続で行動','🔥',StatType.discipline,70,7,'streak'),
 AchievementRule('level-ten','AWAKENED','レベル10到達','✨',StatType.creativity,100,10,'level'),
 AchievementRule('int-scholar','SCHOLAR','INT 500 EXP','📚',StatType.intelligence,60,500,'intelligence'),
 AchievementRule('fit-warrior','WARRIOR','FIT 500 EXP','💪',StatType.fitness,60,500,'fitness'),
 AchievementRule('finance-master','SAVER','FIN 500 EXP','💎',StatType.finance,60,500,'finance'),
 AchievementRule('social-bond','CONNECTOR','SOC 500 EXP','🤝',StatType.social,60,500,'social'),
 AchievementRule('creative-spark','CREATOR','CRE 500 EXP','🎨',StatType.creativity,60,500,'creativity'),
];
