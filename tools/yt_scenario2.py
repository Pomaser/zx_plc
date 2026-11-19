"""The second YouTube tour (tools/mkyoutube.py --scenario yt_scenario2):
faster than the first one (shorter gaps, typing in fast forward with a ">>"
mark, quicker mouse), with Structured Text, the command palette, name
completion and the values right behind the variables in the ST simulation.

The commands are those of yt_scenario.py (mkvideo + say:ID / ws / ch: /
tape: / seek: / rec / sd / ur: / mouse:); x:N fast forward.
"""

PAUSE = 8                           # frames after a cue before ws goes on
GLIDE_PX = 9                        # mouse glide speed
BADGE = True                        # ">>" in the top border while x:N > 1

PRONOUNCE = [
    (r"\bZX-PLC\b", "Zed X P L C"),
    (r"\bZX\b", "Zed X"),
    (r"\bIEC 61131-3\b", "I E C sixty-one one thirty-one, part three"),
    (r"%?\b([IQM])X?(\d)\.(\d)\b", r"\1 \2 point \3"),
    (r"%?\bMW(\d)\b", r"M W \1"),
    (r"%?\bSW(\d)\b", r"S W \1"),
    (r"\bPOUs\b", "P O Use"),
    (r"\bPOU\b", "P O U"),
    (r"\bFBD\b", "F B D"),
    (r"\bLD\b", "L D"),
    (r"\bIL\b", "I L"),
    (r"\bST\b", "S T"),
    (r"\bEND_IF\b", "end if"),
    (r"\bVAR\b", "var"),
    (r"\bAY\b", "A Y"),
    (r"\bUR-4\b", "U R four"),
    (r"\bTON(\d)\b", r"T O N \1"),
    (r"\bCTU(\d)\b", r"C T U \1"),
    (r"\bCAL\b", "call"),
    (r"\bPLC\b", "P L C"),
    (r"\bdivMMC\b", "div M M C"),
    (r"\besxDOS\b", "E S X DOS"),
    (r"\bSD\b", "S D"),
    (r"\bGitHub\b", "Git Hub"),
    (r"\b128K\b", "one twenty-eight K"),
    (r"\bBREAK\b", "break"),
    (r"\bEDIT\b", "edit"),
    (r"\bSYMBOL SHIFT\b", "symbol shift"),
    (r"\bVS Code\b", "V S Code"),
    (r"\bTwinCAT\b", "twin cat"),
]

PRONOUNCE_EL = [
    (r"\bZX-PLC\b", "Z X P L C"),
    (r"\bZX\b", "Z X"),
    (r"\bIEC 61131-3\b", "I E C sixty-one one thirty-one, part three"),
    (r"%?\b([IQM])X?(\d)\.(\d)\b", r"\1 \2 point \3"),
    (r"%?\bMW(\d)\b", r"M W \1"),
    (r"%?\bSW(\d)\b", r"S W \1"),
    (r"\bPOUs\b", "P O Us"),
    (r"\bPOU\b", "P O U"),
    (r"\bIL\b", "I L"),
    (r"\bLD\b", "L D"),
    (r"\bFBD\b", "F B D"),
    (r"\bST\b", "S T"),
    (r"\bEND_IF\b", "end if"),
    (r"\bTON(\d)\b", r"T O N \1"),
    (r"\bCTU(\d)\b", r"C T U \1"),
    (r"\bCAL\b", "call"),
    (r"\bUR-4\b", "U R four"),
    (r"\bVS Code\b", "V S Code"),
    (r"\bTwinCAT\b", "Twin CAT"),
]

