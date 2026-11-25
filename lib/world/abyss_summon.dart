import 'abyss_inventory.dart';

enum SummonPool { equipment, relic, supplies }

/// Draft LM-02 policy. Not connected to production ticket consumption.
class SummonPolicy {
 const SummonPolicy();
 static const costs={SummonPool.equipment:1,SummonPool.relic:5,SummonPool.supplies:1};
 static const weights=[4500,3000,1800,500,150,40,9,1];
 static const pityLimits={EquipmentRarity.ssr:50,EquipmentRarity.ur:150,EquipmentRarity.lr:300,EquipmentRarity.gr:1000,EquipmentRarity.ex:3000};

 List<int> effectiveWeights(EquipmentRarity highestUnlocked){
  final result=List<int>.of(weights);
  for(var i=highestUnlocked.index+1;i<result.length;i++){
   result[highestUnlocked.index]+=result[i];
   result[i]=0;
  }
  return List.unmodifiable(result);
 }

 /// A draw uses an explicit integer roll in [0,10000).
 /// Highest due unlocked pity wins; ten-pull guarantee supplies a minimum SR
 /// only when SR is unlocked. Both priority rules are provisional.
 SummonOutcome draw({required EquipmentRarity highestUnlocked,required int roll,required Map<EquipmentRarity,int> misses,bool guaranteeSr=false}){
  if(roll<0||roll>=10000)throw RangeError.range(roll,0,9999,'roll');
  for(final entry in misses.entries){
   final limit=pityLimits[entry.key];
   if(limit==null||entry.value<0||entry.value>=limit)throw ArgumentError('Invalid pity counter');
  }
  final effective=effectiveWeights(highestUnlocked);
  var remaining=roll;
  var rarity=EquipmentRarity.n;
  for(var i=0;i<effective.length;i++){
   if(remaining<effective[i]){rarity=EquipmentRarity.values[i];break;}
   remaining-=effective[i];
  }
  for(final entry in pityLimits.entries){
   if(entry.key.index<=highestUnlocked.index&&(misses[entry.key]??0)+1>=entry.value&&entry.key.index>rarity.index){
    rarity=entry.key;
   }
  }
  if(guaranteeSr&&highestUnlocked.index>=EquipmentRarity.sr.index&&rarity.index<EquipmentRarity.sr.index){
   rarity=EquipmentRarity.sr;
  }
  final next=<EquipmentRarity,int>{};
  for(final entry in pityLimits.entries){
   // Locked tiers retain their previous counters, but never accrue misses.
   final previous=misses[entry.key]??0;
   next[entry.key]=entry.key.index>highestUnlocked.index?previous:rarity.index>=entry.key.index?0:previous+1;
  }
  return SummonOutcome(rarity,next);
 }
}

class SummonOutcome {
 SummonOutcome(this.rarity,Map<EquipmentRarity,int> misses):misses=Map.unmodifiable(misses);
 final EquipmentRarity rarity;
 final Map<EquipmentRarity,int> misses;
}
