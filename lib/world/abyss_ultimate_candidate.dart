import 'abyss_skill.dart';
import 'world_engine.dart';

/// 設計書02 v1.1付録Bの時空断裂。ST18・独立CD8・無料習得は試験案。
/// 時間の範囲の単体攻撃のみ。本番カタログに接続しない。
class UltimateSkillCandidate {
 static const definition=SkillDefinition(
  id:'skill:spacetime_break',name:'時空断裂',kind:SkillKind.active,
  acquisition:SkillAcquisition(clearedStage:18),
  execution:ActiveSkillSpec(id:'skill:spacetime_break',name:'時空断裂',powerPercent:500,physicalCost:0,cooldown:8,effect:ActiveSkillEffect.ultimateAttack,lifeCost:180),
 );
}
