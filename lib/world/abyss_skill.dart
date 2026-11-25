import 'world_engine.dart';

enum SkillKind { active, passive }

/// 試験用の固定加算補正。HP・エネルギー上限・会心率は変更しない。
class PassiveStatBonus {
 const PassiveStatBonus({this.physical=0,this.magic=0,this.defense=0});
 final int physical,magic,defense;
 void validate(){
  if([physical,magic,defense].any((v)=>v<0||v>1000000))throw const FormatException('Invalid passive stat bonus');
 }
}

class SkillDefinition {
 const SkillDefinition({required this.id,required this.name,required this.kind,this.execution,this.passiveBonus});
 final String id,name;
 final SkillKind kind;
 final ActiveSkillSpec? execution;
 final PassiveStatBonus? passiveBonus;
}

/// 試験用成長規則。性能への反映は行わない。
class SkillMastery {
 static const maxLevel=10,usesPerLevel=10,maxUses=(maxLevel-1)*usesPerLevel;
 static int level(int uses){
  if(uses<0||uses>maxUses)throw RangeError.range(uses,0,maxUses);
  return 1+uses~/usesPerLevel;
 }
 static int next(int uses){
  level(uses);
  return uses==maxUses?uses:uses+1;
 }
}

class SkillState {
 static const activeLimit=6,passiveLimit=3;
 int _revision=0;
 int get revision=>_revision;
 void _checkRevision(){if(_revision==0x7fffffffffffffff)throw StateError('Skill revision overflow');}
 final Map<String,int> _learned={};
 final List<String> _active=[],_passive=[];
 Map<String,int> get learned=>Map.unmodifiable(_learned);
 List<String> get active=>List.unmodifiable(_active);
 List<String> get passive=>List.unmodifiable(_passive);
 List<String> _slots(SkillKind kind)=>kind==SkillKind.active?_active:_passive;
 static int limit(SkillKind kind)=>kind==SkillKind.active?activeLimit:passiveLimit;
 static bool validId(String id)=>id.startsWith('skill:')&&id.length>6&&id.trim()==id;
 Map<String,dynamic> toJson()=>{'version':2,'revision':_revision,'learned':Map<String,int>.of(_learned),'active':List<String>.of(_active),'passive':List<String>.of(_passive)};
 factory SkillState.fromJson(Map<String,dynamic> j){
  final version=j['version'];
  if(version is! int||(version!=1&&version!=2))throw const FormatException('Invalid skill version');
  final state=SkillState();
  final revision=version==1&&!j.containsKey('revision')?0:j['revision'];
  if(revision is! int||revision<0)throw const FormatException('Invalid skill revision');
  state._revision=revision;
  final learned=j['learned'];
  if(learned is! Map<String,dynamic>)throw const FormatException('Invalid learned skills');
  for(final entry in learned.entries){
   final count=entry.value;
   if(!validId(entry.key)||count is! int||(version==1?count!=0:count<0||count>SkillMastery.maxUses))throw const FormatException('Invalid skill record');
   state._learned[entry.key]=count;
  }
  final seen=<String>{};
  for(final kind in SkillKind.values){
   final raw=j[kind.name];
   if(raw is! List||raw.length>limit(kind))throw const FormatException('Invalid skill slots');
   for(final id in raw){
    if(id is! String||!state._learned.containsKey(id)||!seen.add(id))throw const FormatException('Invalid equipped skill');
    state._slots(kind).add(id);
   }
  }
  return state;
 }
 SkillState();
}

