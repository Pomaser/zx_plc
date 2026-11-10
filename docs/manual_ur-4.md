# Uživatelská a technická příručka: Rozhraní UR-4 pro ZX Spectrum

Univerzální rozhraní **UR-4** (výrobce TESLA s.p. Kolín) rozšiřuje možnosti mikropočítačů kompatibilních se Sinclair ZX Spectrum o obousměrné paralelní porty, rozhraní pro připojení joysticků, tiskáren a měřicí techniky.

---

## 1. Technická specifikace a popis obvodu

Srdcem rozhraní UR-4 je programovatelný periferní obvod **MHB 8255A** (kompatibilní s Intel 8255), který obsahuje tři paralelní 8bitové brány ($PA$, $PB$, $PC$).

* **Sběrnicový obvod:** MHB 8255A
* **Pracovní režimy:** Vstupní / Výstupní (obousměrné rozhraní)
* **Zatížitelnost výstupů:** Max. 1 logická jednotka TTL pro každý bit ($I_{OL} = 1{,}7\text{ mA}$ při $V_{OL} \le 0{,}45\text{ V}$, $I_{OH} = -200\text{ }\mu\text{A}$ při $V_{OH} \ge 2{,}4\text{ V}$)
* **Odběr proudu:** Max. $130\text{ mA}$
* **Napájení:** $9{,}0\text{ V}$ DC přímo ze sběrnice počítače (obsahuje vestavěný stabilizátor na $+5\text{ V}$)
* **Ovládací prvky:** Tlačítko **RESET** pro nulování počítače i obvodu 8255A.
* **Kompatibilita:** ZX Spectrum, Spectrum +, Spectrum 128, Amstrad +2, Amstrad +3 (*Poznámka: Není kompatibilní s Didaktik Gama od VD Služba Skalica z důvodu chybějícího napětí +9 V na sběrnici*).

---

## 2. Adresování bran a řídicího registru

Komunikace s obvodem probíhá na 8bitové adrese řízené dekódováním adresních linek $A_5, A_6, A_7$.

### Přehled dekadických adres (Portů)

| Registr / Brána | Dekadická adresa | Popis |
| :--- | :---: | :--- |
| **Brána PA** | **31** | 8bitová datová brána (PA0–PA7) |
| **Brána PB** | **63** | 8bitová datová brána (PB0–PB7) |
| **Brána PC** | **95** | 8bitová datová brána (PC0–PC7) / rozdělitelná po 4 bitech |
| **Řídicí registr (CWR)** | **127** | Registr řídicího slova (Control Word Register) |

---

## 3. Inicializace a konfigurace bran (CWR)

Po zapnutí počítače nebo stisku tlačítka RESET je obvod automaticky nastaven tak, že všechny brány fungují jako **vstupní**. Pro jinou konfiguraci je nutné odeslat řídicí slovo na adresu `127`.

### Logický stav v tabulce konfigurace:
* `0` = Brána nastavena jako **výstupní**
* `1` = Brána nastavena jako **vstupní**

### Tabulka řídicích slov (Port 127)

