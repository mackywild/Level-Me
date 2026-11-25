import 'abyss_skill.dart';
import 'world_engine.dart';

/// 設計書02 v1.1の時間逆行。無料習得は試験用、本番カタログに接続しない。
class RewindSkillCandidate {
 static const definition=SkillDefinition(
  id:'skill:rewind',name:'時間逆行',kind:SkillKind.active,
  acquisition:SkillAcquisition(clearedStage:16),
  execution:ActiveSkillSpec(id:'skill:rewind',name:'時間逆行',powerPercent:0,physicalCost:0,cooldown:8,effect:ActiveSkillEffect.rewindHp,lifeCost:90),
 );
}