# Czech speech (--lang cs): letters, abbreviations and the English menu words as
# a Czech speaker says them; the subtitles keep the text. Longer patterns first.
PRONOUNCE_CS = [
    (r"\bZX-PLC\b", "zet iks pé el cé"),
    (r"\bZX\b", "zet iks"),
    (r"\bIEC 61131-3\b", "í é cé šedesát jedna sto třicet jedna, část tři"),
    (r"%?\bI(\d)\.(\d)\b", r"í \1 tečka \2"),
    (r"%?\bQ(\d)\.(\d)\b", r"kvé \1 tečka \2"),
    (r"%?\bM(\d)\.(\d)\b", r"em \1 tečka \2"),
    (r"\bSYMBOL SHIFT a E\b", "symbol šift a é"),
    (r"\bSYMBOL SHIFT\b", "symbol šift"),
    (r"\bControl E\b", "kontrol é"),
    (r"\bjazyk S\b", "jazyk es"),
    (r"\bI jako INT\b", "í jako int"),
    (r"\bW otevře\b", "dvojité vé otevře"),
    (r"\bF jeden\b", "ef jeden"),
    (r"\bT je nakreslí\b", "té je nakreslí"),
    (r"\bport C\b", "port cé"),
    (r"\bPOU\b", "pé ó ú"),
    (r"\bPLC\b", "pé el cé"),
    (r"\bFBD\b", "ef bé dé"),
    (r"\bLD\b", "el dé"),
    (r"\bIL\b", "í el"),
    (r"\bST\b", "es té"),
    (r"\bTON(\d)\b", r"té ó en \1"),
    (r"\bUR-4\b", "u er čtyři"),
    (r"\bZ80\b", "zet osmdesát"),
    (r"\b128K\b", "sto dvacet osm ká"),
    (r"\bSD\b", "es dé"),
    (r"\bdivMMC\b", "div em em cé"),
    (r"\besxDOS\b", "é es iks dos"),
    (r"\bVS Code\b", "vé es kód"),
    (r"\bTwinCATu\b", "tvinketu"),
    (r"\bGitHubu\b", "gitchabu"),
    (r"\bLED\b", "ledky"),
    (r"\bEND_IF\b", "end if"),
    (r"\bENTER\b", "enter"),
    (r"\bVAR\b", "var"),
    (r"\binline\b", "inlajn"),
    (r"\bTHEN\b", "den"),
    (r"\bELSE\b", "els"),
    (r"\bINT\b", "int"),
    (r"\bOptions\b", "opšns"),
    (r"\bMouse\b", "maus"),
    (r"\bView\b", "vjů"),
    (r"\bSymbols\b", "simbls"),
    (r"\bAddresses\b", "edresis"),
    (r"\bAbout\b", "ebaut"),
    (r"\bRun\b", "ran"),
    (r"\bMAIN\b", "mejn"),
    (r"\bLAMP\b", "lemp"),
    (r"\bFAN\b", "fen"),
    (r"\bRAMP\b", "remp"),
    (r"\bmanage\b", "menidž"),
    (r"\bspeed\b", "spíd"),
    (r"\bmotor\b", "motor"),
]

CHAPTERS_CS = {
    "Intro": "Úvod",
    "Screen, mouse and command palette": "Obrazovka, myš a paleta příkazů",
    "Ladder diagram": "Žebříčkový diagram",
    "Function block diagram": "Funkční bloky",
    "Instruction list": "Seznam instrukcí",
    "Symbols": "Symboly",
    "Structured Text": "Strukturovaný text",
    "Copy, paste and undo": "Kopírování, vložení a undo",
    "Simulation": "Simulace",
    "Watch, force and trend": "Sledování, vynucení a trend",
    "Hardware and storage": "Hardware a ukládání",
    "Help and About": "Nápověda a About",
}

