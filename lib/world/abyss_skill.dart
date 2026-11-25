import 'world_engine.dart';

enum SkillKind { active, passive }

class SkillDefinition {
 const SkillDefinition({required this.id,required this.name,required this.kind,this.execution});
 final String id,name;
 final SkillKind kind;
 final ActiveSkillSpec? execution;
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
 Map<String,dynamic> toJson()=>{'version':1,'revision':_revision,'learned':Map<String,int>.of(_learned),'active':List<String>.of(_active),'passive':List<String>.of(_passive)};
 factory SkillState.fromJson(Map<String,dynamic> j){
  if(j['version'] is! int||j['version']!=1)throw const FormatException('Invalid skill version');
  final state=SkillState();
  final revision=j.containsKey('revision')?j['revision']:0;
  if(revision is! int||revision<0)throw const FormatException('Invalid skill revision');
  state._revision=revision;
  final learned=j['learned'];
  if(learned is! Map<String,dynamic>)throw const FormatException('Invalid learned skills');
  for(final entry in learned.entries){
   final count=entry.value;
   if(!validId(entry.key)||count is! int||count!=0)throw const FormatException('Invalid skill record');
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
   _definitions[def.id]=def;
  }
 }
 final _definitions=<String,SkillDefinition>{};
 static final production=SkillCatalog(const []);
 List<SkillDefinition> get definitions=>List.unmodifiable(_definitions.values);
 SkillDefinition? find(String id)=>_definitions[id];
 void validateSaved(SkillState state){
  if(state.learned.keys.any((id)=>find(id)==null))throw const FormatException('Unapproved learned skill');
  for(final kind in SkillKind.values){
   if(state._slots(kind).any((id)=>find(id)?.kind!=kind))throw const FormatException('Invalid skill kind');
  }
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
