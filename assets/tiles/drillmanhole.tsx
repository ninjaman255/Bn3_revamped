<?xml version="1.0" encoding="UTF-8"?>
<tileset version="1.10" tiledversion="1.11.2" name="drillmanhole" tilewidth="64" tileheight="48" tilecount="6" columns="3" objectalignment="top">
 <grid orientation="isometric" width="64" height="48"/>
 <image source="drillmanhole.png" width="192" height="96"/>
 <tile id="0" probability="0">
  <objectgroup draworder="index" id="2">
   <object id="2" x="45" y="51">
    <polygon points="3,-3 -37,5 -29,-35 11,-43"/>
   </object>
  </objectgroup>
  <animation>
   <frame tileid="0" duration="166"/>
   <frame tileid="1" duration="166"/>
   <frame tileid="2" duration="166"/>
   <frame tileid="1" duration="166"/>
   <frame tileid="0" duration="166"/>
  </animation>
 </tile>
 <tile id="3">
  <objectgroup draworder="index" id="2">
   <object id="1" x="45" y="51">
    <polygon points="3,-3 -37,5 -29,-35 11,-43"/>
   </object>
  </objectgroup>
  <animation>
   <frame tileid="5" duration="166"/>
   <frame tileid="4" duration="166"/>
   <frame tileid="3" duration="166"/>
   <frame tileid="4" duration="166"/>
   <frame tileid="5" duration="166"/>
  </animation>
 </tile>
</tileset>