class SkillCatalog {
 SkillCatalog(Iterable<SkillDefinition> definitions){
  for(final def in definitions){
   if(!SkillState.validId(def.id)||def.name.trim().isEmpty||_definitions.containsKey(def.id))throw const FormatException('Invalid skill master');
   final spec=def.execution;
   if(spec!=null){
    spec.validate();
    if(def.kind!=SkillKind.active||spec.id!=def.id||spec.name!=def.name)throw const FormatException('Invalid skill execution mapping');
   }
   final bonus=def.passiveBonus;
   if(bonus!=null){
    bonus.validate();
    if(def.kind!=SkillKind.passive)throw const FormatException('Invalid passive skill mapping');
   }
   _definitions[def.id]=def;
  }
 }
 final _definitions=<String,SkillDefinition>{};
 static final production=SkillCatalog(const []);
 List<SkillDefinition> get definitions=>List.unmodifiable(_definitions.values);
 SkillDefinition? find(String id)=>_definitions[id];
 void validateSaved(SkillState state){
  if(state.learned.keys.any((id)=>find(id)==null))throw const FormatException('Unapproved learned skill');
  for(final entry in state.learned.entries){
   if(entry.value>0&&find(entry.key)?.execution==null)throw const FormatException('Unapproved skill mastery');
  }
  for(final kind in SkillKind.values){
   if(state._slots(kind).any((id)=>find(id)?.kind!=kind))throw const FormatException('Invalid skill kind');
  }
 }
 /// 装備補正後に固定値を加算する。装着順に依存せず、戦闘開始時のstatsに反映する。
 WorldStats applyPassive(WorldStats base,SkillState state){
  validateSaved(state);
  var physical=base.physical,magic=base.magic,defense=base.defense;
  int add(int value,int bonus){
   if(value<0||value>0x7fffffffffffffff-bonus)throw StateError('Passive stat overflow');
   return value+bonus;
  }
  for(final id in state.passive){
   final bonus=find(id)?.passiveBonus;
   if(bonus==null)continue;
   physical=add(physical,bonus.physical);
   magic=add(magic,bonus.magic);
   defense=add(defense,bonus.defense);
  }
  return WorldStats(hp:base.hp,physical:physical,magic:magic,defense:defense,physicalMax:base.physicalMax,magicMax:base.magicMax,crit:base.crit);
 }
 List<ActiveSkillSpec> snapshot(SkillState state){
  validateSaved(state);
  return List<ActiveSkillSpec>.unmodifiable([for(final id in state.active) ?find(id)?.execution]);
 }
 void validateBattle(WorldState world,SkillState state){
  final b=world.battle;
  if(b==null)return;
  // 旧戦闘は空snapshotのまま継続可能。非空の場合は現在の装着定義との一致を必須とする。
  if(b.activeSkills.isEmpty)return;
  final expected=snapshot(state);
  if(expected.length!=b.activeSkills.length)throw const FormatException('Invalid battle skill loadout');
  for(var i=0;i<expected.length;i++){
   final a=expected[i],saved=b.activeSkills[i];
   if(a.id!=saved.id||a.name!=saved.name||a.powerPercent!=saved.powerPercent||a.physicalCost!=saved.physicalCost||a.cooldown!=saved.cooldown)throw const FormatException('Invalid battle skill snapshot');
  }
 }
 /// 実行と成長を同じ作業用状態で処理する。失敗時は呼出元が作業状態を破棄する。
 void executeActive(WorldEngine engine,WorldState world,SkillState state,String id,int battleId,int turn,int now){
  validateSaved(state);
  validateBattle(world,state);
  final count=state._learned[id];
  if(count==null||!state.active.contains(id)||find(id)?.execution==null)throw StateError('Skill unavailable');
  final next=SkillMastery.next(count);
  engine.actActiveSkill(world,id,battleId,turn,now);
  state._learned[id]=next;
 }
 SkillDefinition _require(WorldState world,String id){
  if(world.battle!=null)throw StateError('Skill change unavailable in battle');
  final def=find(id);
  if(def==null)throw StateError('Skill unavailable');
  return def;
 }
 // 習得条件・通貨消費は未承認。本番空カタログのため使用不可。
 void learn(WorldState world,SkillState state,String id){
  _require(world,id);
  if(state._learned.containsKey(id))throw StateError('Skill already learned');
  state._checkRevision();
  state._learned[id]=0;
  state._revision++;
 }
 void equip(WorldState world,SkillState state,String id){
  final def=_require(world,id);
  if(!state._learned.containsKey(id))throw StateError('Skill not learned');
  final slots=state._slots(def.kind);
  if(slots.contains(id)||slots.length>=SkillState.limit(def.kind))throw StateError('Skill slot unavailable');
  state._checkRevision();
  slots.add(id);
  state._revision++;
 }
 void unequip(WorldState world,SkillState state,String id){
  final def=_require(world,id);
  if(!state._slots(def.kind).contains(id))throw StateError('Skill not equipped');
  state._checkRevision();
  state._slots(def.kind).remove(id);
  state._revision++;
 }
}
