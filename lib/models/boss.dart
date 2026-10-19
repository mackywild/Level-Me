class Boss {
 const Boss({required this.id,required this.title,required this.description,required this.maxHp,required this.hp,required this.rewardExp,required this.defeats});
 final String id,title,description;
 final int maxHp,hp,rewardExp,defeats;
 Boss damage(int amount) {
  final next=hp-amount;
  return Boss(id:id,title:title,description:description,maxHp:maxHp,hp:next>0?next:maxHp,rewardExp:rewardExp,defeats:next>0?defeats:defeats+1);
 }
 Map<String,dynamic> toJson()=>{'id':id,'title':title,'description':description,'maxHp':maxHp,'hp':hp,'rewardExp':rewardExp,'defeats':defeats};
 factory Boss.fromJson(Map<String,dynamic> j)=>Boss(id:j['id'] as String,title:j['title'] as String,description:j['description'] as String,maxHp:j['maxHp'] as int,hp:j['hp'] as int,rewardExp:j['rewardExp'] as int,defeats:j['defeats'] as int? ?? 0);
}
