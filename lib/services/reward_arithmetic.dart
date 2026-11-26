/// 符号付き64bit整数資源の報酬演算（Dartネイティブ向け）。
class RewardArithmetic {
 const RewardArithmetic._();
 static const maximum=0x7fffffffffffffff;
 static int add(int balance,int reward){
  if(balance<0||reward<0||balance>maximum-reward)throw StateError('Reward overflow or negative value');
  return balance+reward;
 }
 static int cappedAdd(int balance,int reward,int cap){
  if(balance<0||reward<0||cap<0)throw StateError('Invalid capped reward');
  if(balance>=cap)return cap;
  return reward>=cap-balance?cap:balance+reward;
 }
 /// 正のEXPの従来の四捨五入と最小1。巨大値でも中間積を失わない。
 static int timedExp(int exp,int multiplier){
  if(exp<=0||multiplier<1||multiplier>120)throw StateError('Invalid timed reward');
  final rounded=(BigInt.from(exp)*BigInt.from(multiplier)+BigInt.from(12))~/BigInt.from(25);
  if(rounded>BigInt.from(maximum))throw StateError('Timed reward overflow');
  return rounded==BigInt.zero?1:rounded.toInt();
 }
}
