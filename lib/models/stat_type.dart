enum StatType { intelligence, fitness, discipline, finance, social, creativity }
extension StatTypeX on StatType {
 String get label => switch(this){StatType.intelligence=>'知力',StatType.fitness=>'体力',StatType.discipline=>'継続力',StatType.finance=>'資産管理',StatType.social=>'交流力',StatType.creativity=>'創造力'};
 String get shortLabel => label;
 String get icon => switch(this) {
 StatType.intelligence => '🧠', StatType.fitness => '💪',
 StatType.discipline => '🔥', StatType.finance => '💰',
 StatType.social => '🤝', StatType.creativity => '⚙️' };
}
