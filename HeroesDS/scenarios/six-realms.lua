-- HeroesDS scenario (tools/make_m3.py --dump-scenario; docs/FORMATS.md).
-- Province ids and county ids belong to one generated map: keep them.
return {
  title = "Six realms (seed 77)",
  player = "order",   -- the realm the player has (its view: fog of war)
  fog = true,
  realms = {   -- city = true: a city-state
    { id = "life", name = "Life", color = { 230, 230, 240 } },
    { id = "order", name = "Order", color = { 60, 110, 220 } },
    { id = "death", name = "Death", color = { 120, 60, 150 } },
    { id = "chaos", name = "Chaos", color = { 210, 50, 40 } },
    { id = "nature", name = "Nature", color = { 60, 170, 70 } },
    { id = "might", name = "Might", color = { 220, 160, 40 } },
    { id = "city_belpel", name = "Free City of Belpel", color = { 190, 175, 145 }, city = true },
    { id = "city_ostgor", name = "Free City of Ostgor", color = { 160, 178, 190 }, city = true },
    { id = "city_dunnorost", name = "Free City of Dunnorost", color = { 192, 165, 170 }, city = true },
  },
  provinces = {   -- owner = "": nobody's; sea zones have no owner
    { id = 0, name = "Weneth", owner = "order" },
    { id = 1, name = "Halzanlor", owner = "might" },
    { id = 2, name = "Corul", owner = "death" },
    { id = 3, name = "Ornor", owner = "life" },
    { id = 4, name = "Ostgor", owner = "city_ostgor" },
    { id = 5, name = "Dalar", owner = "chaos" },
    { id = 6, name = "Lorpelmir", owner = "might" },
    { id = 7, name = "Dalyr", owner = "nature" },
    { id = 8, name = "Pelon", owner = "order" },
    { id = 9, name = "Dunnorost", owner = "city_dunnorost" },
    { id = 10, name = "Ispel", owner = "life" },
    { id = 11, name = "Ostval", owner = "order" },
    { id = 12, name = "Corkarar", owner = "nature" },
    { id = 13, name = "Belpel", owner = "city_belpel" },
    { id = 14, name = "Ornor", owner = "chaos" },
    { id = 15, name = "Ultormir", owner = "might" },
    { id = 16, name = "Ranpel", owner = "might" },
    { id = 17, name = "Enmir", owner = "chaos" },
    { id = 18, name = "Ardun", owner = "order" },
    { id = 19, name = "Orostgal", owner = "nature" },
    { id = 20, name = "Arost", owner = "nature" },
    { id = 21, name = "Orbel", owner = "death" },
    { id = 22, name = "Ortoror", owner = "chaos" },
    { id = 23, name = "Tormir", owner = "order" },
    { id = 24, name = "Orul", owner = "might" },
    { id = 25, name = "Ostgalcor", owner = "order" },
    { id = 26, name = "Ethhal", owner = "nature" },
    { id = 27, name = "Ordun", owner = "might" },
    { id = 28, name = "Yrorul", owner = "life" },
    { id = 29, name = "Dunsil", owner = "life" },
    { id = 30, name = "Belnor", owner = "might" },
    { id = 31, name = "Yrbelbel", owner = "order" },
    { id = 32, name = "Pelethgal", owner = "life" },
    { id = 33, name = "Dungalnor", owner = "chaos" },
    { id = 34, name = "Oriabel", owner = "nature" },
    { id = 35, name = "Onis", owner = "nature" },
    { id = 36, name = "Marpel", owner = "order" },
    { id = 37, name = "Halyr", owner = "life" },
    { id = 38, name = "Yrzanmir", owner = "might" },
    { id = 39, name = "Wenon", owner = "chaos" },
    { id = 40, name = "Ranfal", owner = "death" },
    { id = 41, name = "Mirnor", owner = "life" },
    { id = 42, name = "Arnor Sea" },
    { id = 43, name = "Valnor Sea" },
    { id = 44, name = "Ethbelost Sea" },
    { id = 45, name = "Ialor Sea" },
    { id = 46, name = "Ostcor Sea" },
    { id = 47, name = "Gornorfal Sea" },
    { id = 48, name = "Dalcor Sea" },
    { id = 49, name = "Ulmar Sea" },
    { id = 50, name = "Nordunar Sea" },
    { id = 51, name = "Ulis Sea" },
    { id = 52, name = "Karmir Sea" },
    { id = 53, name = "Pelmar Sea" },
    { id = 54, name = "Isvalor Sea" },
    { id = 55, name = "Valzantor Sea" },
    { id = 56, name = "Iawen Sea" },
    { id = 57, name = "Mirlorhal Sea" },
    { id = 58, name = "Halulgal Sea" },
    { id = 59, name = "Dunmir Sea" },
    { id = 60, name = "Falmir Sea" },
    { id = 61, name = "Falen Sea" },
    { id = 62, name = "Argal Sea" },
    { id = 63, name = "Zantorfal Sea" },
    { id = 64, name = "Belval Sea" },
    { id = 65, name = "Onul Sea" },
    { id = 66, name = "Dunnordun Sea" },
    { id = 67, name = "Arnorval Sea" },
    { id = 68, name = "Norsilpel Sea" },
    { id = 69, name = "Falen Sea" },
    { id = 70, name = "Markar Sea" },
    { id = 71, name = "Belonnor Sea" },
    { id = 72, name = "Dunenhal Sea" },
    { id = 73, name = "Dungalar Sea" },
    { id = 74, name = "Enmir Sea" },
    { id = 75, name = "Lorcor Sea" },
    { id = 76, name = "Karisran Sea" },
    { id = 77, name = "Falnor Sea" },
    { id = 78, name = "Marlor Sea" },
  },
  counties = {
    { id = 1, name = "Iagor" },   -- Weneth
    { id = 2, name = "Torenwen" },   -- Weneth
    { id = 3, name = "Corpelwen" },   -- Weneth
    { id = 4, name = "Orval" },   -- Weneth
    { id = 5, name = "Lorran" },   -- Weneth
    { id = 6, name = "Iaval" },   -- Weneth
    { id = 7, name = "Onordal" },   -- Weneth
    { id = 8, name = "Iayr" },   -- Weneth
    { id = 9, name = "Dalor" },   -- Halzanlor
    { id = 10, name = "Ranval" },   -- Halzanlor
    { id = 11, name = "Karhalen" },   -- Halzanlor
    { id = 12, name = "Dunbeldun" },   -- Halzanlor
    { id = 13, name = "Haliawen" },   -- Corul
    { id = 14, name = "Dungor" },   -- Corul
    { id = 15, name = "Corgal" },   -- Corul
    { id = 16, name = "Arpelkar" },   -- Corul
    { id = 17, name = "Ostfal" },   -- Ornor
    { id = 18, name = "Ethpel" },   -- Ornor
    { id = 19, name = "Ostethlor" },   -- Ornor
    { id = 20, name = "Ranlordal" },   -- Ornor
    { id = 21, name = "Silnor" },   -- Ornor
    { id = 22, name = "Dunyrmir" },   -- Ornor
    { id = 23, name = "Kardalcor" },   -- Ostgor
    { id = 24, name = "Gorzan" },   -- Ostgor
    { id = 25, name = "Dunmar" },   -- Ostgor
    { id = 26, name = "Karhalgal" },   -- Dalar
    { id = 27, name = "Lorulmir" },   -- Dalar
    { id = 28, name = "Silbelran" },   -- Dalar
    { id = 29, name = "Wenuleth" },   -- Dalar
    { id = 30, name = "Weniaran" },   -- Lorpelmir
    { id = 31, name = "Wenmir" },   -- Lorpelmir
    { id = 32, name = "Arar" },   -- Lorpelmir
    { id = 33, name = "Onor" },   -- Lorpelmir
    { id = 34, name = "Silfal" },   -- Lorpelmir
    { id = 35, name = "Ostfaltor" },   -- Lorpelmir
    { id = 36, name = "Cormiren" },   -- Dalyr
    { id = 37, name = "Oncorgor" },   -- Dalyr
    { id = 38, name = "Valuldal" },   -- Dalyr
    { id = 39, name = "Marmireth" },   -- Dalyr
    { id = 40, name = "Iaen" },   -- Dalyr
    { id = 41, name = "Iswenfal" },   -- Dalyr
    { id = 42, name = "Gorsilor" },   -- Pelon
    { id = 43, name = "Karia" },   -- Pelon
    { id = 44, name = "Onnor" },   -- Pelon
    { id = 45, name = "Valhalyr" },   -- Pelon
    { id = 46, name = "Marwenen" },   -- Pelon
    { id = 47, name = "Pelvalyr" },   -- Pelon
    { id = 48, name = "Pelval" },   -- Dunnorost
    { id = 49, name = "Silnoris" },   -- Dunnorost
    { id = 50, name = "Dunnoron" },   -- Dunnorost
    { id = 51, name = "Miror" },   -- Ispel
    { id = 52, name = "Onenul" },   -- Ispel
    { id = 53, name = "Tormir" },   -- Ispel
    { id = 54, name = "Torwenar" },   -- Ispel
    { id = 55, name = "Norar" },   -- Ispel
    { id = 56, name = "Ranmarfal" },   -- Ispel
    { id = 57, name = "Falval" },   -- Ostval
    { id = 58, name = "Orbel" },   -- Ostval
    { id = 59, name = "Yrnor" },   -- Ostval
    { id = 60, name = "Noren" },   -- Ostval
    { id = 61, name = "Pelhaltor" },   -- Ostval
    { id = 62, name = "Ulgor" },   -- Corkarar
    { id = 63, name = "Ostmir" },   -- Corkarar
    { id = 64, name = "Enostkar" },   -- Corkarar
    { id = 65, name = "Karmargor" },   -- Corkarar
    { id = 66, name = "Dunyr" },   -- Corkarar
    { id = 67, name = "Halfal" },   -- Corkarar
    { id = 68, name = "Normar" },   -- Corkarar
    { id = 69, name = "Loreth" },   -- Corkarar
    { id = 70, name = "Norpel" },   -- Corkarar
    { id = 71, name = "Rania" },   -- Belpel
    { id = 72, name = "Ranyreth" },   -- Belpel
    { id = 73, name = "Norcor" },   -- Ornor
    { id = 74, name = "Orgor" },   -- Ornor
    { id = 75, name = "Zandunon" },   -- Ornor
    { id = 76, name = "Halgorcor" },   -- Ornor
    { id = 77, name = "Ethen" },   -- Ornor
    { id = 78, name = "Cormargal" },   -- Ornor
    { id = 79, name = "Ethcorwen" },   -- Ornor
    { id = 80, name = "Isul" },   -- Ultormir
    { id = 81, name = "Beldalsil" },   -- Ultormir
    { id = 82, name = "Arzangor" },   -- Ultormir
    { id = 83, name = "Marmiror" },   -- Ultormir
    { id = 84, name = "Falulmar" },   -- Ultormir
    { id = 85, name = "Coren" },   -- Ranpel
    { id = 86, name = "Aren" },   -- Ranpel
    { id = 87, name = "Enon" },   -- Ranpel
    { id = 88, name = "Silgorbel" },   -- Ranpel
    { id = 89, name = "Corkar" },   -- Ranpel
    { id = 90, name = "Halgaldal" },   -- Ranpel
    { id = 91, name = "Miren" },   -- Enmir
    { id = 92, name = "Gorkartor" },   -- Enmir
    { id = 93, name = "Arnor" },   -- Enmir
    { id = 94, name = "Ostis" },   -- Enmir
    { id = 95, name = "Belran" },   -- Enmir
    { id = 96, name = "Ethensil" },   -- Enmir
    { id = 97, name = "Falnor" },   -- Enmir
    { id = 98, name = "Yrranhal" },   -- Enmir
    { id = 99, name = "Halzanran" },   -- Enmir
    { id = 100, name = "Mirmargal" },   -- Enmir
    { id = 101, name = "Dunyr" },   -- Ardun
    { id = 102, name = "Dunbel" },   -- Ardun
    { id = 103, name = "Yryrhal" },   -- Ardun
    { id = 104, name = "Duntorwen" },   -- Ardun
    { id = 105, name = "Valpel" },   -- Ardun
    { id = 106, name = "Onnornor" },   -- Ardun
    { id = 107, name = "Halzan" },   -- Orostgal
    { id = 108, name = "Ranis" },   -- Orostgal
    { id = 109, name = "Lorcorpel" },   -- Orostgal
    { id = 110, name = "Maryr" },   -- Orostgal
    { id = 111, name = "Gormir" },   -- Orostgal
    { id = 112, name = "Loren" },   -- Orostgal
    { id = 113, name = "Galtorkar" },   -- Orostgal
    { id = 114, name = "Norar" },   -- Arost
    { id = 115, name = "Zanorost" },   -- Arost
    { id = 116, name = "Arorpel" },   -- Arost
    { id = 117, name = "Valdun" },   -- Arost
    { id = 118, name = "Iaar" },   -- Arost
    { id = 119, name = "Torvalen" },   -- Arost
    { id = 120, name = "Pelostlor" },   -- Orbel
    { id = 121, name = "Lormirbel" },   -- Orbel
    { id = 122, name = "Belul" },   -- Orbel
    { id = 123, name = "Artor" },   -- Orbel
    { id = 124, name = "Ethcor" },   -- Orbel
    { id = 125, name = "Yria" },   -- Ortoror
    { id = 126, name = "Orzangor" },   -- Ortoror
    { id = 127, name = "Norul" },   -- Ortoror
    { id = 128, name = "Pelmir" },   -- Ortoror
    { id = 129, name = "Arran" },   -- Tormir
    { id = 130, name = "Ostia" },   -- Tormir
    { id = 131, name = "Normirkar" },   -- Tormir
    { id = 132, name = "Pelyr" },   -- Tormir
    { id = 133, name = "Ethnor" },   -- Tormir
    { id = 134, name = "Noriaia" },   -- Tormir
    { id = 135, name = "Iafal" },   -- Tormir
    { id = 136, name = "Ialor" },   -- Orul
    { id = 137, name = "Belmiryr" },   -- Orul
    { id = 138, name = "Faliaeth" },   -- Orul
    { id = 139, name = "Karorhal" },   -- Orul
    { id = 140, name = "Armarost" },   -- Orul
    { id = 141, name = "Dalloror" },   -- Orul
    { id = 142, name = "Isenfal" },   -- Ostgalcor
    { id = 143, name = "Mirbeleth" },   -- Ostgalcor
    { id = 144, name = "Ethmarmar" },   -- Ostgalcor
    { id = 145, name = "Ethenmir" },   -- Ostgalcor
    { id = 146, name = "Gordal" },   -- Ostgalcor
    { id = 147, name = "Valnormar" },   -- Ostgalcor
    { id = 148, name = "Isfalmir" },   -- Ostgalcor
    { id = 149, name = "Belkardal" },   -- Ostgalcor
    { id = 150, name = "Ostartor" },   -- Ostgalcor
    { id = 151, name = "Belwen" },   -- Ethhal
    { id = 152, name = "Orvaldal" },   -- Ethhal
    { id = 153, name = "Valen" },   -- Ethhal
    { id = 154, name = "Valfal" },   -- Ethhal
    { id = 155, name = "Marlor" },   -- Ethhal
    { id = 156, name = "Zanul" },   -- Ethhal
    { id = 157, name = "Dalnor" },   -- Ethhal
    { id = 158, name = "Norhalbel" },   -- Ordun
    { id = 159, name = "Iasil" },   -- Ordun
    { id = 160, name = "Onval" },   -- Ordun
    { id = 161, name = "Corzanis" },   -- Ordun
    { id = 162, name = "Mirular" },   -- Ordun
    { id = 163, name = "Falyr" },   -- Yrorul
    { id = 164, name = "Lorgor" },   -- Yrorul
    { id = 165, name = "Gordungal" },   -- Yrorul
    { id = 166, name = "Pelengor" },   -- Yrorul
    { id = 167, name = "Dalon" },   -- Yrorul
    { id = 168, name = "Falyrlor" },   -- Yrorul
    { id = 169, name = "Ostistor" },   -- Yrorul
    { id = 170, name = "Marmarar" },   -- Dunsil
    { id = 171, name = "Belzan" },   -- Dunsil
    { id = 172, name = "Ortor" },   -- Dunsil
    { id = 173, name = "Orwenia" },   -- Dunsil
    { id = 174, name = "Zanfal" },   -- Belnor
    { id = 175, name = "Gordun" },   -- Belnor
    { id = 176, name = "Dallor" },   -- Belnor
    { id = 177, name = "Onwen" },   -- Belnor
    { id = 178, name = "Yrgor" },   -- Belnor
    { id = 179, name = "Ostia" },   -- Yrbelbel
    { id = 180, name = "Belwen" },   -- Yrbelbel
    { id = 181, name = "Cormirdun" },   -- Yrbelbel
    { id = 182, name = "Miria" },   -- Yrbelbel
    { id = 183, name = "Silfalbel" },   -- Yrbelbel
    { id = 184, name = "Gorar" },   -- Pelethgal
    { id = 185, name = "Dundalval" },   -- Pelethgal
    { id = 186, name = "Yrfalgal" },   -- Pelethgal
    { id = 187, name = "Kariaeth" },   -- Pelethgal
    { id = 188, name = "Valcor" },   -- Pelethgal
    { id = 189, name = "Noriadun" },   -- Pelethgal
    { id = 190, name = "Mirostcor" },   -- Dungalnor
    { id = 191, name = "Isgoria" },   -- Dungalnor
    { id = 192, name = "Yrvalval" },   -- Dungalnor
    { id = 193, name = "Orfal" },   -- Dungalnor
    { id = 194, name = "Zanis" },   -- Dungalnor
    { id = 195, name = "Gorgor" },   -- Dungalnor
    { id = 196, name = "Lorlorgor" },   -- Dungalnor
    { id = 197, name = "Yryrran" },   -- Oriabel
    { id = 198, name = "Silissil" },   -- Oriabel
    { id = 199, name = "Halnor" },   -- Oriabel
    { id = 200, name = "Torulis" },   -- Oriabel
    { id = 201, name = "Dunost" },   -- Oriabel
    { id = 202, name = "Halfal" },   -- Onis
    { id = 203, name = "Wenonzan" },   -- Onis
    { id = 204, name = "Yrgorhal" },   -- Onis
    { id = 205, name = "Ostul" },   -- Onis
    { id = 206, name = "Wenyr" },   -- Onis
    { id = 207, name = "Margor" },   -- Onis
    { id = 208, name = "Wengaldal" },   -- Onis
    { id = 209, name = "Karkargal" },   -- Marpel
    { id = 210, name = "Ranwenyr" },   -- Marpel
    { id = 211, name = "Isranyr" },   -- Marpel
    { id = 212, name = "Gordun" },   -- Marpel
    { id = 213, name = "Dunlor" },   -- Marpel
    { id = 214, name = "Falaryr" },   -- Marpel
    { id = 215, name = "Goria" },   -- Halyr
    { id = 216, name = "Dunwen" },   -- Halyr
    { id = 217, name = "Valis" },   -- Halyr
    { id = 218, name = "Falpelor" },   -- Halyr
    { id = 219, name = "Dalost" },   -- Yrzanmir
    { id = 220, name = "Enmir" },   -- Yrzanmir
    { id = 221, name = "Bellorpel" },   -- Yrzanmir
    { id = 222, name = "Galar" },   -- Yrzanmir
    { id = 223, name = "Ulmir" },   -- Yrzanmir
    { id = 224, name = "Halpel" },   -- Yrzanmir
    { id = 225, name = "Lorostval" },   -- Yrzanmir
    { id = 226, name = "Isdunul" },   -- Wenon
    { id = 227, name = "Halfal" },   -- Wenon
    { id = 228, name = "Dalia" },   -- Wenon
    { id = 229, name = "Coria" },   -- Wenon
    { id = 230, name = "Dunonyr" },   -- Ranfal
    { id = 231, name = "Lororar" },   -- Ranfal
    { id = 232, name = "Karsil" },   -- Ranfal
    { id = 233, name = "Halwenul" },   -- Ranfal
    { id = 234, name = "Ostsileth" },   -- Ranfal
    { id = 235, name = "Pelmar" },   -- Ranfal
    { id = 236, name = "Iszanor" },   -- Mirnor
    { id = 237, name = "Zanyrzan" },   -- Mirnor
    { id = 238, name = "Zantorar" },   -- Mirnor
    { id = 239, name = "Norbel" },   -- Mirnor
    { id = 240, name = "Zandun" },   -- Mirnor
    { id = 241, name = "Ethvalran" },   -- Mirnor
  },
}
