import 'abyss_skill.dart';
import 'world_engine.dart';

/// 設計書02 v1.1付録B・時間重奏案。静止爪撃250%・無料習得は試験案。
/// 超時連撃は既存複合爪撃と同等の400%/90日、停止共有CDを使用する。
class ChronoFinisherCandidates {
 static const definitions=[
  SkillDefinition(id:'skill:still_claw',name:'静止爪撃',kind:SkillKind.active,
   acquisition:SkillAcquisition(clearedStage:12),
   execution:ActiveSkillSpec(id:'skill:still_claw',name:'静止爪撃',powerPercent:250,physicalCost:0,cooldown:0,effect:ActiveSkillEffect.stopAttack,lifeCost:45)),
  SkillDefinition(id:'skill:chrono_combo',name:'超時連撃',kind:SkillKind.active,
   acquisition:SkillAcquisition(clearedStage:12),
   execution:ActiveSkillSpec(id:'skill:chrono_combo',name:'超時連撃',powerPercent:400,physicalCost:0,cooldown:0,effect:ActiveSkillEffect.stopAttack,lifeCost:90)),
 ];
}
