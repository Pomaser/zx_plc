"""The scenario and the commentary of the YouTube tour (tools/mkyoutube.py).

SCENARIO: the commands of tools/mkvideo.py (k: t: wN go: cl: go!: cl!: shot:
hold:) plus say:ID / ws / ch:Title / tape: / seek: / rec / sd / ur: / mouse:.
Everything runs at normal speed (x:1). Mouse coordinates are screen pixels.
NARRATION: id -> (English, spoken and the EN subtitles; Czech subtitles).
PRONOUNCE: (regex, replacement) for the TTS only; the subtitles keep the text.
"""

PRONOUNCE = [
    (r"\bZX-PLC\b", "Zed X P L C"),
    (r"\bZX\b", "Zed X"),
    (r"\bIEC 61131-3\b", "I E C sixty-one one thirty-one, part three"),
    (r"%?\b([IQM])X?(\d)\.(\d)\b", r"\1 \2 point \3"),
    (r"%?\bSW(\d)\b", r"S W \1"),
    (r"\bPOUs\b", "P O Use"),
    (r"\bPOU\b", "P O U"),
    (r"\bFBD\b", "F B D"),
    (r"\bLD\b", "L D"),
    (r"\bIL\b", "I L"),
    (r"\bAY\b", "A Y"),
    (r"\bUR-4\b", "U R four"),
    (r"\bTON(\d)\b", r"T O N \1"),
    (r"\bCTU(\d)\b", r"C T U \1"),
    (r"\bTON\b", "T O N"),
    (r"\bCTU\b", "C T U"),
    (r"\bCAL\b", "call"),
    (r"\bANDN\b", "and-not"),
    (r"\bST\b", "store"),
    (r"\bPLC\b", "P L C"),
    (r"\bPLCs\b", "P L Cs"),
    (r"\bdivMMC\b", "div M M C"),
    (r"\besxDOS\b", "E S X DOS"),
    (r"\bSD\b", "S D"),
    (r"\bET\b", "E T"),
    (r"\bCV\b", "C V"),
    (r"\bPT\b", "P T"),
    (r"\bPV\b", "P V"),
    (r"\bZX0\b", "Zed X zero"),
    (r"\bGitHub\b", "Git Hub"),
    (r"\b128K\b", "one twenty-eight K"),
    (r"\bBREAK\b", "break"),
    (r"\bEDIT\b", "edit"),
    (r"\b8255\b", "eighty-two fifty-five"),
    (r"\bSYMBOL SHIFT\b", "symbol shift"),
    (r"\bkB\b", "kilobytes"),
]

# ElevenLabs reads most abbreviations well; only these are spelled out for it
PRONOUNCE_EL = [
    (r"\bZX-PLC\b", "Z X P L C"),
    (r"\bZX\b", "Z X"),
    (r"\bIEC 61131-3\b", "I E C sixty-one one thirty-one, part three"),
    (r"%?\b([IQM])X?(\d)\.(\d)\b", r"\1 \2 point \3"),
    (r"%?\bSW(\d)\b", r"S W \1"),
    (r"\bPOUs\b", "P O Us"),
    (r"\bPOU\b", "P O U"),
    (r"\bIL\b", "I L"),
    (r"\bLD\b", "L D"),
    (r"\bFBD\b", "F B D"),
    (r"\bTON(\d)\b", r"T O N \1"),
    (r"\bCTU(\d)\b", r"C T U \1"),
    (r"\bCAL\b", "call"),
    (r"\bUR-4\b", "U R four"),
    (r"\b8255\b", "eighty-two fifty-five"),
]

