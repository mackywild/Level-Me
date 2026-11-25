import 'abyss_skill.dart';
import 'world_engine.dart';

/// 設計書02 v1.1付録Bの紅き覚醒。ST12・独立CD5・無料習得は試験案。
/// 覚醒ゲージ案とは別。本番カタログに接続しない。
class AwakeningSkillCandidate {
 static const definition=SkillDefinition(
  id:'skill:crimson_awakening',name:'紅き覚醒',kind:SkillKind.active,
  acquisition:SkillAcquisition(clearedStage:12),
  execution:ActiveSkillSpec(id:'skill:crimson_awakening',name:'紅き覚醒',powerPercent:0,physicalCost:0,cooldown:5,effect:ActiveSkillEffect.crimsonAwakening,lifeCost:30),
 );
}
