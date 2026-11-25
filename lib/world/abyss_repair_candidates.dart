import 'abyss_skill.dart';
import 'world_engine.dart';

/// 設計書02 v1.1の効果・寿命候補値。ST03・独立CD5・無料習得は試験案。
/// 本番カタログに接続しない。
class RepairSkillCandidates {
 static const definitions=[
  SkillDefinition(id:'skill:wound_repair',name:'傷時修復',kind:SkillKind.active,acquisition:SkillAcquisition(clearedStage:3),
   execution:ActiveSkillSpec(id:'skill:wound_repair',name:'傷時修復',powerPercent:0,physicalCost:0,cooldown:5,effect:ActiveSkillEffect.repairHp,lifeCost:7)),
  SkillDefinition(id:'skill:body_repair',name:'肉体修復',kind:SkillKind.active,acquisition:SkillAcquisition(clearedStage:3),
   execution:ActiveSkillSpec(id:'skill:body_repair',name:'肉体修復',powerPercent:0,physicalCost:0,cooldown:5,effect:ActiveSkillEffect.repairHp,lifeCost:21)),
  SkillDefinition(id:'skill:time_cleanse',name:'時の浄化',kind:SkillKind.active,acquisition:SkillAcquisition(clearedStage:3),
   execution:ActiveSkillSpec(id:'skill:time_cleanse',name:'時の浄化',powerPercent:0,physicalCost:0,cooldown:5,effect:ActiveSkillEffect.timeCleanse,lifeCost:30)),
  SkillDefinition(id:'skill:life_rewind',name:'生命逆行',kind:SkillKind.active,acquisition:SkillAcquisition(clearedStage:3),
   execution:ActiveSkillSpec(id:'skill:life_rewind',name:'生命逆行',powerPercent:0,physicalCost:0,cooldown:5,effect:ActiveSkillEffect.repairHp,lifeCost:180)),
  SkillDefinition(id:'skill:full_repair',name:'完全修復',kind:SkillKind.active,acquisition:SkillAcquisition(clearedStage:3),
   execution:ActiveSkillSpec(id:'skill:full_repair',name:'完全修復',powerPercent:0,physicalCost:0,cooldown:5,effect:ActiveSkillEffect.repairHp,lifeCost:365)),
 ];
}
