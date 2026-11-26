import 'abyss_equipment.dart';
import 'abyss_equipment_effects.dart';
import 'abyss_equipment_skill_master.dart';
import 'abyss_ex_equipment_skill.dart';
import 'abyss_inventory.dart';

enum ExSkillActivation { automatic, manual }
enum ExEffectStacking { additive, highestOnly }
enum ExEffectCapScope { sharedWithNormal, independent }

/// 固有効果の契約。特殊効果の意味・単位・実行は別途承認する。
/// この定義の登録だけでは戦闘で発動しない。
class ExEffectRule {
 ExEffectRule.normal({required EquipmentEffect effect,required this.stacking,required this.capScope,required this.cap})
  :id='normal:${effect.name}',normalEffect=effect {
  final approved=EquipmentSkillMaster.approvedCaps[effect]!;
  if(cap<=0||cap>approved||(capScope==ExEffectCapScope.sharedWithNormal&&cap!=approved)){
   throw ArgumentError('Invalid EX normal effect cap');
  }
 }
 ExEffectRule.special({required this.id,required this.stacking,required this.cap})
  :normalEffect=null,capScope=ExEffectCapScope.independent {
  if(!_validId(id,'equipment_ex_effect:')||cap<=0||cap>1000000)throw ArgumentError('Invalid EX special effect rule');
 }
 final String id;
 final EquipmentEffect? normalEffect;
 final ExEffectStacking stacking;
 final ExEffectCapScope capScope;
 final int cap;
 static bool _validId(String id,String prefix)=>id.startsWith(prefix)&&id.length>prefix.length&&id.trim()==id&&!RegExp(r'\s').hasMatch(id);
}

/// Lvごとの固定値を明示する。強化値を参照しない。代償は特殊規則への参照としてのみ定義可能。
class ExFixedEffect {
 ExFixedEffect({required this.ruleId,required Map<int,int> valuesByLevel,this.drawback=false})
  :valuesByLevel=Map.unmodifiable(valuesByLevel){
  if(ruleId.trim().isEmpty||this.valuesByLevel.isEmpty||this.valuesByLevel.entries.any((e)=>e.key<1||e.key>10||e.value<=0||e.value>1000000))throw ArgumentError('Invalid EX fixed effect values');
 }
 final String ruleId;
 final Map<int,int> valuesByLevel;
 final bool drawback;
}

class ExFixedSkillDefinition {
 ExFixedSkillDefinition({required this.id,required this.name,required this.activation,required Iterable<ExFixedEffect> effects})
  :effects=List.unmodifiable(effects){
  if(!ExEffectRule._validId(id,'equipment_ex_skill:')||name.trim().isEmpty||this.effects.isEmpty||this.effects.every((e)=>e.drawback)||this.effects.map((e)=>e.ruleId).toSet().length!=this.effects.length)throw ArgumentError('Invalid EX fixed skill definition');
 }
 final String id,name;
 final ExSkillActivation activation;
 final List<ExFixedEffect> effects;
}

/// 個別構成と固定効果規則を一括検証する。通常候補とは別の名前空間。
/// 入手、保存、抽選実行、効果集計、能動枠はまだ接続しない。
class ExEquipmentMaster {
 ExEquipmentMaster({required EquipmentCatalog equipment,required EquipmentSkillMaster randomMaster,required Iterable<ExEquipmentSkillLayout> layouts,required Iterable<ExFixedSkillDefinition> fixedSkills,required Iterable<ExEffectRule> effectRules}){
  for(final rule in effectRules){
   if(_rules.containsKey(rule.id))throw ArgumentError('Duplicate EX effect rule');
   _rules[rule.id]=rule;
  }
  final randomIds=randomMaster.entries.map((e)=>e.id).toSet();
  for(final skill in fixedSkills){
   if(_skills.containsKey(skill.id)||randomIds.contains(skill.id))throw ArgumentError('Duplicate or random EX fixed skill ID');
   for(final effect in skill.effects){
    final rule=_rules[effect.ruleId];
    if(rule==null||(effect.drawback&&rule.normalEffect!=null))throw ArgumentError('Unknown EX effect rule or invalid drawback');
    if(effect.valuesByLevel.values.any((v)=>v>rule.cap))throw ArgumentError('EX fixed value exceeds effect cap');
   }
   _skills[skill.id]=skill;
  }
  for(final layout in layouts){
   final item=equipment.find(layout.masterId);
   if(item==null||item.rarity!=EquipmentRarity.ex||item.slot!=layout.slot||_layouts.containsKey(layout.masterId))throw ArgumentError('Invalid EX equipment layout registration');
   if(!randomMaster.hasCandidates(layout.slot))throw ArgumentError('EX random pool unavailable');
   for(final fixed in layout.fixedSkills){
    final skill=_skills[fixed.id];
    if(skill==null||skill.effects.any((e)=>!e.valuesByLevel.containsKey(fixed.level)))throw ArgumentError('Unknown EX fixed skill or undefined level');
   }
   _layouts[layout.masterId]=layout;
  }
 }
 static const version=1;
 final _rules=<String,ExEffectRule>{};
 final _skills=<String,ExFixedSkillDefinition>{};
 final _layouts=<String,ExEquipmentSkillLayout>{};
 Map<String,ExEffectRule> get effectRules=>Map.unmodifiable(_rules);
 Map<String,ExFixedSkillDefinition> get fixedSkills=>Map.unmodifiable(_skills);
 Map<String,ExEquipmentSkillLayout> get layouts=>Map.unmodifiable(_layouts);
 ExEquipmentSkillLayout requireLayout(EquipmentInstance item){
  final layout=_layouts[item.masterId];
  if(layout==null)throw StateError('EX equipment layout unavailable');
  layout.unlockedFixedSkills(item);
  return layout;
 }
 List<({ExFixedSkillDefinition skill,int level})> resolveFixedSkills(EquipmentInstance item){
  final layout=requireLayout(item);
  return List.unmodifiable(layout.unlockedFixedSkills(item).map((fixed)=>(skill:_skills[fixed.id]!,level:fixed.level)));
 }
}