NARRATION = {
    # ---- Intro
    "intro1": (
        "This is ZX-PLC, a PLC editor and simulator for the ZX Spectrum 128K, "
        "loading from tape.",
        "Tohle je ZX-PLC, editor a simulátor PLC pro ZX Spectrum 128K, "
        "který se právě nahrává z pásky."),
    "intro2": (
        "It speaks all four languages of IEC 61131-3: ladder diagram, function blocks, "
        "instruction list, and now Structured Text. Let's build a small machine with it.",
        "Umí všechny čtyři jazyky normy IEC 61131-3: žebříček, funkční bloky, seznam "
        "instrukcí a nově strukturovaný text. Postavíme s ním malý stroj."),
    "intro3": (
        "It is written in Z80 assembler and uses all the paged memory of the 128K: "
        "editors, compilers, a virtual machine and the tools sit in different banks.",
        "Je napsaný v assembleru Z80 a využívá celou stránkovanou paměť 128K: editory, "
        "překladače, virtuální stroj i nástroje sedí v různých bankách."),
    # ---- Screen, mouse, palette
    "scr1": (
        "The demo project opens in the POU list. The menu is at the top, the status "
        "bar at the bottom.",
        "Ukázkový projekt se otevře v seznamu POU. Nahoře je menu, dole stavový řádek."),
    "scr2": (
        "Everything works from the keyboard, but a Kempston mouse is faster. "
        "Options, Mouse.",
        "Všechno jde z klávesnice, ale s myší Kempston je to rychlejší. "
        "Options, Mouse."),
    "pal1": (
        "And here is something you know from VS Code: the command palette. "
        "SYMBOL SHIFT and E, or Control E in the browser, lists every POU and every "
        "command. Type a few letters, and ENTER.",
        "A tady je něco, co znáte z VS Code: paleta příkazů. SYMBOL SHIFT a E, "
        "v prohlížeči Control E, vypíše všechny POU a všechny příkazy. Napíšete pár "
        "písmen a ENTER."),
    "pal2": (
        "That opened the demo in Structured Text. One more: manage, back to the list.",
        "Tím se otevřelo demo ve strukturovaném textu. Ještě jednou: manage, zpět "
        "na seznam."),
    # ---- LD
    "ld1": (
        "Our machine: a conveyor with a motor, a running lamp, a cooling fan and a "
        "part counter. New project, and a first POU in ladder diagram: LAMP.",
        "Náš stroj: dopravník s motorem, kontrolkou chodu, ventilátorem a počítadlem "
        "dílů. Nový projekt a první POU v žebříčku: LAMP."),
    "ld2": (
        "A click on a cell opens the element picker. A contact for the motor, Q0.0.",
        "Kliknutí na buňku otevře výběr prvků. Kontakt pro motor, Q0.0."),
    "ld3": (
        "An on-delay timer, TON0, two seconds, and a coil for the running lamp, Q0.1.",
        "Časovač se zpožděním, TON0, dvě sekundy, a cívka kontrolky chodu, Q0.1."),
    "ld4": (
        "So the lamp lights up two seconds after the motor starts.",
        "Kontrolka se tedy rozsvítí dvě sekundy po rozběhu motoru."),
    # ---- FBD
    "fbd1": (
        "The next POU, FAN, in function block diagram: the motor feeds a timer, three "
        "seconds, and the timer switches the fan.",
        "Další POU, FAN, ve funkčních blocích: motor vede do časovače, tři sekundy, "
        "a časovač spíná ventilátor."),
    "fbd2": (
        "A second network counts parts: the sensor drives a counter, the stop button "
        "resets it, and after three parts output Q0.5 goes on.",
        "Druhá síť počítá díly: čidlo pohání čítač, tlačítko stop ho nuluje a po "
        "třech dílech se zapne výstup Q0.5."),
    # ---- IL
    "il1": (
        "MAIN is in instruction list. Let's speed up the typing: the motor latch, a "
        "service timer, a counter of starts, and the calls of LAMP and FAN.",
        "MAIN je v seznamu instrukcí. Psaní zrychlíme: samodržná vazba motoru, servisní "
        "časovač, čítač startů a volání LAMP a FAN."),
    "il2": (
        "Instructions turn upper case on SPACE, and every line is checked on ENTER. "
        "An input that does not exist is refused at once.",
        "Instrukce se po mezeře převedou na velká písmena a každý řádek se kontroluje "
        "při ENTER. Vstup, který neexistuje, je odmítnut hned."),
    "il3": (
        "Errors that need the whole project, like a wrong jump, show up when it is "
        "compiled. We will see one in Structured Text in a moment.",
        "Chyby, které potřebují celý projekt, třeba špatný skok, se ukážou při překladu. "
        "Jednu za chvíli uvidíme ve strukturovaném textu."),
    # ---- Symbols
    "sym1": (
        "Addresses are hard to remember, so we name them in the symbol table.",
        "Adresy se špatně pamatují, tak jim dáme jména v tabulce symbolů."),
    "sym2": (
        "View, Symbols shows the names everywhere, and the status bar shows the "
        "comment of the operand at the cursor.",
        "View, Symbols ukáže jména všude a stavový řádek ukazuje komentář operandu "
        "pod kurzorem."),
    "sym3": (
        "Cross references find every use of the motor, and ENTER jumps right there.",
        "Křížové reference najdou každé použití motoru a ENTER tam rovnou skočí."),
    # ---- ST
    "st1": (
        "Now the new language: Structured Text. The palette again: new POU, RAMP, "
        "language S. It will ramp the speed of the motor up.",
        "Teď nový jazyk: strukturovaný text. Zase paleta příkazů: nová POU, RAMP, jazyk S. "
        "Bude rozjíždět rychlost motoru."),
    "st2": (
        "The ST editor helps a lot. A keyword turns blue and upper case as you type. "
        "SYMBOL SHIFT and SPACE completes a name, here motor, from the symbols.",
        "Editor ST hodně pomáhá. Klíčové slovo se při psaní obarví modře a převede na "
        "velká písmena. SYMBOL SHIFT a mezera doplní jméno, tady motor, ze symbolů."),
    "st3": (
        "And ENTER completes the whole IF: THEN, an empty line and END_IF, all "
        "aligned, the cursor ready inside.",
        "A ENTER doplní celé IF: THEN, prázdný řádek a END_IF, vše zarovnané, kurzor "
        "připravený uvnitř."),
    "st4": (
        "speed is a new name. ENTER asks how to declare it: I for INT. A VAR block is "
        "made at the top, and folds into one line, so it takes no room.",
        "speed je nové jméno. ENTER se zeptá, jak ho deklarovat: I jako INT. Nahoře "
        "vznikne blok VAR a sbalí se do jednoho řádku, takže nezabírá místo."),
    "st4b": (
        "Local variables keep their values from scan to scan, and the block opens "
        "again as soon as the cursor moves into it.",
        "Lokální proměnné si drží hodnotu z cyklu na cyklus a blok se znovu rozbalí, "
        "jakmile do něj vjede kurzor."),
    "st5": (
        "An ELSE branch, and a limit at one hundred: again, IF is completed for us.",
        "Větev ELSE a omezení na sto: IF se zase doplní samo."),
    "st6": (
        "Here a semicolon is missing. Run, from the palette: the compiler opens the "
        "line, and the status bar says what is wrong.",
        "Tady chybí středník. Run z palety příkazů: překladač otevře řádek a stavový řádek "
        "řekne, co je špatně."),
    "st7": (
        "Fixed. View, Addresses shows the same code with the addresses, View, Symbols "
        "with the names. And MAIN gets a call of RAMP.",
        "Opraveno. View, Addresses ukáže stejný kód s adresami, View, Symbols se jmény. "
        "A MAIN dostane volání RAMP."),
    # ---- Editing
    "ed1": (
        "The editors share mark, copy and paste, and every change can be undone and "
        "redone, step by step.",
        "Editory mají společné označení, kopírování a vložení a každou změnu jde vrátit "
        "a znovu provést, krok za krokem."),
    # ---- Simulation
    "sim1": (
        "Run. The program runs fifty scans a second. Green LEDs are the inputs, red "
        "the outputs. A click on the start button.",
        "Run. Program běží padesát cyklů za sekundu. Zelené LED jsou vstupy, červené "
        "výstupy. Klik na tlačítko start."),
    "sim2": (
        "The motor latches on, the IL lines show their values, and the timers count.",
        "Motor se přidrží, řádky IL ukazují své hodnoty a časovače počítají."),
    "sim3": (
        "Ladder shows the power flow in green, and function blocks light up their "
        "active signals.",
        "Žebříček ukazuje tok energie zeleně a funkční bloky rozsvítí aktivní signály."),
    "sim4": (
        "And ST, the new way: every variable shows its live value right behind its "
        "name, like the inline monitoring of TwinCAT. Watch speed ramp up to one hundred.",
        "A ST nově: každá proměnná ukazuje živou hodnotu hned za svým jménem, jako "
        "inline monitoring v TwinCATu. Sledujte, jak speed stoupá ke stovce."),
    "sim5": (
        "Stop, and speed drops back to zero.",
        "Stop a speed spadne zpět na nulu."),
    # ---- Watch, force, trend
    "w1": (
        "W opens the watch list: any operands with their live values. F forces one, "
        "here the stop button, whatever the program does.",
        "W otevře seznam sledování: libovolné operandy s živými hodnotami. F jeden "
        "vynutí, tady tlačítko stop, ať program dělá cokoli."),
    "w2": (
        "T draws them as time charts, like a logic analyzer.",
        "T je nakreslí jako časové průběhy, jako logický analyzátor."),
    # ---- Hardware and storage
    "hw1": (
        "Real hardware: with a UR-4 interface, real switches drive the inputs, and the "
        "outputs go to its port C.",
        "Skutečný hardware: s rozhraním UR-4 ovládají vstupy skutečné spínače a výstupy "
        "jdou na jeho port C."),
    "hw2": (
        "Projects are saved to tape as standard files. This is how it sounds.",
        "Projekty se ukládají na pásku jako standardní soubory. Takhle to zní."),
    "hw3": (
        "Or, with a divMMC and esxDOS, to an SD card, and back from a list of files.",
        "Nebo, s divMMC a esxDOS, na SD kartu, a zpět ze seznamu souborů."),
    # ---- Help
    "hp1": (
        "Help lists all the keys. ZX-PLC is free and open source: the tape, the source "
        "and a browser version are on GitHub. The links are in the description.",
        "Nápověda vypíše všechny klávesy. ZX-PLC je zdarma a s otevřeným kódem: páska, "
        "zdrojáky i verze pro prohlížeč jsou na GitHubu. Odkazy jsou v popisu."),
    "hp1b": (
        "And About has a text scroller in the border, an old demo scene trick.",
        "A okénko About má v rámečku rolující text, starý trik z demoscény."),
    "hp2": (
        "Thanks for watching!",
        "Díky za pozornost!"),
}

