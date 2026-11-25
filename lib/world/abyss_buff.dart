import 'abyss_inventory.dart';
import 'world_engine.dart';

class BuffItem {
 const BuffItem({required this.id,required this.name,required this.kind});
 final String id,name;
 final BattleBuff kind;
}

class BuffCatalog {
 BuffCatalog(Iterable<BuffItem> items){
  for(final item in items){
   if(!item.id.startsWith('item:')||item.id.length<=5||item.name.trim().isEmpty||_items.containsKey(item.id))throw const FormatException('Invalid buff item');
   _items[item.id]=item;
  }
 }
 final _items=<String,BuffItem>{};
 static final production=BuffCatalog(const []);
 List<BuffItem> get items=>List.unmodifiable(_items.values);
 void validateSavedEffects(WorldState world){
  final allowed=_items.values.map((item)=>item.kind).toSet();
  if(world.battle?.buffs.keys.any((kind)=>!allowed.contains(kind))??false)throw const FormatException('Unapproved saved battle buff');
 }
 BuffItem validate({required WorldState world,required AbyssInventory inventory,required String id,required int expectedSequence,required int battleId,required int turn,required WorldEngine engine}){
  if(world.itemUseSequence!=expectedSequence)throw StateError('Stale item use request');
  if(world.itemUseSequence==0x7fffffffffffffff)throw StateError('Item use sequence overflow');
  final item=_items[id];
  if(item==null)throw StateError('Buff item unavailable');
  if((inventory.stacks[id]??0)<1)throw StateError('Insufficient items');
  engine.validateBuff(world,item.kind,battleId,turn);
  return item;
 }
 void use({required WorldState world,required AbyssInventory inventory,required String id,required int expectedSequence,required int battleId,required int turn,required WorldEngine engine,required int now}){
  final item=validate(world:world,inventory:inventory,id:id,expectedSequence:expectedSequence,battleId:battleId,turn:turn,engine:engine);
  inventory.removeStack(id,1);
  world.itemUseSequence++;
  engine.finishBuffTurn(world,item.kind,battleId,turn,now,item.name);
 }
}
