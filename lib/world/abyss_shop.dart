import 'abyss_inventory.dart';
import 'world_engine.dart';

enum ShopCurrency { gold, magicCrystals }

class ShopOffer {
 const ShopOffer({required this.id,required this.materialId,required this.currency,required this.price,required this.quantity});
 final String id,materialId;
 final ShopCurrency currency;
 final int price,quantity;
}

class ShopCatalog {
 ShopCatalog(Iterable<ShopOffer> offers){
  for(final offer in offers){
   if(!offer.id.startsWith('shop:')||offer.id.length<=5||!offer.materialId.startsWith('item:')||offer.materialId.length<=5||offer.price<=0||offer.price>1000000||offer.quantity<=0||offer.quantity>1000000||_offers.containsKey(offer.id))throw const FormatException('Invalid shop offer');
   _offers[offer.id]=offer;
  }
 }
 final _offers=<String,ShopOffer>{};
 static final production=ShopCatalog(const []);
 List<ShopOffer> get offers=>List.unmodifiable(_offers.values);
 void validateMaterials(bool Function(ShopOffer) valid){
  if(_offers.values.any((offer)=>!valid(offer)))throw const FormatException('Invalid shop material master');
 }
 ShopOffer purchase({required WorldState world,required AbyssInventory inventory,required String offerId,required int expectedSequence}){
  if(world.battle!=null)throw StateError('Shop unavailable in battle');
  if(world.shopSequence!=expectedSequence)throw StateError('Stale shop request');
  final next=world.shopSequence+1;
  if(next<=world.shopSequence)throw StateError('Shop sequence overflow');
  final offer=_offers[offerId];
  if(offer==null)throw StateError('Shop offer unavailable');
  final balance=offer.currency==ShopCurrency.gold?world.gold:world.magicCrystals;
  if(balance<offer.price)throw StateError('Insufficient shop currency');
  final count=inventory.stacks[offer.materialId]??0;
  if(count+offer.quantity<=count)throw StateError('Stack overflow');
  inventory.addStack(offer.materialId,offer.quantity);
  if(offer.currency==ShopCurrency.gold){
   world.gold-=offer.price;
  }else{
   world.magicCrystals-=offer.price;
  }
  world.shopSequence=next;
  return offer;
 }
}
