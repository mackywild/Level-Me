import 'abyss_skill.dart';
import 'world_engine.dart';

/// 設計候補の寿命・威力。ST06条件、独立CD5、無料習得は試験案。
/// 本番カタログへの接続は禁止。
class AccelerationSkillCandidates {
 static const definitions=[
  SkillDefinition(id:'skill:speed_claw',name:'時速爪',kind:SkillKind.active,
   acquisition:SkillAcquisition(clearedStage:6),
   execution:ActiveSkillSpec(id:'skill:speed_claw',name:'時速爪',powerPercent:250,physicalCost:0,cooldown:5,effect:ActiveSkillEffect.accelerationAttack,lifeCost:10)),
  SkillDefinition(id:'skill:gale_claws',name:'疾風乱爪',kind:SkillKind.active,
   acquisition:SkillAcquisition(clearedStage:6),
   execution:ActiveSkillSpec(id:'skill:gale_claws',name:'疾風乱爪',powerPercent:50,hits:8,physicalCost:0,cooldown:5,effect:ActiveSkillEffect.accelerationAttack,lifeCost:45)),
 ];
}