NARRATION = {
    # ---- Intro
    "intro1": (
        "This is ZX-PLC: a PLC editor and simulator for the ZX Spectrum 128K. "
        "It is loading from tape right now, on a real 128K in an emulator.",
        "Tohle je ZX-PLC: editor a simulátor PLC pro ZX Spectrum 128K. "
        "Právě se nahrává z pásky, na skutečné 128K v emulátoru."),
    "intro2": (
        "The program is written in Z80 assembler. Its blocks are packed with ZX0, "
        "so the whole tape takes under four minutes.",
        "Program je napsaný v assembleru Z80. Bloky jsou zabalené pomocí ZX0, "
        "takže celá páska trvá necelé čtyři minuty."),
    "intro3": (
        "When everything is loaded, the PLC in the picture switches from STOP to RUN.",
        "Když je všechno nahrané, PLC na obrázku se přepne ze STOP do RUN."),
    "intro4": (
        "In this video we build a small machine control from scratch, in all three "
        "languages of the IEC 61131-3 standard the program supports: ladder diagram, "
        "function block diagram and instruction list. Then we run it in the simulator. "
        "Let's press a key.",
        "V tomto videu od nuly postavíme malé řízení stroje, ve všech třech jazycích "
        "normy IEC 61131-3, které program umí: v žebříčku, ve funkčních blocích a v "
        "seznamu instrukcí. Pak ho spustíme v simulátoru. Stiskneme klávesu."),
    # ---- The screen
    "scr1": (
        "The program starts with a demo project. This is the POU list: the program "
        "organisation units of the project, with their language, size and comment.",
        "Program startuje s ukázkovým projektem. Tohle je seznam POU: programových "
        "organizačních jednotek projektu, s jazykem, velikostí a komentářem."),
    "scr2": (
        "At the top is the menu bar, with the name of the current POU on the right. "
        "At the bottom is the status bar. Here it shows the free project memory.",
        "Nahoře je lišta menu, vpravo s názvem aktuální POU. Dole je stavový řádek, "
        "tady ukazuje volnou paměť projektu."),
    "scr3": (
        "Everything works from the keyboard: BREAK or EDIT opens the menu, and every "
        "menu item has its hotkey. But a Kempston mouse makes it even easier, so let's "
        "switch it on in the Setup menu.",
        "Všechno jde ovládat klávesnicí: BREAK nebo EDIT otevře menu a každá položka "
        "má svou zkratku. S myší Kempston je to ale ještě snazší, tak ji zapneme v "
        "menu Setup."),
    "scr4": (
        "Now a small arrow follows the mouse. A click on a menu title opens it, and a "
        "click on an item runs it.",
        "Teď myš sleduje malá šipka. Kliknutím na titulek se menu otevře, kliknutím "
        "na položku se provede."),
    # ---- LD
    "ld1": (
        "Our machine is a conveyor with a motor, a running lamp, a cooling fan and a "
        "part counter. We start with an empty project: File, New project.",
        "Naším strojem je dopravník s motorem, kontrolkou chodu, chladicím ventilátorem "
        "a počítadlem dílů. Začneme prázdným projektem: File, New project."),
    "ld2": (
        "A new project has only MAIN, the program the PLC runs in every scan. "
        "We add a new POU called LAMP, in ladder diagram.",
        "Nový projekt má jen MAIN, program, který PLC provede v každém cyklu. "
        "Přidáme novou POU jménem LAMP, v žebříčkovém diagramu."),
    "ld3": (
        "Every POU has a short comment. Then the ladder editor opens.",
        "Každá POU má krátký komentář. Pak se otevře editor žebříčku."),
    "ld4": (
        "The rung is drawn from the left power rail to the right. A click on a cell "
        "opens the element picker. The first element is a normally open contact.",
        "Příčka se kreslí od levé napájecí sběrnice doprava. Kliknutí na buňku otevře "
        "výběr prvků. Prvním prvkem je spínací kontakt."),
    "ld5": (
        "Its operand is the motor output, Q0.0. Operands can be typed in this short "
        "form; the editor stores them in the IEC form.",
        "Jeho operandem je výstup motoru Q0.0. Operandy jde psát v této krátké formě, "
        "editor je uloží v podobě podle IEC."),
    "ld6": (
        "Next comes an on-delay timer, TON0, with a preset time of two seconds.",
        "Dál přijde časovač se zpožděným zapnutím, TON0, s předvolbou dvě sekundy."),
    "ld7": (
        "And at the right end a coil: the running lamp, Q0.1. So the lamp lights up "
        "two seconds after the motor starts.",
        "A na pravém konci cívka: kontrolka chodu Q0.1. Kontrolka se tedy rozsvítí "
        "dvě sekundy po rozběhu motoru."),
    # ---- FBD
    "fbd1": (
        "The second POU, FAN, is in function block diagram.",
        "Druhá POU, FAN, je ve funkčních blocích."),
    "fbd2": (
        "Here the signals flow through blocks from left to right. The input of the "
        "first network is again the motor, Q0.0.",
        "Tady signály tečou bloky zleva doprava. Vstupem první sítě je opět motor Q0.0."),
    "fbd3": (
        "It feeds a timer block, TON2, with three seconds. Its output switches the "
        "cooling fan, Q0.2.",
        "Ten vede do bloku časovače TON2 se třemi sekundami. Jeho výstup spíná "
        "chladicí ventilátor Q0.2."),
    "fbd4": (
        "The second network counts the parts. The part sensor, input I0.2, goes into "
        "the count-up input of the counter CTU1, with a preset of three.",
        "Druhá síť počítá díly. Čidlo dílu, vstup I0.2, vede do čítacího vstupu "
        "čítače CTU1 s předvolbou tři."),
    "fbd5": (
        "The stop button, I0.1, resets it. When three parts have passed, output Q0.5 "
        "goes on.",
        "Tlačítko stop, I0.1, ho nuluje. Když projdou tři díly, zapne se výstup Q0.5."),
    # ---- IL
    "il1": (
        "Now MAIN, in instruction list: a text language, one instruction per line, "
        "with a single accumulator.",
        "Teď MAIN v seznamu instrukcí: textový jazyk, jedna instrukce na řádek, "
        "s jediným akumulátorem."),
    "il2": (
        "First a comment, then the classic motor latch: load the start button, OR the "
        "motor itself, AND NOT the stop button, and store the result to the motor.",
        "Nejdřív komentář, pak klasická samodržná vazba motoru: načti tlačítko start, "
        "OR samotný motor, AND NOT tlačítko stop a výsledek ulož do motoru."),
    "il3": (
        "A known instruction is turned to upper case as soon as you press SPACE, and "
        "every line is checked when you press ENTER.",
        "Známá instrukce se převede na velká písmena hned po stisku mezery a každý "
        "řádek se zkontroluje při stisku ENTER."),
    "il4": (
        "Timers and counters are called with CAL and named parameters, just like in "
        "the standard. This one lights a service lamp after five seconds of running.",
        "Časovače a čítače se volají přes CAL s pojmenovanými parametry, přesně jako "
        "v normě. Tenhle rozsvítí servisní kontrolku po pěti sekundách chodu."),
    "il5": (
        "A counter counts the starts of the motor, and after three starts it sets Q0.4.",
        "Čítač počítá starty motoru a po třech startech nastaví Q0.4."),
    "il6": (
        "Finally MAIN calls the other two POUs, LAMP and FAN.",
        "Nakonec MAIN zavolá další dvě POU, LAMP a FAN."),
    "il7": (
        "What if we make a mistake? An input that does not exist, I9.9, is refused "
        "at once, with a message.",
        "Co když se spleteme? Vstup, který neexistuje, I9.9, je hned odmítnut "
        "se zprávou."),
    "il8": (
        "Some errors only show up when the whole project is compiled. Here a jump goes "
        "to a label that does not exist.",
        "Některé chyby se ukážou až při překladu celého projektu. Tady skok vede na "
        "návěští, které neexistuje."),
    "il9": (
        "Run compiles all POUs. The compiler stops, opens the editor at the faulty line "
        "and shows the error in the status bar. We delete the line.",
        "Run přeloží všechny POU. Překladač se zastaví, otevře editor na chybném "
        "řádku a chybu ukáže ve stavovém řádku. Řádek smažeme."),
    # ---- Symbols
    "sym1": (
        "Addresses like I0.0 are hard to remember, so let's give them names. "
        "Edit, Symbols opens the symbol table.",
        "Adresy jako I0.0 se špatně pamatují, tak jim dáme jména. "
        "Edit, Symbols otevře tabulku symbolů."),
    "sym2": (
        "Each row has a name, an address and a comment. Start button, stop button, "
        "part sensor, then the outputs.",
        "Každý řádek má jméno, adresu a komentář. Tlačítko start, tlačítko stop, "
        "čidlo dílu, potom výstupy."),
    "sym3": (
        "Back in MAIN, View, Symbols shows the program with the names instead of the "
        "addresses. The status bar shows the symbol and the comment of the operand at "
        "the cursor.",
        "Zpátky v MAIN ukáže View, Symbols program se jmény místo adres. Stavový "
        "řádek ukazuje symbol a komentář operandu pod kurzorem."),
    "sym4": (
        "Cross references find every use of an operand. Where is the motor used? "
        "In MAIN, where it is read and written, and in LAMP and FAN.",
        "Křížové reference najdou každé použití operandu. Kde všude je motor? "
        "V MAIN, kde se čte i zapisuje, a v LAMP a FAN."),
    "sym5": (
        "ENTER on an entry jumps straight to that place, here into the ladder of LAMP.",
        "ENTER na položce skočí přímo na to místo, tady do žebříčku LAMP."),
    # ---- Editing
    "ed1": (
        "The editors share the usual tools. SYMBOL SHIFT and A marks the start of a "
        "block, and the cursor selects the lines.",
        "Editory mají společné běžné nástroje. SYMBOL SHIFT a A označí začátek bloku "
        "a kurzor vybere řádky."),
    "ed2": (
        "SYMBOL SHIFT and D copies the block, SYMBOL SHIFT and F pastes it in front of "
        "the cursor.",
        "SYMBOL SHIFT a D blok zkopíruje, SYMBOL SHIFT a F ho vloží před kurzor."),
    "ed3": (
        "And every change can be undone with SYMBOL SHIFT and U, step by step, and "
        "redone with SYMBOL SHIFT and Y. The history keeps hundreds of steps, in a "
        "separate memory bank.",
        "Každou změnu jde vrátit pomocí SYMBOL SHIFT a U, krok za krokem, a znovu "
        "provést pomocí SYMBOL SHIFT a Y. Historie drží stovky kroků v samostatné "
        "paměťové bance."),
    # ---- Simulation
    "sim1": (
        "Time to run it. Run, Run compiles the project and starts the scan cycle: "
        "one scan every frame, fifty times a second.",
        "Čas to spustit. Run, Run přeloží projekt a spustí cyklus: jeden průchod "
        "programem každý snímek, padesátkrát za sekundu."),
    "sim2": (
        "The bottom panel shows the sixteen inputs in green and the sixteen outputs in "
        "red. A click on an input LED toggles it, so we press the start button.",
        "Spodní panel ukazuje šestnáct vstupů zeleně a šestnáct výstupů červeně. "
        "Kliknutí na LED vstupu ho přepne, tak stiskneme tlačítko start."),
    "sim3": (
        "The motor latches on. Each IL line shows the value of its operand: TRUE is "
        "green. The timer counts its elapsed time, and after five seconds the service "
        "lamp comes on.",
        "Motor se přidrží. Každý řádek IL ukazuje hodnotu svého operandu: TRUE je "
        "zeleně. Časovač počítá uplynulý čas a po pěti sekundách se rozsvítí servisní "
        "kontrolka."),
    "sim4": (
        "Two more presses of the start button: the counter of starts reaches three "
        "and sets its output. Then the stop button.",
        "Ještě dvakrát tlačítko start: čítač startů dojde na tři a nastaví svůj "
        "výstup. Pak tlačítko stop."),
    "sim5": (
        "The simulation shows the POU that is open in the editor. In LAMP, the ladder "
        "shows the power flow: active contacts, boxes and coils are green.",
        "Simulace ukazuje POU, která je otevřená v editoru. V LAMP ukazuje žebříček "
        "tok energie: aktivní kontakty, bloky a cívky jsou zelené."),
    "sim6": (
        "And in FAN, the function blocks: the names of TRUE signals and the insides of "
        "active blocks turn green. The fan starts three seconds after the motor.",
        "A ve FAN funkční bloky: jména signálů v TRUE a vnitřky aktivních bloků "
        "zezelenají. Ventilátor naběhne tři sekundy po motoru."),
    "sim7": (
        "Three clicks on the part sensor, and the counter output goes on.",
        "Tři kliknutí na čidlo dílu a výstup čítače se zapne."),
    # ---- Watch
    "w1": (
        "W switches to the watch page. Here we can list any operands and see their "
        "live values: the motor, the elapsed time of the fan timer, the parts counter, "
        "the stop button.",
        "W přepne na stránku sledování. Tady můžeme vypsat libovolné operandy a vidět "
        "jejich živé hodnoty: motor, uplynulý čas časovače ventilátoru, počítadlo "
        "dílů, tlačítko stop."),
    "w2": (
        "And the scan time words: the last, the longest and the shortest scan cycle.",
        "A slova doby cyklu: poslední, nejdelší a nejkratší cyklus."),
    "w3": (
        "F forces the selected operand. Forcing the stop button to TRUE stops the "
        "motor and resets the counter, whatever the program does.",
        "F vynutí vybraný operand. Vynucení tlačítka stop na TRUE zastaví motor a "
        "vynuluje čítač, ať program dělá cokoli."),
    "w4": (
        "F again forces it to FALSE, and once more releases it.",
        "Další F ho vynutí na FALSE a ještě jednou ho uvolní."),
    # ---- Trend
    "tr1": (
        "T shows the trend page: the watched signals drawn as time charts, like a "
        "logic analyzer. Let's start the motor and watch.",
        "T ukáže stránku trendu: sledované signály nakreslené jako časové průběhy, "
        "jako v logickém analyzátoru. Spustíme motor a díváme se."),
    "tr2": (
        "The motor goes high. The elapsed time of the fan timer ramps up to its preset, "
        "and three parts step the counter up.",
        "Motor přejde do jedničky. Uplynulý čas časovače ventilátoru stoupá k "
        "předvolbě a tři díly krokují čítač nahoru."),
    "tr3": (
        "The stop button ends it all. The chart keeps sampling even when another page "
        "is shown.",
        "Tlačítko stop všechno ukončí. Graf vzorkuje dál, i když je zobrazená jiná "
        "stránka."),
    # ---- UR-4
    "ur1": (
        "The simulation can also drive real hardware. The UR-4 is a Czechoslovak "
        "interface with an 8255 chip and three eight bit ports.",
        "Simulace umí ovládat i skutečný hardware. UR-4 je československé rozhraní "
        "s obvodem 8255 a třemi osmibitovými porty."),
    "ur2": (
        "Setup, UR-4 I/O switches it on. Ports A and B become the inputs, and port C "
        "the outputs.",
        "Setup, UR-4 I/O ho zapne. Porty A a B se stanou vstupy a port C výstupy."),
    "ur3": (
        "A real switch on port A now starts the motor, and the motor output appears "
        "on port C. The status bar says UR-4 RUN.",
        "Skutečný spínač na portu A teď spustí motor a výstup motoru se objeví na "
        "portu C. Stavový řádek ukazuje UR-4 RUN."),
    # ---- Saving
    "sv1": (
        "Our project is finished, so let's save it. File, Save tape asks for a name, "
        "and writes a standard CODE file, which any tape tool can copy.",
        "Projekt je hotový, tak ho uložíme. File, Save tape se zeptá na jméno a "
        "zapíše standardní soubor CODE, který zkopíruje jakýkoli páskový nástroj."),
    "sv2": (
        "This is how it sounds.",
        "Takhle to zní."),
    "sv2b": (
        "The project is small, so saving takes about twenty seconds. Loading works "
        "the same way: File, Load tape waits for a project and skips other files. "
        "If loading fails, the old project comes back.",
        "Projekt je malý, takže ukládání trvá asi dvacet sekund. Nahrávání funguje "
        "stejně: File, Load tape čeká na projekt a jiné soubory přeskočí. Když se "
        "nahrávání nepovede, vrátí se původní projekt."),
    "sv3": (
        "With a divMMC interface and esxDOS, the project goes to an SD card instead. "
        "Save SD writes the file TOUR.PLC.",
        "S rozhraním divMMC a systémem esxDOS jde projekt místo toho na SD kartu. "
        "Save SD zapíše soubor TOUR.PLC."),
    "sv4": (
        "To prove it, we clear the project, and load it back: Load SD lists the PLC "
        "files on the card.",
        "Abychom to dokázali, projekt smažeme a načteme ho zpět: Load SD vypíše "
        "soubory PLC na kartě."),
    "sv5": (
        "And our three POUs are back.",
        "A naše tři POU jsou zpátky."),
    # ---- Help
    "hp1": (
        "Help, Controls lists the keys, in case you forget one.",
        "Help, Controls vypíše klávesy, kdybyste nějakou zapomněli."),
    "hp2": (
        "ZX-PLC is free and open source. The tape, the snapshot and the source code "
        "are on GitHub, and there is a browser version, so you can try it without a "
        "Spectrum. The links are in the description.",
        "ZX-PLC je zdarma a s otevřeným zdrojovým kódem. Páska, snapshot i zdrojový "
        "kód jsou na GitHubu a existuje i verze pro prohlížeč, takže si to můžete "
        "vyzkoušet i bez Spectra. Odkazy jsou v popisu."),
    "hp3": (
        "Thanks for watching!",
        "Díky za pozornost!"),
}

