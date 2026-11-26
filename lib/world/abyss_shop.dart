import 'abyss_inventory.dart';
import 'abyss_equipment.dart';
import 'world_engine.dart';

enum ShopCurrency { gold, magicCrystals }

class ShopOffer {
 const ShopOffer({required this.id,required this.materialId,required this.currency,required this.price,required this.quantity});
 const ShopOffer.equipment({required this.id,required String equipmentId,required this.price}):materialId=equipmentId,currency=ShopCurrency.magicCrystals,quantity=1;
 final String id,materialId;
 bool get isEquipment=>materialId.startsWith('equipment:');
 String get rewardId=>materialId;
 final ShopCurrency currency;
 final int price,quantity;
}

class ShopCatalog {
 ShopCatalog(Iterable<ShopOffer> offers){
  for(final offer in offers){
   if(!offer.id.startsWith('shop:')||offer.id.length<=5||!(offer.isEquipment?offer.materialId.length>10&&offer.quantity==1&&offer.currency==ShopCurrency.magicCrystals:offer.materialId.startsWith('item:')&&offer.materialId.length>5)||offer.price<=0||offer.price>1000000||offer.quantity<=0||offer.quantity>1000000||_offers.containsKey(offer.id))throw const FormatException('Invalid shop offer');
   _offers[offer.id]=offer;
  }
 }
 final _offers=<String,ShopOffer>{};
 static final production=ShopCatalog(const []);
 List<ShopOffer> get offers=>List.unmodifiable(_offers.values);
 void validateMaterials(bool Function(ShopOffer) valid){
  if(_offers.values.any((offer)=>!offer.isEquipment&&!valid(offer)))throw const FormatException('Invalid shop material master');
 }
 void validateEquipment(EquipmentCatalog catalog){
  for(final offer in _offers.values.where((offer)=>offer.isEquipment)){
   final definition=catalog.find(offer.rewardId);
   if(definition==null||definition.rarity==EquipmentRarity.ex)throw const FormatException('Invalid shop equipment master');
  }
 }
 ShopOffer validate({required WorldState world,required AbyssInventory inventory,required String offerId,required int expectedSequence,EquipmentCatalog? equipmentCatalog}){
  if(world.battle!=null)throw StateError('Shop unavailable in battle');
  if(world.shopSequence!=expectedSequence)throw StateError('Stale shop request');
  final next=world.shopSequence+1;
  if(next<=world.shopSequence)throw StateError('Shop sequence overflow');
  final offer=_offers[offerId];
  if(offer==null)throw StateError('Shop offer unavailable');
  final balance=offer.currency==ShopCurrency.gold?world.gold:world.magicCrystals;
  if(balance<offer.price)throw StateError('Insufficient shop currency');
  if(offer.isEquipment){
   final definition=equipmentCatalog?.find(offer.rewardId);
   // EXは入手時固有スキルの仕様との整合が未確定。
   if(definition==null||definition.rarity==EquipmentRarity.ex)throw StateError('Shop equipment unavailable');
  }else{
   final count=inventory.stacks[offer.materialId]??0;
   if(count+offer.quantity<=count)throw StateError('Stack overflow');
  }
  return offer;
 }
 ShopOffer purchase({required WorldState world,required AbyssInventory inventory,required String offerId,required int expectedSequence,EquipmentCatalog? equipmentCatalog}){
  final offer=validate(world:world,inventory:inventory,offerId:offerId,expectedSequence:expectedSequence,equipmentCatalog:equipmentCatalog);
  if(offer.isEquipment){
   final definition=equipmentCatalog!.find(offer.rewardId)!;
   inventory.addEquipment(definition.id,definition.slot,definition.rarity);
  }else{
   inventory.addStack(offer.materialId,offer.quantity);
  }
  if(offer.currency==ShopCurrency.gold){
   world.gold-=offer.price;
  }else{
   world.magicCrystals-=offer.price;
  }
  world.shopSequence++;
  return offer;
 }
}
