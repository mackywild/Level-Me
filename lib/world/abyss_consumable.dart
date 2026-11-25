import 'abyss_inventory.dart';
import 'world_engine.dart';

enum RecoveryTarget { hp, physical, magic, all }

class RecoveryItem {
 const RecoveryItem({required this.id,required this.name,required this.target,required this.percent});
 final String id,name;
 final RecoveryTarget target;
 final int percent;
}

class ConsumableCatalog {
 ConsumableCatalog(Iterable<RecoveryItem> items){
  for(final item in items){
   if(!item.id.startsWith('item:')||item.id.length<=5||item.name.trim().isEmpty||item.percent<=0||item.percent>100||(item.target==RecoveryTarget.all&&item.percent!=100)||_items.containsKey(item.id))throw const FormatException('Invalid recovery item');
   _items[item.id]=item;
  }
 }
 final _items=<String,RecoveryItem>{};
 // 回復量・入手経路の正式承認までは本番で使用不可。
 static final production=ConsumableCatalog(const []);
 RecoveryItem? find(String id)=>_items[id];
 List<RecoveryItem> get items=>List.unmodifiable(_items.values);

 ({int hp,int physical,int magic}) _amounts(WorldState world,WorldStats stats,RecoveryItem item){
  int amount(int current,int maximum)=>WorldEngine.recoveryAmount(current,maximum,item.percent);
  return (
   hp:item.target==RecoveryTarget.hp||item.target==RecoveryTarget.all?amount(world.hp,stats.hp):0,
   physical:item.target==RecoveryTarget.physical||item.target==RecoveryTarget.all?amount(world.physical,stats.physicalMax):0,
   magic:item.target==RecoveryTarget.magic||item.target==RecoveryTarget.all?amount(world.magic,stats.magicMax):0,
  );
 }
 // 複数資源の合計値は既存APIの表示用。個別の回復量は最大値を超えない。
 int _total(({int hp,int physical,int magic}) amounts){
  final sum=BigInt.from(amounts.hp)+BigInt.from(amounts.physical)+BigInt.from(amounts.magic);
  if(sum>BigInt.from(0x7fffffffffffffff))throw StateError('Recovery total overflow');
  return sum.toInt();
 }
 int preview({required WorldState world,required WorldStats stats,required AbyssInventory inventory,required String id,required int expectedSequence}){
  if(world.battle!=null)throw StateError('Consumable unavailable in battle');
  return _preview(world:world,stats:stats,inventory:inventory,id:id,expectedSequence:expectedSequence);
 }
 int previewInBattle({required WorldState world,required AbyssInventory inventory,required String id,required int expectedSequence,required int battleId,required int expectedTurn}){
  final battle=world.battle;
  if(battle==null||battle.id!=battleId||battle.turn!=expectedTurn)throw StateError('Stale battle command');
  if(battle.turn==0x7fffffffffffffff)throw StateError('Battle turn overflow');
  return _preview(world:world,stats:battle.stats,inventory:inventory,id:id,expectedSequence:expectedSequence);
 }
 int _preview({required WorldState world,required WorldStats stats,required AbyssInventory inventory,required String id,required int expectedSequence}){
  if(world.itemUseSequence!=expectedSequence)throw StateError('Stale item use request');
  final next=world.itemUseSequence+1;
  if(next<=world.itemUseSequence)throw StateError('Item use sequence overflow');
  final item=find(id);
  if(item==null)throw StateError('Recovery item unavailable');
  if((inventory.stacks[id]??0)<1)throw StateError('Insufficient items');
  final amount=_total(_amounts(world,stats,item));
  if(amount==0)throw StateError('Recovery not needed');
  return amount;
 }
 int use({required WorldState world,required WorldStats stats,required AbyssInventory inventory,required String id,required int expectedSequence}){
  final amount=preview(world:world,stats:stats,inventory:inventory,id:id,expectedSequence:expectedSequence);
  _apply(world,stats,inventory,id);
  return amount;
 }
 int useInBattle({required WorldState world,required AbyssInventory inventory,required String id,required int expectedSequence,required int battleId,required int expectedTurn,required WorldEngine engine,required int now}){
  final amount=previewInBattle(world:world,inventory:inventory,id:id,expectedSequence:expectedSequence,battleId:battleId,expectedTurn:expectedTurn);
  _apply(world,world.battle!.stats,inventory,id);
  engine.finishRecoveryTurn(world,battleId,expectedTurn,now,find(id)!.name,amount);
  return amount;
 }
 void _apply(WorldState world,WorldStats stats,AbyssInventory inventory,String id){
  final amounts=_amounts(world,stats,find(id)!);
  inventory.removeStack(id,1);
  world.hp+=amounts.hp;
  world.physical+=amounts.physical;
  world.magic+=amounts.magic;
  world.itemUseSequence++;
 }
}
