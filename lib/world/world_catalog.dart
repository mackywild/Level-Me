/// Initial prologue slice. Stable IDs are independent of display names.
class WorldEncounter {
 const WorldEncounter(this.id,this.stage,this.title,this.enemy,this.hp,this.attack,this.defense,this.gold,
  {this.main=false,this.lifeDays=0,this.rank='F',this.timeResistant=false});
 final String id,title,enemy,rank;
 final int stage,hp,attack,defense,gold,lifeDays;
 final bool main,timeResistant;
}
class WorldCatalog {
 static const titles={1:'血の契約',2:'紅き瞳',3:'夜の捕食者'};
 static const encounters=[
  WorldEncounter('p01_main',1,'血の契約','契約の試練',10,3,0,40,main:true),
  WorldEncounter('p01_hunt',1,'通常討伐','契約の幻影',25,4,0,15),
  WorldEncounter('p01_explore',1,'探索','時の残影',35,5,2,25),
  WorldEncounter('p01_elite',1,'強敵討伐','覚醒の幻影',75,10,8,50,rank:'E'),
  WorldEncounter('p02_main',2,'紅き瞳','地下格闘王バルド',15,4,0,60,main:true,rank:'E'),
  WorldEncounter('p02_hunt',2,'通常討伐','格闘家',30,5,0,20,rank:'E'),
  WorldEncounter('p02_explore',2,'探索','闘技場の挑戦者',40,6,2,30,rank:'E'),
  WorldEncounter('p02_elite',2,'強敵討伐','闘技王の影',90,12,10,60,rank:'E'),
  WorldEncounter('p03_main',3,'夜の捕食者','裏社会の王ギルバート',20,5,1,80,main:true,lifeDays:365,rank:'E'),
  WorldEncounter('p03_hunt',3,'通常討伐','悪党',35,6,1,25,lifeDays:30,rank:'E'),
  WorldEncounter('p03_explore',3,'探索','闇の眷属',50,8,4,40,rank:'E'),
  WorldEncounter('p03_elite',3,'強敵討伐','黒幕の側近',110,15,12,80,lifeDays:90,rank:'D'),
 ];
 static WorldEncounter byId(String id)=>encounters.firstWhere((e)=>e.id==id,orElse:()=>throw ArgumentError('Unknown encounter: $id'));
}
