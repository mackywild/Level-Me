class LevelProgress {
 const LevelProgress({required this.level,required this.expIntoLevel,required this.expToNextLevel});
 final int level,expIntoLevel,expToNextLevel;
 double get ratio => expToNextLevel == 0 ? 1 : expIntoLevel/expToNextLevel;
}
class LevelCalculator {
 const LevelCalculator._();
 static int expRequiredForNextLevel(int level)=>100+25*(level-1);
 static LevelProgress fromTotalExp(int totalExp) {
  var level=1,remaining=totalExp<0?0:totalExp;
  while(remaining>=expRequiredForNextLevel(level)){remaining-=expRequiredForNextLevel(level);level++;}
  return LevelProgress(level:level,expIntoLevel:remaining,expToNextLevel:expRequiredForNextLevel(level));
 }
 static int statRankFromExp(int exp)=>1+(exp~/100);
}
