import 'dart:math';
import 'abyss_inventory.dart';
import 'world_engine.dart';

enum RecoveryTarget { hp, physical, magic }

class RecoveryItem {
 const RecoveryItem({required this.id,required this.name,required this.target,required this.percent});
 final String id,name;
 final RecoveryTarget target;
 final int percent;
}

class ConsumableCatalog {
 ConsumableCatalog(Iterable<RecoveryItem> items){
  for(final item in items){
   if(!item.id.startsWith('item:')||item.id.length<=5||item.name.trim().isEmpty||item.percent<=0||item.percent>100||_items.containsKey(item.id))throw const FormatException('Invalid recovery item');
   _items[item.id]=item;
  }
 }
 final _items=<String,RecoveryItem>{};
 // 回復量・入手経路の正式承認までは本番で使用不可。
 static final production=ConsumableCatalog(const []);
 RecoveryItem? find(String id)=>_items[id];
 List<RecoveryItem> get items=>List.unmodifiable(_items.values);

 int preview({required WorldState world,required WorldStats stats,required AbyssInventory inventory,required String id,required int expectedSequence}){
  if(world.battle!=null)throw StateError('Consumable unavailable in battle');
  if(world.itemUseSequence!=expectedSequence)throw StateError('Stale item use request');
  final next=world.itemUseSequence+1;
  if(next<=world.itemUseSequence)throw StateError('Item use sequence overflow');
  final item=find(id);
  if(item==null)throw StateError('Recovery item unavailable');
  if((inventory.stacks[id]??0)<1)throw StateError('Insufficient items');
  final (current,maximum)=switch(item.target){
   RecoveryTarget.hp=>(world.hp,stats.hp),
   RecoveryTarget.physical=>(world.physical,stats.physicalMax),
   RecoveryTarget.magic=>(world.magic,stats.magicMax),
  };
  if(maximum<=0||current<0||current>=maximum)throw StateError('Recovery not needed');
  // 最大値基準、整数切り捨て、最低1。上限を超えない。
  final amount=min(maximum-current,max(1,(maximum~/100)*item.percent+(maximum%100)*item.percent~/100));
  return amount;
 }
 int use({required WorldState world,required WorldStats stats,required AbyssInventory inventory,required String id,required int expectedSequence}){
  final amount=preview(world:world,stats:stats,inventory:inventory,id:id,expectedSequence:expectedSequence);
  final item=find(id)!;
  inventory.removeStack(id,1);
  switch(item.target){
   case RecoveryTarget.hp:world.hp+=amount;
   case RecoveryTarget.physical:world.physical+=amount;
   case RecoveryTarget.magic:world.magic+=amount;
  }
  world.itemUseSequence++;
  return amount;
 }
}
