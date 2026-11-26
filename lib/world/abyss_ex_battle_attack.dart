import 'dart:math';

/// Only these ordinary attacks are executable; no protagonist time powers.
enum ExAttackAttribute { physical, magic }

/// Immutable battle definition and usage history. Costs are fixed at battle start,
/// except the existing dynamic energy discount buff.
class ExBattleAttack {
 ExBattleAttack({required this.slot,required this.instanceId,required this.skillId,required this.level,required this.attribute,required this.powerBps,required this.physicalCost,required this.magicCost,required this.hpCostBps,required this.lifeDays,required this.cooldown,required this.initialCooldown,required this.maxUses,required this.energyDiscount,required this.maxHpBps,this.uses=0,this.lastCast=0}){
  if(slot<0||slot>=3||!instanceId.startsWith('eq_')||!skillId.startsWith('equipment_ex_skill:')||skillId.length<=19||level<1||level>10||powerBps<=0||powerBps>1000000||
     [physicalCost,magicCost,lifeDays].any((n)=>n<0||n>1000000)||hpCostBps<0||hpCostBps>=10000||cooldown<0||cooldown>1000||initialCooldown<0||initialCooldown>1000||
     (maxUses!=null&&(maxUses!<=0||maxUses!>1000))||(maxHpBps!=null&&(maxHpBps!<=0||maxHpBps!>10000))||uses<0||lastCast<0||(uses==0)!=(lastCast==0)||(maxUses!=null&&uses>maxUses!)){
   throw const FormatException('Invalid EX battle attack');
  }
 }
 final int slot,level,powerBps,physicalCost,magicCost,hpCostBps,lifeDays,cooldown,initialCooldown,uses,lastCast;
 final int? maxUses,maxHpBps;
 final String instanceId,skillId;
 final ExAttackAttribute attribute;
 final bool energyDiscount;
 int remaining(int turn)=>max(0,lastCast==0?initialCooldown-(turn-1):cooldown-(turn-lastCast-1));
 Map<String,dynamic> definition()=>{'slot':slot,'instanceId':instanceId,'skillId':skillId,'level':level,'attribute':attribute.name,'powerBps':powerBps,'physicalCost':physicalCost,'magicCost':magicCost,'hpCostBps':hpCostBps,'lifeDays':lifeDays,'cooldown':cooldown,'initialCooldown':initialCooldown,'maxUses':maxUses,'energyDiscount':energyDiscount,'maxHpBps':maxHpBps};
 Map<String,dynamic> toJson()=>{...definition(),'uses':uses,'lastCast':lastCast};
 ExBattleAttack cast(int turn)=>ExBattleAttack.fromJson({...definition(),'uses':uses+1,'lastCast':turn});
 factory ExBattleAttack.fromJson(Object? raw){
  if(raw is! Map<String,dynamic>||raw.length!=17||['slot','level','powerBps','physicalCost','magicCost','hpCostBps','lifeDays','cooldown','initialCooldown','uses','lastCast'].any((k)=>raw[k] is! int)||
     ['instanceId','skillId','attribute'].any((k)=>raw[k] is! String)||raw['energyDiscount'] is! bool||!raw.containsKey('maxUses')||!raw.containsKey('maxHpBps')||(raw['maxUses']!=null&&raw['maxUses'] is! int)||(raw['maxHpBps']!=null&&raw['maxHpBps'] is! int)){
   throw const FormatException('Invalid EX attack fields');
  }
  final attribute=ExAttackAttribute.values.where((a)=>a.name==raw['attribute']);
  if(attribute.isEmpty)throw const FormatException('Unknown EX attack attribute');
  return ExBattleAttack(slot:raw['slot'] as int,instanceId:raw['instanceId'] as String,skillId:raw['skillId'] as String,level:raw['level'] as int,attribute:attribute.single,powerBps:raw['powerBps'] as int,physicalCost:raw['physicalCost'] as int,magicCost:raw['magicCost'] as int,hpCostBps:raw['hpCostBps'] as int,lifeDays:raw['lifeDays'] as int,cooldown:raw['cooldown'] as int,initialCooldown:raw['initialCooldown'] as int,maxUses:raw['maxUses'] as int?,energyDiscount:raw['energyDiscount'] as bool,maxHpBps:raw['maxHpBps'] as int?,uses:raw['uses'] as int,lastCast:raw['lastCast'] as int);
 }
 static List<ExBattleAttack> validate(Iterable<ExBattleAttack> attacks,int turn){
  final list=List<ExBattleAttack>.of(attacks);
  if(list.length>3||list.map((a)=>a.slot).toSet().length!=list.length||list.map((a)=>a.skillId).toSet().length!=list.length||list.any((a)=>a.lastCast>=turn||(a.uses>0&&BigInt.from(a.lastCast)<BigInt.from(a.initialCooldown+1)+BigInt.from(a.uses-1)*BigInt.from(a.cooldown+1)))){
   throw const FormatException('Invalid EX attack history');
  }
  final total=list.fold(BigInt.zero,(n,a)=>n+BigInt.from(a.uses));
  if(total>BigInt.from(turn-1))throw const FormatException('Invalid EX usage count');
  return list;
 }
}
