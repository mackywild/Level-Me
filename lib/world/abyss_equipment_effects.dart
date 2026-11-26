import 'abyss_inventory.dart';
import 'abyss_equipment_skill_policy.dart';
import 'abyss_equipment_skill_pool.dart';

/// 効果の識別子。数値曲線・上限は本番承認後に注入する。
enum EquipmentEffect { physicalPercent, magicPercent, defensePercent, damageReduction, extraAttackChance, energyDiscount, cooldownReduction, criticalChance, penetration, hpPercent, evasionChance, resistance, naturalRecovery, rewardPercent }

/// 戦闘版4と表示で共通の接続済み効果集合。
const battleConnectedEquipmentEffects={EquipmentEffect.physicalPercent,EquipmentEffect.magicPercent,EquipmentEffect.defensePercent,EquipmentEffect.criticalChance,EquipmentEffect.evasionChance,EquipmentEffect.damageReduction,EquipmentEffect.energyDiscount,EquipmentEffect.penetration,EquipmentEffect.extraAttackChance,EquipmentEffect.hpPercent,EquipmentEffect.cooldownReduction};

/// 自動効果のみ。単位は0.01%（10000=100%）。
class EquipmentEffectRule {
 EquipmentEffectRule({required this.effect,required this.pool,required Iterable<int> levelValues}):levelValues=List.unmodifiable(levelValues){
  if(this.levelValues.length!=10||this.levelValues.any((n)=>n<0||n>1000000))throw ArgumentError('Invalid equipment effect curve');
 }
 final EquipmentEffect effect;
 final EquipmentSkillPool pool;
 final List<int> levelValues;
}

/// 付与結果の読み取り用入力。永続化・抽選確定は別責務。
class EquipmentSkillGrant {
 const EquipmentSkillGrant({required this.instanceId,required this.milestone,required this.skillId,required this.level});
 final String instanceId,skillId;
 final int milestone,level;
}

/// 戦闘開始時に作成する不変の効果集計。戦闘エンジンへの接続は後続。
class EquipmentEffectSnapshot {
 EquipmentEffectSnapshot._(Map<EquipmentEffect,int> totals):totals=Map.unmodifiable(totals);
 final Map<EquipmentEffect,int> totals;
 int value(EquipmentEffect effect)=>totals[effect]??0;
}

class EquipmentEffectPolicy {
 EquipmentEffectPolicy({required Map<String,EquipmentEffectRule> rules,required Map<EquipmentEffect,int> caps})
  :_rules=Map.unmodifiable(rules),_caps=Map.unmodifiable(caps){
  for(final entry in _rules.entries){
   if(entry.key.trim().isEmpty||!_caps.containsKey(entry.value.effect))throw ArgumentError('Missing effect rule or cap');
  }
  for(final entry in _caps.entries){
   final bounded=switch(entry.key){
    EquipmentEffect.damageReduction||EquipmentEffect.energyDiscount||EquipmentEffect.cooldownReduction=>9999,
    EquipmentEffect.extraAttackChance||EquipmentEffect.criticalChance||EquipmentEffect.evasionChance||EquipmentEffect.penetration||EquipmentEffect.resistance=>10000,
    _=>1000000,
   };
   if(entry.value<0||entry.value>bounded)throw ArgumentError('Unsafe equipment effect cap');
  }
 }
 final Map<String,EquipmentEffectRule> _rules;
 final Map<EquipmentEffect,int> _caps;

 /// 同じIDの異なる付与枠は加算。枠の二重計上・分類違いは拒否。
 /// EX固定・ランダム枠は個別規則の接続まで明示的に未対応。
 EquipmentEffectSnapshot snapshot(AbyssInventory inventory,Iterable<EquipmentSkillGrant> grants){
  final equipped=inventory.equipped.values.toSet();
  final totals=<EquipmentEffect,int>{};
  final seen=<({String id,int milestone})>{};
  for(final grant in grants){
   final item=inventory.equipment[grant.instanceId];
   if(item==null)throw StateError('Unknown equipment skill owner');
   if(item.rarity==EquipmentRarity.ex)throw UnsupportedError('EX effect layout not connected');
   if(!EquipmentSkillPolicy.validSkillLevel(grant.level)||
      !EquipmentSkillPolicy.reachedMilestones(item.rarity,item.enhancement).contains(grant.milestone)||
      !seen.add((id:item.id,milestone:grant.milestone))){
    throw StateError('Invalid equipment skill grant');
   }
   final rule=_rules[grant.skillId];
   if(rule==null||rule.pool!=EquipmentSkillPoolOdds.poolForSlot(item.slot))throw StateError('Invalid equipment effect rule');
   if(!equipped.contains(item.id))continue;
   final cap=_caps[rule.effect]!;
   final sum=(totals[rule.effect]??0)+rule.levelValues[grant.level-1];
   totals[rule.effect]=sum>cap?cap:sum;
  }
  return EquipmentEffectSnapshot._(totals);
 }

 /// 追加攻撃の再帰発動を禁止する入口。実際の抽選・攻撃は後続。
 static bool canTriggerExtraAttack({required bool isExtraAttack})=>!isExtraAttack;
}