SCENARIO = [
    # ================================================================ Intro
    "ch:Intro mouse:0",
    "w150 k:ENTER w20 tape:zxplc.tap seek:1200 rec",
    "say:intro1 w100 say:intro2 ws w100",
    "w300 say:intro3 ws w150",
    "say:intro4 ws k:SPACE w100",
    # ================================================================ The screen
    "ch:The~screen~and~the~mouse mouse:1",
    "say:scr1 w50 shot:scr1 ws",
    "say:scr2 ws",
    "say:scr3 w150 k:CS+1 w30 k:H w20 k:S w40 shot:scr3 k:M w60 ws",
    "say:scr4 go:120,100 w50 go!:36,3 cl!:L w60 go:200,150 w15 cl:L w30 ws",
    # ================================================================ LD
    "ch:Ladder~diagram",
    "say:ld1 w100 go!:8,3 cl!:L w30 go!:30,12 cl!:L w40",
    "go:85,100 w20 cl:L w40",
    "go:140,92 w20 cl:L w60 shot:new ws",
    "say:ld2 w100 go!:36,3 cl!:L w30 go!:40,20 cl!:L w30",
    "t:LAMP w15 k:ENTER w30",
    "go!:140,100 cl!:L w30 ws",
    "say:ld3 t:running~lamp w15 k:ENTER w60 ws",
    "say:ld4 w60 go:20,36 w15 cl:L w20 cl:L w60",
    "go:20,36 w15 cl:L w30",
    "go!:130,52 cl!:L w30 ws",
    "say:ld5 t:Q0.0 w10 k:ENTER w40 ws",
    "say:ld6 go:44,36 w15 cl:L w30 go!:130,100 cl!:L w30",
    "t:TON0 w10 k:ENTER w40",
    "k:CS+0 k:CS+0 t:2s w10 k:ENTER w40 ws",
    "say:ld7 go:236,36 w15 cl:L w30 cl:L w30",
    "go!:130,76 cl!:L w30 t:Q0.1 w10 k:ENTER w60 shot:ld go:200,150 ws",
    # ================================================================ FBD
    "ch:Function~block~diagram",
    "say:fbd1 go!:36,3 cl!:L w30 go!:40,20 cl!:L w30",
    "t:FAN w15 k:ENTER w30 go!:140,108 cl!:L w30",
    "t:cooling~fan w15 k:ENTER w60 ws",
    "say:fbd2 go:20,44 w15 cl:L w20 cl:L w60",
    "go:20,36 w15 cl:L w30",
    "go!:110,20 cl!:L w30 t:Q0.0 w10 k:ENTER w40 ws",
    "say:fbd3 go:44,36 w15 cl:L w30 go!:110,108 cl!:L w40",
    "t:TON2 w10 k:ENTER w40 k:CS+0 k:CS+0 t:3s w10 k:ENTER w40",
    "go:68,36 w15 cl:L w30 go!:110,164 cl!:L w30 t:Q0.2 w10 k:ENTER w50 shot:fbd1 ws",
    "say:fbd4 go:20,68 w15 cl:L w30 cl:L w30 go!:110,20 cl!:L w30 t:I0.2 w10 k:ENTER w40",
    "go:44,68 w15 cl:L w30 go!:110,132 cl!:L w40 t:CTU1 w10 k:ENTER w40",
    "k:CS+0 k:CS+0 t:3 w10 k:ENTER w50 ws",
    "say:fbd5 go:20,84 w15 cl:L w30 cl:L w30 go!:110,28 cl!:L w30 t:I0.1 w10 k:ENTER w40",
    "go:68,68 w15 cl:L w30 cl:L w30 go!:110,164 cl!:L w30 t:Q0.5 w10 k:ENTER w60 shot:fbd go:200,150 ws",
    # ================================================================ IL
    "ch:Instruction~list",
    "say:il1 go!:36,3 cl!:L w30 go!:40,12 cl!:L w60",
    "go:20,28 w15 cl:L w30 cl:L w30 go:200,140 w30 ws",
    "say:il2 t://~Motor~start/stop w10 k:ENTER w20",
    "t:LD~I0.0 w10 k:ENTER w20",
    "t:OR~Q0.0 w10 k:ENTER w20",
    "t:ANDN~I0.1 w10 k:ENTER w20",
    "t:ST~Q0.0 w10 k:ENTER w40 ws",
    "say:il3 w40 ws",
    "say:il4 t://~Service~lamp~after~5~s w10 k:ENTER w20",
    "t:CAL~TON1(IN:=Q0.0,~PT:=T#5s) w10 k:ENTER w20",
    "t:LD~TON1.Q w10 k:ENTER w20",
    "t:ST~Q0.3 w10 k:ENTER w20 ws",
    "say:il5 t://~Count~the~starts w10 k:ENTER w20",
    "t:CAL~CTU0(CU:=I0.0,~R:=I0.1,~PV:=3) w10 k:ENTER w20",
    "t:LD~CTU0.Q w10 k:ENTER w20",
    "t:ST~Q0.4 w10 k:ENTER w20 ws",
    "say:il6 t:CAL~LAMP w10 k:ENTER w20",
    "t:CAL~FAN w10 k:ENTER w60 shot:il ws",
    "say:il7 t:LD~I9.9 w10 k:ENTER w80 shot:il_err1 ws",
    "k:ENTER w20 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 w10 shot:il_clr",
    "say:il8 t:JMP~SKIP w10 k:ENTER w60 ws",
    "say:il9 w20 go!:103,3 cl!:L w30 go!:110,12 cl!:L w100 shot:il_err2",
    "w60 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 w10 k:CS+0 w60 shot:il_fixed ws",
    # ================================================================ Symbols
    "ch:Symbols~and~cross~references",
    "say:sym1 w60 go!:60,3 cl!:L w30 go!:70,44 cl!:L w30 go:200,150 w20 ws",
    "say:sym2 t:start k:SPACE t:I0.0 k:SPACE t:start~button k:ENTER w20",
    "t:stop k:SPACE t:I0.1 k:SPACE t:stop~button k:ENTER w20",
    "t:sensor k:SPACE t:I0.2 k:SPACE t:part~sensor k:ENTER w20",
    "t:motor k:SPACE t:Q0.0 k:SPACE t:conveyor~motor k:ENTER w20",
    "t:runLamp k:SPACE t:Q0.1 k:SPACE t:running~lamp k:ENTER w20",
    "t:fanOn k:SPACE t:Q0.2 k:SPACE t:cooling~fan k:ENTER w20",
    "t:service k:SPACE t:Q0.3 k:SPACE t:service~lamp k:ENTER w20",
    "t:starts3 k:SPACE t:Q0.4 k:SPACE t:3~starts~done k:ENTER w20",
    "t:parts3 k:SPACE t:Q0.5 k:SPACE t:3~parts~counted k:ENTER w60 shot:sym ws",
    "say:sym3 go!:60,3 cl!:L w30 go!:70,12 cl!:L w30 go:200,150 w60",
    "go!:80,3 cl!:L w30 go!:90,12 cl!:L w30 go:200,150 w20",
    "go:40,44 w15 cl:L w60 shot:vsym ws",
    "say:sym4 w40 k:SS+X w100 shot:xref ws",
    "say:sym5 k:CS+6 w20 k:CS+6 w20 k:CS+6 w30 k:ENTER w100 shot:xref_jump ws",
    # ================================================================ Editing
    "ch:Copy,~paste~and~undo",
    "go!:36,3 cl!:L w30 go!:40,12 cl!:L w60",
    "go:20,28 w15 cl:L w30 cl:L w60 go:200,150",
    "say:ed1 go:40,20 w15 cl:L w30 k:SS+A w30 k:CS+6 w15 k:CS+6 w15 k:CS+6 w40 shot:mark ws",
    "say:ed2 k:SS+D w60 go:40,132 w15 cl:L w30 k:SS+F w100 shot:paste go:200,150 ws",
    "say:ed3 w20 k:SS+U w60 shot:undo k:SS+Y w60 k:SS+U w60 ws",
    # ================================================================ Simulation
    "ch:Simulation",
    "say:sim1 go!:103,3 cl!:L w30 go!:110,12 cl!:L w100 ws",
    "say:sim2 w60 go:6,174 w30 ws",
    "cl:L w50 cl:L w60",
    "say:sim3 w100 shot:sim2 ws w100",
    "say:sim4 w20 cl:L w40 cl:L w60 cl:L w40 cl:L w60 shot:sim3 ws",
    "go:22,174 w20 cl:L w60 cl:L w60",
    "say:sim5 go!:36,3 cl!:L w30 go!:40,12 cl!:L w60",
    "go:20,36 w15 cl:L w30 cl:L w60",
    "go!:103,3 cl!:L w30 go!:110,12 cl!:L w100",
    "go:6,174 w20 cl:L w50 cl:L w60 ws w150",
    "say:sim6 go!:36,3 cl!:L w30 go!:40,12 cl!:L w60",
    "go:20,44 w15 cl:L w30 cl:L w60",
    "go!:103,3 cl!:L w30 go!:110,12 cl!:L w100",
    "go:6,174 w20 cl:L w50 cl:L w180 shot:f1 ws",
    "say:sim7 go:38,174 w20 cl:L w30 cl:L w40 cl:L w30 cl:L w40 cl:L w30 cl:L w60 shot:f2 ws",
    # ================================================================ Watch
    "ch:Watch~and~force",
    "say:w1 go:200,140 w20 k:W w60",
    "k:ENTER w30 t:motor w10 k:ENTER w40",
    "k:CS+6 w10 k:ENTER w30 t:TON2.ET w10 k:ENTER w40",
    "k:CS+6 w10 k:ENTER w30 t:CTU1.CV w10 k:ENTER w40",
    "k:CS+6 w10 k:ENTER w30 t:stop w10 k:ENTER w60 ws",
    "say:w2 k:CS+6 w10 k:ENTER w30 t:SW0 w10 k:ENTER w30",
    "k:CS+6 w10 k:ENTER w30 t:SW1 w10 k:ENTER w30",
    "k:CS+6 w10 k:ENTER w30 t:SW2 w10 k:ENTER w60 shot:w1 ws",
    "k:CS+7 w10 k:CS+7 w10 k:CS+7 w30",
    "say:w3 w60 k:F w100 shot:w2 ws",
    "say:w4 w30 k:F w80 k:F w80 shot:w3 ws",
    # ================================================================ Trend
    "ch:Trend",
    "say:tr1 k:T w60 ws",
    "go:6,174 w20 cl:L w20 cl:L w60",
    "say:tr2 w100 go:38,174 w20 cl:L w20 cl:L w40 cl:L w20 cl:L w40 cl:L w20 cl:L w60 ws",
    "say:tr3 go:22,174 w20 cl:L w20 cl:L w100 shot:trend ws",
    "k:G w60",
    # ================================================================ UR-4
    "ch:Real~I/O:~the~UR-4",
    "say:ur1 w60 ws",
    "say:ur2 go!:135,3 cl!:L w30 go!:145,28 cl!:L w60 go:200,140 shot:ur_on ws",
    "say:ur3 w30 ur:01,00 w30 ur:00,00 w100 shot:ur_run ws",
    "ur:02,00 w30 ur:00,00 w60",
    "go!:135,3 cl!:L w30 go!:145,28 cl!:L w60",
    # ================================================================ Saving
    "ch:Saving:~tape~and~SD~card",
    "go!:36,3 cl!:L w30 go!:40,12 cl!:L w60",
    "say:sv1 go!:8,3 cl!:L w30 go!:30,36 cl!:L w40 shot:tname w20 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 w10 t:TOUR w15 k:ENTER w40 shot:save ws",
    "say:sv2 k:ENTER w30 ws",
    "w100 say:sv2b ws w30 shot:saved k:ENTER w40",
    "sd",
    "say:sv3 go!:8,3 cl!:L w30 go!:30,52 cl!:L w40 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 w10 t:TOUR w15 k:ENTER w100 shot:sdsave ws",
    "k:ENTER w30 shot:sd1",
    "say:sv4 go!:8,3 cl!:L w30 go!:30,12 cl!:L w40 shot:sd2 go:85,100 w20 cl:L w40 go:140,92 w20 cl:L w60 shot:sd3",
    "go!:8,3 cl!:L w30 go!:30,44 cl!:L w40 go:85,100 w20 cl:L w100 shot:sdlist ws",
    "k:ENTER w100 shot:sd4",
    "say:sv5 go!:36,3 cl!:L w30 go!:40,12 cl!:L w60 shot:sdloaded ws",
    # ================================================================ Help
    "ch:Help~and~About",
    "say:hp1 go!:165,3 cl!:L w30 go!:168,12 cl!:L w60 shot:controls ws w60",
    "k:ENTER w30",
    "say:hp2 go!:165,3 cl!:L w30 go!:168,20 cl!:L w40 go:220,150 shot:about ws",
    "say:hp3 ws w150",
]