| Řídicí slovo (Decimal) | Brána PA (bit 0–7) | Brána PB (bit 0–7) | Brána PC (bit 0–3) | Brána PC (bit 4–7) |
| :---: | :---: | :---: | :---: | :---: |
| **128** | 0 (Výstup) | 0 (Výstup) | 0 (Výstup) | 0 (Výstup) |
| **129** | 0 (Výstup) | 0 (Výstup) | 1 (Vstup) | 0 (Výstup) |
| **130** | 0 (Výstup) | 1 (Vstup) | 0 (Výstup) | 0 (Výstup) |
| **131** | 0 (Výstup) | 1 (Vstup) | 1 (Vstup) | 0 (Výstup) |
| **136** | 0 (Výstup) | 0 (Výstup) | 0 (Výstup) | 1 (Vstup) |
| **137** | 0 (Výstup) | 0 (Výstup) | 1 (Vstup) | 1 (Vstup) |
| **138** | 0 (Výstup) | 1 (Vstup) | 0 (Výstup) | 1 (Vstup) |
| **139** | 0 (Výstup) | 1 (Vstup) | 1 (Vstup) | 1 (Vstup) |
| **144** | 1 (Vstup) | 0 (Výstup) | 0 (Výstup) | 0 (Výstup) |
| **145** | 1 (Vstup) | 0 (Výstup) | 1 (Vstup) | 0 (Výstup) |
| **146** | 1 (Vstup) | 1 (Vstup) | 0 (Výstup) | 0 (Výstup) |
| **147** | 1 (Vstup) | 1 (Vstup) | 1 (Vstup) | 0 (Výstup) |
| **152** | 1 (Vstup) | 0 (Výstup) | 0 (Výstup) | 1 (Vstup) |
| **153** | 1 (Vstup) | 0 (Výstup) | 1 (Vstup) | 1 (Vstup) |
| **154** | 1 (Vstup) | 1 (Vstup) | 0 (Výstup) | 1 (Vstup) |
| **155** | 1 (Vstup) | 1 (Vstup) | 1 (Vstup) | 1 (Vstup) |

---

## 4. Příklady programování v BASICu

V prostředí Sinclair BASIC se pro komunikaci s rozhraním používají instrukce `OUT` (zápis na port) a `IN` (čtení z portu).

### A. Inicializace bran
```bas
10 REM Nastavení všech bran jako výstupních
20 OUT 127, 128

30 REM Nastavení všech bran jako vstupních
40 OUT 127, 155

50 REM Brány PA a PB jako vstupní, PC jako výstupní
60 OUT 127, 146
```

### B. Zápis dat na výstupní brány
```bas
10 OUT 127, 128 : REM Konfigurace: Všechny brány = VÝSTUP
20 OUT 31, 255  : REM Na bránu PA pošle hodnotu 255 (11111111b)
30 OUT 63, 128  : REM Na bránu PB pošle hodnotu 128 (10000000b)
40 OUT 31, 170  : REM Na bránu PA pošle hodnotu 170 (10101010b)
```

### C. Čtení dat ze vstupních bran
```bas
10 OUT 127, 155 : REM Konfigurace: Všechny brány = VSTUP
20 LET a = IN 63 : REM Načtení dat z brány PB do proměnné 'a'
30 LET b = IN 31 : REM Načtení dat z brány PA do proměnné 'b'
40 PRINT "Hodnota PB: "; a, "Hodnota PA: "; b
```

---

## 5. Zapojení konektorů a periférií

UR-4 nabízí připojení pro různorodá periferní zařízení:
* **Kempston Joystick:** Připojuje se do konektoru **Cannon** (D-Sub). V hrách volte ovládaní typu *Kempston*.
* **Tiskárny:** Podpora tiskáren Gamacentrum 01 (výrobce GAMA Milevsko) nebo BT-100 (výrobce TESLA Přelouč, s rozhraním ZP-Spectrum).
* **Převodníky:** A/D a D/A převodníky, měřicí přístroje se sběrnicovým rozhraním.

### Připojení nestandardních ovladačů
Ovladače, které nemají konektor typu Cannon nebo spínají vůči kladnému napětí ($+5\text{ V}$), musí být osazeny řadovým konektorem `TX 514 30.13` nebo `TX 527 30.13` a spínat proti zemi (GND).

---

## 6. Bezpečnostní pokyny a údržba

1. **Vypínání počítače:** Zasouvání i vysouvání rozhraní UR-4 provádějte **ZÁSADNĚ PŘI VYPNUTÉM POČÍTAČI**. Při manipulaci pod napětím hrozí zničení počítače nebo obvodu 8255A!
2. **Statická elektřina:** Vyvarujte se přímého dotýkání vývodů přímého konektoru. Obvody MOS jsou citlivé na poškození statickým nábojem.
3. **Klíč konektoru:** Při zasouvání na sběrnici dbejte na to, aby klíč (přepážka) v přímém konektoru přesně zapadl do výřezu v plošném spojení sběrnice počítače.