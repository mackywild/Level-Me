import 'abyss_skill.dart';
import 'world_engine.dart';

/// 設計書02 v1.1の寿命獲得補正。ST03・無料習得は試験案。
/// 本番カタログに接続しない。
class PredationSkillCandidates {
 static const definitions=[
  SkillDefinition(id:'skill:time_absorption',name:'時の吸収',kind:SkillKind.passive,
   acquisition:SkillAcquisition(clearedStage:3),lifeRewardBonus:LifeRewardBonus.timeAbsorption),
  SkillDefinition(id:'skill:predator_instinct',name:'捕食本能',kind:SkillKind.passive,
   acquisition:SkillAcquisition(clearedStage:3),lifeRewardBonus:LifeRewardBonus.predatorInstinct),
 ];
}
