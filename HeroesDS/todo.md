Fanowski projekt gry w Stylu heroes 4 na DS. 

Gra nie bedzie wiernym portem, ale bedzie korzystac z oryginalnych zasobów gry. 
(mam oryginał z GOG na dysku C ).Tylko dla mnie 

Gra bedzie miec 2 tryby, 
- 1 mapa kontynentu , prowincje , miasta , jednostki , miasta jak w grze Imperial Glory
- - 2 tryb to walka jak w heroes 4 , dolny ekran widok mapy walki , górny ekran animuje sprajty walki (musimy ladowac animacje 2 walczacych jednostek  w naprzeciwłelglych naroznikach ekranu , korzystajac z wiekszej rozdzieloczosci sprajtów jednostek wiec ds musi wczytac animowac i zwolnic pamiec )

Zebrałem kilka narzedzi do wyodrebnienia grafiki z plików gry, ale moze łatwiej bedzie nam samemu poszukac specyfikacji plików i napiszesz skrypt ktory wyekstachuje grafikie i pliki meta animacji sprajtów na potrzeby naszej konsoli LiteLua ?

![alt text](image.png) to program ale on eksportuje do formatu .ora
w drzewie katalogu widac strukture, animacje jednostek sa w "actor_sequence -> bandit -> i tu combat ma duze rozdzielczosci animacji a reszta to sprajty z mapy gdzie sa proste prezentacje 

zacznijmy od opracowania grafiki sprjtów z gry , jak je wyciagnac , uzyc w naszej konsoli i animowac , z podzialem na animacje 2 trybów gry (mapa taktyczna i walki ). ? 
równolegle musimy zaprojektowac system który bedzie umial nawet ze stubami grafiki na razie obsługiwac walke, uwzgedniajac , moce jednostek, statysyki , magie obszarowa , i reszte sattystyk gry. 
- pomoc : https://h4.heroes.net.pl/umiejetnosci/mocy i inne strony z tego adresu
-manual gry i internet abys mogl zrozumiec jakie sa zaleznosci sattystyk w walce  Ok ? wsztstko piszemy tutaj : D:\Programowanie\LuaDS\HeroesDS