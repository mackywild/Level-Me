import 'abyss_inventory.dart';
import 'world_engine.dart';

class PurificationItem {
 const PurificationItem({required this.id,required this.name});
 final String id,name;
}

class PurificationCatalog {
 PurificationCatalog(Iterable<PurificationItem> items){
  for(final item in items){
   if(!item.id.startsWith('item:')||item.id.length<=5||item.name.trim().isEmpty||_items.containsKey(item.id))throw const FormatException('Invalid purification item');
   _items[item.id]=item;
  }
 }
 final _items=<String,PurificationItem>{};
 static final production=PurificationCatalog(const []);
 List<PurificationItem> get items=>List.unmodifiable(_items.values);
 void validateSavedStatuses(WorldState world){
  if(_items.isEmpty&&(world.battle?.statuses.isNotEmpty??false))throw const FormatException('Unapproved saved battle status');
 }
 int preview({required WorldState world,required AbyssInventory inventory,required String id,required int expectedSequence,required int battleId,required int turn,required WorldEngine engine}){
  if(world.itemUseSequence!=expectedSequence)throw StateError('Stale item use request');
  if(world.itemUseSequence==0x7fffffffffffffff)throw StateError('Item use sequence overflow');
  if(!_items.containsKey(id))throw StateError('Purification item unavailable');
  if((inventory.stacks[id]??0)<1)throw StateError('Insufficient items');
  return engine.validatePurification(world,battleId,turn);
 }
 int use({required WorldState world,required AbyssInventory inventory,required String id,required int expectedSequence,required int battleId,required int turn,required WorldEngine engine,required int now}){
  final count=preview(world:world,inventory:inventory,id:id,expectedSequence:expectedSequence,battleId:battleId,turn:turn,engine:engine);
  inventory.removeStack(id,1);
  world.itemUseSequence++;
  engine.finishPurificationTurn(world,battleId,turn,now,_items[id]!.name);
  return count;
 }
}
