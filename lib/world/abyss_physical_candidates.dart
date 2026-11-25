import 'abyss_skill.dart';
import 'world_engine.dart';

/// 設計書02 v1.1の候補値。習得条件・CDは未承認。
/// 本番マスターへの接続は禁止。CD0は実行試験用の仮値。
class PhysicalSkillCandidates {
 static const definitions=[
  SkillDefinition(id:'skill:swift_fist',name:'瞬拳',kind:SkillKind.active,execution:ActiveSkillSpec(id:'skill:swift_fist',name:'瞬拳',powerPercent:110,physicalCost:5,cooldown:0)),
  SkillDefinition(id:'skill:double_claw',name:'双爪',kind:SkillKind.active,execution:ActiveSkillSpec(id:'skill:double_claw',name:'双爪',powerPercent:65,hits:2,physicalCost:6,cooldown:0)),
  SkillDefinition(id:'skill:shock',name:'震撃',kind:SkillKind.active,execution:ActiveSkillSpec(id:'skill:shock',name:'震撃',powerPercent:200,physicalCost:12,cooldown:0)),
  SkillDefinition(id:'skill:flurry',name:'乱舞',kind:SkillKind.active,execution:ActiveSkillSpec(id:'skill:flurry',name:'乱舞',powerPercent:40,hits:6,physicalCost:15,cooldown:0)),
  SkillDefinition(id:'skill:crimson_flurry',name:'紅蓮乱舞',kind:SkillKind.active,execution:ActiveSkillSpec(id:'skill:crimson_flurry',name:'紅蓮乱舞',powerPercent:45,hits:10,physicalCost:25,cooldown:0)),
 ];
}
