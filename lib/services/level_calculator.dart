class LevelProgress {
 const LevelProgress({required this.level,required this.expIntoLevel,required this.expToNextLevel});
 final int level,expIntoLevel,expToNextLevel;
 double get ratio => expToNextLevel == 0 ? 1 : expIntoLevel/expToNextLevel;
}
class LevelCalculator {
 const LevelCalculator._();
 static int expRequiredForNextLevel(int level){
  if(level<1||level-1>(0x7fffffffffffffff-100)~/25)throw RangeError.value(level,'level');
  return 100+25*(level-1);
 }
 /// n回レベルアップに必要な累積EXP。中間積はBigIntで評価する。
 static BigInt _cumulative(int n)=>BigInt.from(n)*(BigInt.from(175)+BigInt.from(25)*BigInt.from(n))~/BigInt.two;
 static LevelProgress fromTotalExp(int totalExp) {
  final exp=BigInt.from(totalExp<0?0:totalExp);
  var lo=0,hi=1;
  while(_cumulative(hi)<=exp){hi*=2;}
  while(hi-lo>1){
   final mid=lo+(hi-lo)~/2;
   if(_cumulative(mid)<=exp){lo=mid;}else{hi=mid;}
  }
  final level=lo+1;
  return LevelProgress(level:level,expIntoLevel:(exp-_cumulative(lo)).toInt(),expToNextLevel:expRequiredForNextLevel(level));
 }
 static int statRankFromExp(int exp){
  if(exp<0)throw RangeError.value(exp,'exp');
  return 1+exp~/100;
 }
}
