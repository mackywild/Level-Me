import 'world_engine.dart';

enum SkillKind { active, passive }

class SkillDefinition {
 const SkillDefinition({required this.id,required this.name,required this.kind});
 final String id,name;
 final SkillKind kind;
}

class SkillState {
 static const activeLimit=6,passiveLimit=3;
 final Map<String,int> _learned={};
 final List<String> _active=[],_passive=[];
 Map<String,int> get learned=>Map.unmodifiable(_learned);
 List<String> get active=>List.unmodifiable(_active);
 List<String> get passive=>List.unmodifiable(_passive);
 List<String> _slots(SkillKind kind)=>kind==SkillKind.active?_active:_passive;
 static int limit(SkillKind kind)=>kind==SkillKind.active?activeLimit:passiveLimit;
 static bool validId(String id)=>id.startsWith('skill:')&&id.length>6&&id.trim()==id;
 Map<String,dynamic> toJson()=>{'version':1,'learned':Map<String,int>.of(_learned),'active':List<String>.of(_active),'passive':List<String>.of(_passive)};
 factory SkillState.fromJson(Map<String,dynamic> j){
  if(j['version'] is! int||j['version']!=1)throw const FormatException('Invalid skill version');
  final state=SkillState();
  final learned=j['learned'];
  if(learned is! Map<String,dynamic>)throw const FormatException('Invalid learned skills');
  for(final entry in learned.entries){
   final count=entry.value;
   if(!validId(entry.key)||count is! int||count<0)throw const FormatException('Invalid skill record');
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
  state._learned[id]=0;
 }
 void equip(WorldState world,SkillState state,String id){
  final def=_require(world,id);
  if(!state._learned.containsKey(id))throw StateError('Skill not learned');
  final slots=state._slots(def.kind);
  if(slots.contains(id)||slots.length>=SkillState.limit(def.kind))throw StateError('Skill slot unavailable');
  slots.add(id);
 }
 void unequip(WorldState world,SkillState state,String id){
  final def=_require(world,id);
  if(!state._slots(def.kind).remove(id))throw StateError('Skill not equipped');
 }
}