T3 = "x:3 "                          # typing in fast forward
T1 = "x:1 "

SCENARIO = [
    # ================================================================ Intro
    "ch:Intro mouse:0",
    "w150 k:ENTER w20 tape:zxplc.tap seek:700 rec",
    "say:intro1 w100 ws",
    "say:intro3 ws",
    "say:intro2 ws k:SPACE w60",
    # ================================================================ Screen, mouse, palette
    "ch:Screen,~mouse~and~command~palette mouse:1",
    "say:scr1 w40 ws",
    "say:scr2 k:CS+1 w20 k:H w15 k:O w30 shot:scr k:M w40 go:120,100 w10 ws",
    "say:pal1 w40 k:SS+E w40 shot:pal t:de w15 t:m w15 k:CS+6 w10 k:CS+6 w10 k:CS+6 w30 k:ENTER w60 ws",
    "say:pal2 w20 k:SS+E w30 t:man w20 k:ENTER w50 ws",
    # ================================================================ LD
    "ch:Ladder~diagram",
    "say:ld1 go!:8,3 cl!:L w20 go!:30,12 cl!:L w30 go:85,100 w10 cl:L w30",
    "go:140,92 w10 cl:L w40 go!:36,3 cl!:L w20 go!:40,20 cl!:L w20",
    "t:LAMP w10 k:ENTER w20 go!:140,100 cl!:L w20 t:running~lamp w10 k:ENTER w50 ws",
    "say:ld2 go:20,36 w10 cl:L w15 cl:L w40 go:20,36 w10 cl:L w20",
    "go!:130,52 cl!:L w20 t:Q0.0 w10 k:ENTER w30 ws",
    "say:ld3 go:44,36 w10 cl:L w20 go!:130,100 cl!:L w20",
    "t:TON0 w10 k:ENTER w30 k:CS+0 k:CS+0 t:2s w10 k:ENTER w30",
    "go:236,36 w10 cl:L w20 cl:L w20",
    "go!:130,76 cl!:L w20 t:Q0.1 w10 k:ENTER w40 shot:ld go:200,150 ws",
    "say:ld4 ws",
    # ================================================================ FBD
    "ch:Function~block~diagram",
    "say:fbd1 go!:36,3 cl!:L w20 go!:40,20 cl!:L w20",
    "t:FAN w10 k:ENTER w20 go!:140,108 cl!:L w20",
    "t:cooling~fan w10 k:ENTER w50",
    "go:20,44 w10 cl:L w15 cl:L w40 go:20,36 w10 cl:L w20",
    "go!:110,20 cl!:L w20 t:Q0.0 w10 k:ENTER w30",
    "go:44,36 w10 cl:L w20 go!:110,108 cl!:L w30",
    "t:TON2 w10 k:ENTER w30 k:CS+0 k:CS+0 t:3s w10 k:ENTER w30",
    "go:68,36 w10 cl:L w20 go!:110,164 cl!:L w20 t:Q0.2 w10 k:ENTER w40 shot:fbd1 ws",
    "say:fbd2 go:20,68 w10 cl:L w20 cl:L w20 go!:110,20 cl!:L w20 t:I0.2 w10 k:ENTER w30",
    "go:44,68 w10 cl:L w20 go!:110,132 cl!:L w30 t:CTU1 w10 k:ENTER w30",
    "k:CS+0 k:CS+0 t:3 w10 k:ENTER w40",
    "go:20,84 w10 cl:L w20 cl:L w20 go!:110,28 cl!:L w20 t:I0.1 w10 k:ENTER w30",
    "go:68,68 w10 cl:L w20 cl:L w20 go!:110,164 cl!:L w20 t:Q0.5 w10 k:ENTER w40 shot:fbd go:200,150 ws",
    # ================================================================ IL
    "ch:Instruction~list",
    "say:il1 go!:36,3 cl!:L w20 go!:40,12 cl!:L w40",
    "go:20,28 w10 cl:L w20 cl:L w30 go:200,140 " + T3 +
    "t://~Motor~start/stop w6 k:ENTER w10 "
    "t:LD~I0.0 w6 k:ENTER w10 t:OR~Q0.0 w6 k:ENTER w10 "
    "t:ANDN~I0.1 w6 k:ENTER w10 t:ST~Q0.0 w6 k:ENTER w10 "
    "t://~Service~lamp~after~5~s w6 k:ENTER w10 "
    "t:CAL~TON1(IN:=Q0.0,~PT:=T#5s) w6 k:ENTER w10 "
    "t:LD~TON1.Q w6 k:ENTER w10 t:ST~Q0.3 w6 k:ENTER w10 "
    "t://~Count~the~starts w6 k:ENTER w10 "
    "t:CAL~CTU0(CU:=I0.0,~R:=I0.1,~PV:=3) w6 k:ENTER w10 "
    "t:LD~CTU0.Q w6 k:ENTER w10 t:ST~Q0.4 w6 k:ENTER w10 "
    "t:CAL~LAMP w6 k:ENTER w10 t:CAL~FAN w6 k:ENTER w10 " + T1 + "shot:il ws",
    "say:il2 w20 t:LD~I9.9 w10 k:ENTER w60 shot:il_err",
    "k:ENTER w15 " + T3 + "k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 w10 k:CS+0 w10 " + T1 + "ws",
    "say:il3 ws",
    # ================================================================ Symbols
    "ch:Symbols",
    "say:sym1 go!:60,3 cl!:L w20 go!:70,44 cl!:L w30 go:200,150 " + T3 +
    "t:start k:SPACE t:I0.0 k:SPACE t:start~button k:ENTER w10 "
    "t:stop k:SPACE t:I0.1 k:SPACE t:stop~button k:ENTER w10 "
    "t:sensor k:SPACE t:I0.2 k:SPACE t:part~sensor k:ENTER w10 "
    "t:motor k:SPACE t:Q0.0 k:SPACE t:conveyor~motor k:ENTER w10 "
    "t:runLamp k:SPACE t:Q0.1 k:SPACE t:running~lamp k:ENTER w10 "
    "t:fanOn k:SPACE t:Q0.2 k:SPACE t:cooling~fan k:ENTER w10 "
    "t:service k:SPACE t:Q0.3 k:SPACE t:service~lamp k:ENTER w10 "
    "t:starts3 k:SPACE t:Q0.4 k:SPACE t:3~starts~done k:ENTER w10 "
    "t:parts3 k:SPACE t:Q0.5 k:SPACE t:3~parts~counted k:ENTER w10 " + T1 + "shot:sym ws",
    "say:sym2 go!:60,3 cl!:L w20 go!:70,12 cl!:L w30 go:200,150 w40",
    "go!:80,3 cl!:L w20 go!:90,12 cl!:L w20 go:200,150 w10",
    "go:40,44 w10 cl:L w50 shot:vsym ws",
    "say:sym3 w20 k:SS+X w80 shot:xref k:CS+6 w15 k:CS+6 w15 k:CS+6 w20 k:ENTER w80 ws",
    # ================================================================ ST
    "ch:Structured~Text",
    "say:st1 w20 k:SS+E w30 t:new w20 k:CS+6 w15 k:ENTER w40",
    "t:RAMP w10 k:ENTER w30 k:S w30 t:speed~ramp w10 k:ENTER w40 k:ENTER w60 shot:st_new ws",
    "say:st2 w20 " + T3 + "t:if~ " + T1 + "w30 " + T3 + "t:mo " + T1 + "w20 k:SS+SPACE w50 shot:st_compl ws",
    "say:st3 k:ENTER w60 shot:st_if ws",
    "say:st4 " + T3 + "t:speed~:=~speed~+~1; " + T1 + "k:ENTER w60 shot:st_decl k:I w80 shot:st_var ws",
    "say:st4b ws",
    "say:st5 " + T3 + "t:else " + T1 + "k:ENTER w40 " + T3 + "t:speed~:=~0; " + T1 +
    "k:CS+6 w15 k:SS+ENTER w30 " + T3 + "t:if~speed~>~100 " + T1 + "k:ENTER w50 " +
    T3 + "t:speed~:=~100; " + T1 + "k:CS+6 w15 k:SS+ENTER w30 shot:st_more ws",
    "say:st6 " + T3 + "t:%MW0~:=~speed " + T1 + "w20 k:SS+E w30 t:run w20 k:ENTER w150 shot:st_err ws",
    "say:st7 k:SS+CS+8 w10 t:; w20 k:CS+7 w20 k:SS+CS+7 w20 k:SS+CS+7 w30",
    "go!:80,3 cl!:L w20 go!:90,20 cl!:L w60 shot:st_addr go!:80,3 cl!:L w20 go!:90,12 cl!:L w60",
    "go:200,150 k:SS+E w30 t:main w20 k:ENTER w60 " + T3 +
    "k:SS+CS+6 w10 k:SS+CS+6 w10 k:SS+ENTER w20 t:CAL~RAMP w6 k:ENTER w20 " + T1 + "shot:st_main ws",
    # ================================================================ Editing
    "ch:Copy,~paste~and~undo",
    "say:ed1 go:40,20 w10 cl:L w20 k:SS+A w20 k:CS+6 w10 k:CS+6 w10 k:CS+6 w30",
    "k:SS+D w40 go:40,132 w10 cl:L w20 k:SS+F w60 shot:paste go:200,150 k:SS+U w50 k:SS+Y w50 k:SS+U w50 ws",
    # ================================================================ Simulation
    "ch:Simulation",
    "say:sim1 k:SS+E w30 t:run w20 k:ENTER w80 go:6,174 w20 cl:L w40 cl:L w40 ws",
    "say:sim2 w80 shot:sim_il ws",
    "say:sim3 k:SS+E w30 t:lamp w20 k:ENTER w30 k:SS+E w30 t:run w20 k:ENTER w120",
    "k:SS+E w30 t:fan w20 k:ENTER w30 k:SS+E w30 t:run w20 k:ENTER w120 shot:sim_fbd ws",
    "say:sim4 k:SS+E w30 t:ramp w20 k:ENTER w30 k:SS+E w30 t:run w20 k:ENTER w60",
    "go:6,174 w15 cl:L w20 cl:L w100 shot:sim_st ws",
    "say:sim5 go:22,174 w15 cl:L w20 cl:L w80 shot:sim_st0 ws",
    # ================================================================ Watch, force, trend
    "ch:Watch,~force~and~trend",
    "say:w1 go:200,140 w10 k:W w50 " + T3 +
    "k:ENTER w10 t:motor w6 k:ENTER w20 k:CS+6 w6 k:ENTER w10 t:TON2.ET w6 k:ENTER w20 "
    "k:CS+6 w6 k:ENTER w10 t:CTU1.CV w6 k:ENTER w20 k:CS+6 w6 k:ENTER w10 t:stop w6 k:ENTER w30 " + T1 +
    "go:6,174 w15 cl:L w20 cl:L w40 k:F w80 shot:watch k:F w40 k:F w40 ws",
    "say:w2 k:T w40 go:6,174 w15 cl:L w20 cl:L w60 go:38,174 w15 cl:L w20 cl:L w30 cl:L w20 cl:L w30",
    "go:22,174 w15 cl:L w20 cl:L w60 shot:trend ws k:G w40",
    # ================================================================ Hardware and storage
    "ch:Hardware~and~storage",
    "say:hw1 go!:135,3 cl!:L w20 go!:145,28 cl!:L w40 go:200,140 ur:01,00 w30 ur:00,00 w60 shot:ur",
    "ur:02,00 w30 ur:00,00 w30 go!:135,3 cl!:L w20 go!:145,28 cl!:L w40 ws",
    "go!:36,3 cl!:L w20 go!:40,12 cl!:L w40",
    "say:hw2 go!:8,3 cl!:L w20 go!:30,36 cl!:L w30 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 w10 t:TOUR w10 k:ENTER w30 k:ENTER w30 ws",
    "w150 x:12 w1200 x:1 w20 shot:saved k:ENTER w30",
    "sd",
    "say:hw3 go!:8,3 cl!:L w20 go!:30,52 cl!:L w30 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 k:CS+0 w10 t:TOUR w10 k:ENTER w80 k:ENTER w20",
    "go!:8,3 cl!:L w20 go!:30,44 cl!:L w30 go:85,100 w10 cl:L w80 shot:sdlist k:ENTER w80 ws",
    # ================================================================ Help
    "ch:Help~and~About",
    "say:hp1 go!:165,3 cl!:L w30 go!:168,12 cl!:L w80 shot:controls w60 k:ENTER w20",
    "go!:165,3 cl!:L w20 go!:168,20 cl!:L w40 go:220,150 shot:about ws",
    "say:hp1b ws",
    "say:hp2 ws w150",
]
