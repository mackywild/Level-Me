import 'abyss_skill.dart';
import 'world_engine.dart';

/// 本番カタログには接続しない。CD5は連続使用防止の試験用仮値。
class TimeSkillCandidates {
 static const foresight=SkillDefinition(
  id:'skill:foresight',name:'未来視',kind:SkillKind.active,
  acquisition:SkillAcquisition(clearedStage:9),
  execution:ActiveSkillSpec(id:'skill:foresight',name:'未来視',powerPercent:0,physicalCost:0,cooldown:5,effect:ActiveSkillEffect.foresight,lifeCost:14),
 );
}
