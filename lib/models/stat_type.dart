enum StatType { intelligence, fitness, discipline, finance, social, creativity }
extension StatTypeX on StatType {
 String get label => name.toUpperCase();
 String get shortLabel => label.substring(0, 3);
 String get icon => switch(this) {
 StatType.intelligence => '🧠', StatType.fitness => '💪',
 StatType.discipline => '🔥', StatType.finance => '💰',
 StatType.social => '🤝', StatType.creativity => '⚙️' };
}
