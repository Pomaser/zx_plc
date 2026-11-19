#!/usr/bin/env python3
"""UI tests of the ST editor: key scripts played into zxplc.sna by the zxrun
emulator, then the stored ST lines (indent + text), the compile result and
runtime values are read from the memory and compared.

    .scratch/venv/bin/python tools/st_uitest.py [-v] [--shots DIR] [test ...]

Scripts use the zxrun syntax (k:KEY, t:text with ~ = space, wN, shot:NAME,
at:X,Y, cl:L) plus the macros below.
"""
import os, sys, argparse
sys.path.insert(0, os.path.dirname(__file__))
from zxrun import Spectrum

HERE = os.path.dirname(os.path.abspath(__file__))
SNA = os.path.join(HERE, "..", "zxplc.sna")

PROJ = 0x9000
POU_TAB = PROJ + 16
POU_BODIES = POU_TAB + 10 * 32
RT = 0x8A00
RT_M = RT + 4
RT_MW = RT + 12
LV_BASE = 0xFD00
BANK_RUN = 4

D = "k:CS+6 w6 "                # cursor down
U = "k:CS+7 w6 "                # cursor up
L = "k:CS+5 w4 "                # left
R = "k:CS+8 w4 "                # right
E = "k:ENTER w40 "              # ENTER (commit, split, completion)
SE = "k:SS+ENTER w40 "          # SS+ENTER: a new line below
DEL = "k:CS+0 w4 "              # DELETE (backspace)
MENU = "k:CS+1 w8 "             # EDIT: the menu bar


def T(text):
    """typing (a space is ~ in zxrun scripts)"""
    return "t:" + text.replace(" ", "~") + " w4 "


class UI:
    def __init__(self, shots=None, mouse=True):
        self.z = Spectrum(SNA)
        self.z.mouse = mouse
        self.z.noborder = False
        self.shots = shots
        self.z.run(40)

    def play(self, script):
        z = self.z
        for cmd in script.split():
            if cmd.startswith("w"):
                z.run(int(cmd[1:]))
            elif cmd.startswith("k:"):
                z.key(cmd[2:])
            elif cmd.startswith("t:"):
                z.type(cmd[2:].replace("~", " "))
            elif cmd.startswith("shot:"):
                if self.shots:
                    z.png(os.path.join(self.shots, cmd[5:] + ".png"))
            elif cmd.startswith("at:"):
                x, y = map(int, cmd[3:].split(","))
                z.mouse_at(x, y)
            elif cmd.startswith("cl:"):
                z.click(cmd[3:])
            else:
                raise ValueError(cmd)

    # ---- project memory
    def mem(self, a, n=1):
        return bytes(self.z.m.memory[a:a + n])

    def slots(self):
        out = []
        for s in range(10):
            e = POU_TAB + s * 32
            name = self.mem(e, 8).decode("latin1").rstrip()
            lang = self.mem(e + 8)[0]
            ln = int.from_bytes(self.mem(e + 10, 2), "little")
            out.append((name, lang, ln))
        return out

    def slot_of(self, name):
        for i, (n, _, _) in enumerate(self.slots()[:8]):
            if n == name:
                return i
        raise KeyError(name)

    def body(self, slot):
        a = POU_BODIES
        sl = self.slots()
        for s in range(slot):
            a += sl[s][2]
        return self.mem(a, sl[slot][2])

    def st_lines(self, name):
        """[(indent, text)] of an ST POU"""
        b = self.body(self.slot_of(name))
        out, i = [], 0
        while i < len(b):
            n = b[i]
            assert b[i + 1] == 4, "not an ST line record"
            out.append((b[i + 2], b[i + 3:i + n].decode("latin1")))
            i += n
        return out

    def mw(self, n):
        return int.from_bytes(self.mem(RT_MW + 2 * n, 2), "little", signed=True)

    def mx(self, byte, bit):
        return (self.mem(RT_M + byte)[0] >> bit) & 1

    def sym(self, name):
        if not hasattr(self, "_sym"):
            self._sym = {}
            for line in open(os.path.join(HERE, "..", "zxplc.sym")):
                p = line.split()
                if len(p) >= 3 and p[1] == "EQU":
                    self._sym[p[0].rstrip(":")] = int(p[2], 16)
        return self._sym[name]

    def st_cur(self):
        """the cursor line of the ST editor (FBD bank 6)"""
        return int.from_bytes(self.z.bank_bytes(6, self.sym("st_cur"), 2), "little")

    def fbd_str(self, name, n=64):
        b = self.z.bank_bytes(6, self.sym(name), n)
        return bytes(b).split(b"\0")[0].decode("latin1")

    def status_left(self):
        """the text of the left status bar part (st_left -> fixed memory)"""
        a = int.from_bytes(self.mem(self.sym("st_left"), 2), "little")
        if not a:
            return ""
        return bytes(self.mem(a, 60)).split(b"\0")[0].decode("latin1")

    def sim_running(self):
        """the simulation screen is in RUN (sm_run, EDIT bank)"""
        return self.z.bank_bytes(0, self.sym("sm_run"), 1)[0] != 0

    def compile_error(self):
        """(message, line 1-based) of the last compile error"""
        a = int.from_bytes(self.mem(self.sym("il_err"), 2), "little")
        msg = bytes(self.mem(a, 40)).split(b"\0")[0].decode("latin1")
        line = int.from_bytes(self.mem(self.sym("cp_line"), 2), "little")
        return msg, line


# ---- macros
def new_st(name):
    """from the POU list: a new ST POU, its editor open"""
    return "k:N w30 " + T(name) + "k:ENTER w30 k:S w30 k:ENTER w40 k:ENTER w80 "


def to_list():
    """from an editor to the POU list (POU > Manage)"""
    return MENU + "k:H w8 k:P w10 k:M w60 "     # (H: no item has this hotkey)


def main_call(name):
    """from the POU list: MAIN gets a last line CAL name (IL editor)"""
    return ("k:CS+7 w4 k:CS+7 w4 k:CS+7 w4 k:CS+7 w4 k:CS+7 w4 k:CS+7 w4 k:ENTER w60 "
            "k:SS+CS+6 w20 k:SS+CS+6 w20 k:SS+ENTER w30 " + T("CAL " + name) + "k:ENTER w40 ")


def run():
    """Run > Run (compiles; an error opens the editor at its line)"""
    return MENU + "k:H w8 k:R w10 k:R w200 "    # (via Help: no R / P items)


# ============================================================ tests
RESULTS = []


def check(name, cond, info=""):
    RESULTS.append((name, bool(cond), info))
    print("  %s %s %s" % ("ok  " if cond else "FAIL", name, info if not cond else ""))


def compare(name, got, exp):
    ok = got == exp
    if not ok:
        print("  --- %s: expected / got" % name)
        for i in range(max(len(got), len(exp))):
            g = got[i] if i < len(got) else None
            e = exp[i] if i < len(exp) else None
            print("   %s %-38s %s" % ("  " if g == e else "!!", e, g))
    check(name, ok)


def t_long(ui):
    """typing a longer program: completion, auto split, folding, compile + run"""
    s = new_st("TST")
    s += T("var") + E                               # VAR / empty / END_VAR
    s += T("cnt : int;") + E
    s += T("sum : int := 10;") + E
    s += T("ok : bool;") + D + SE                   # END_VAR, a line below
    s += T("// main part") + E
    s += T("sum := 10;") + E
    s += T("cnt := 0;") + E
    s += T("for cnt := 1 to 5") + E                 # DO / empty / END_FOR
    s += T("sum := sum + cnt;") + D + SE
    s += T("if sum > 20 then ok := true;") + E     # split; a new line inside
    s += T("else ok := false; end_if;") + E         # split, ";" dropped
    s += T("while cnt > 0") + E
    s += T("cnt := cnt - 1;") + D + SE
    s += T("case sum of 25: %MW5 := 1;") + E
    s += T("else %MW5 := 2; end_case") + E
    s += T("repeat") + E                            # empty / UNTIL / END_REPEAT
    s += T("cnt := cnt + 2;") + D + T(" cnt >= 6") + D + SE
    s += T("%MW6 := cnt;") + E
    s += T("%MW7 := sum;") + E
    s += T("%MX1.0 := ok;") + U + "w20 shot:long_edit "
    ui.play(s)
    exp = [
        (0, "VAR"), (1, "cnt : INT;"), (1, "sum : INT := 10;"), (1, "ok : BOOL;"),
        (0, "END_VAR"),
        (0, "// main part"), (0, "sum := 10;"), (0, "cnt := 0;"),
        (0, "FOR cnt := 1 TO 5"), (0, "DO"), (1, "sum := sum + cnt;"), (0, "END_FOR"),
        (0, "IF sum > 20"), (0, "THEN"), (1, "ok := true;"), (0, "ELSE"),
        (1, "ok := false;"), (0, "END_IF"),
        (0, "WHILE cnt > 0"), (0, "DO"), (1, "cnt := cnt - 1;"), (0, "END_WHILE"),
        (0, "CASE sum"), (0, "OF"), (1, "25: %MW5 := 1;"), (0, "ELSE"), (1, "%MW5 := 2;"),
        (0, "END_CASE"),
        (0, "REPEAT"), (1, "cnt := cnt + 2;"), (0, "UNTIL cnt >= 6"), (0, "END_REPEAT"),
        (0, "%MW6 := cnt;"), (0, "%MW7 := sum;"), (0, "%MX1.0 := ok;"),
    ]
    compare("long: stored lines", ui.st_lines("TST"), exp)
    ui.play(to_list() + main_call("TST") + "shot:long_main " + run() + "shot:long_run ")
    check("long: run: cnt = 6", ui.mw(6) == 6, ui.mw(6))
    check("long: run: sum = 25", ui.mw(7) == 25, ui.mw(7))
    check("long: run: CASE 25:", ui.mw(5) == 1, ui.mw(5))
    check("long: run: ok (IF)", ui.mx(1, 0) == 1)


HOME = "k:SS+CS+5 w4 "          # SS+LEFT: line start
END = "k:SS+CS+8 w4 "           # SS+RIGHT: line end
MARK = "k:SS+A w10 "
COPY = "k:SS+D w30 "
PASTE = "k:SS+F w60 "
UNDO = "k:SS+U w60 "
REDO = "k:SS+Y w60 "
COMPL = "k:SS+SPACE w60 "


def t_edit(ui):
    """corrections: delete / insert characters, delete a line, split a line,
    lower case keywords, a refused unknown name, undo / redo"""
    s = new_st("ED")
    s += T("%MW1 := 5;") + E + T("%MW2 := 7;") + E + T("%MW3 := 9;") + E
    s += T("%MW4 := 1;") + U                        # -> line 2
    s += U + DEL + DEL + T("8;")                    # line 1: 7 -> 8
    s += U + L + T("+1")                            # line 0: 5 -> 5+1
    s += D + D                                      # line 2 "%MW3 := 9;"
    s += DEL * 10 + DEL                             # emptied, then removed
    s += U + HOME + R * 8 + E                       # line 0 split behind ":= "
    s += D + D + END + SE                           # a new line below line 3
    s += T("if %mx0.0 then") + E                    # split: IF / THEN / new
    s += T("%MW9 := 3; end_if;") + E                # split, END_IF without ;
    s += T("foo := 1;") + U + "w20 shot:edit_err " + "k:SPACE w20 "  # refused
    s += DEL * 9 + T("%MW10 := 1;") + U
    ui.play(s + "w20 shot:edit ")
    exp = [(0, "%MW1 :="), (0, "5+1;"), (0, "%MW2 := 8;"), (0, "%MW4 := 1;"),
           (0, "IF %MX0.0"), (0, "THEN"), (1, "%MW9 := 3;"), (0, "END_IF"),
           (0, "%MW10 := 1;")]
    compare("edit: stored lines", ui.st_lines("ED"), exp)
    ui.play(UNDO + "shot:edit_undo ")
    compare("edit: undo", ui.st_lines("ED"), exp[:-1] + [(0, "")])
    ui.play(REDO)
    compare("edit: redo", ui.st_lines("ED"), exp)


def t_clip(ui):
    """copy / paste a marked block, one line without a mark, cut, paste into
    another ST POU"""
    s = new_st("CA")
    s += T("%MW1 := 1;") + E + T("%MW2 := 2;") + E + T("%MW3 := 3;") + E
    s += T("%MW4 := 4;") + U + U + U                 # line 0
    s += MARK + D + COPY + MARK                      # lines 0-1 copied
    s += D + D + D + PASTE + "shot:clip_paste "      # in front of line 3
    exp = [(0, "%MW1 := 1;"), (0, "%MW2 := 2;"), (0, "%MW3 := 3;"),
           (0, "%MW1 := 1;"), (0, "%MW2 := 2;"), (0, "%MW4 := 4;")]
    ui.play(s)
    compare("clip: block pasted", ui.st_lines("CA"), exp)
    # the cursor is on the first pasted line (3): line 2 alone, in front of 5
    s = U + COPY + D + D + D + PASTE
    ui.play(s)
    exp2 = exp[:5] + [(0, "%MW3 := 3;"), (0, "%MW4 := 4;")]
    compare("clip: one line", ui.st_lines("CA"), exp2)
    s = U + MARK + U + MENU + "k:H w8 k:E w8 k:X w60 "  # Edit > Cut lines 3-4
    ui.play(s + "shot:clip_cut ")
    exp3 = exp2[:3] + exp2[5:]
    compare("clip: cut", ui.st_lines("CA"), exp3)
    s = to_list() + new_st("CB") + T("%MW9 := 9;") + U + PASTE  # into CB
    ui.play(s + "shot:clip_other ")
    compare("clip: paste in another POU", ui.st_lines("CB"),
            [(0, "%MW1 := 1;"), (0, "%MW2 := 2;"), (0, "%MW9 := 9;")])
    s = to_list() + "k:CS+7 w4 k:CS+7 w4 k:ENTER w60 " + PASTE  # IL MAIN: refused
    ui.play(s + "shot:clip_il ")
    check("clip: not into IL", ui.slots()[0][2] == 133, ui.slots()[0][2])


def t_autodecl(ui):
    """unknown names: ENTER -> the popup (I / B / T), UP -> only the error,
    BREAK keeps the error"""
    s = new_st("AD")
    s += T("count := count + 1;") + E + "w20 shot:ad_popup " + "k:I w60 "
    s += T("flag := TRUE;") + E + "k:B w60 "
    s += T("delay := T#2s;") + E + "k:T w60 "
    s += T("other := 1;") + U + "w20 shot:ad_up " + "k:SPACE w20 "   # error only
    s += DEL * 11 + T("other2 := 1;") + E + "w20 k:CS+SPACE w40 shot:ad_break "
    s += "k:SPACE w20 " + DEL * 12 + D + "w20 shot:ad_fold "
    ui.play(s)
    exp = [(0, "VAR"), (1, "count : INT;"), (1, "flag : BOOL;"), (1, "delay : TIME;"),
           (0, "END_VAR"), (0, "count := count + 1;"), (0, "flag := TRUE;"),
           (0, "delay := T#2s;"), (0, "")]
    got = ui.st_lines("AD")
    compare("autodecl: VAR block + lines", got[:len(exp)], exp)
    check("autodecl: no more lines", len(got) == len(exp), got[len(exp):])


def t_manual(ui):
    """a VAR block typed by hand (init values, comment), VAR elsewhere refused,
    no line above VAR, compile + run with the initial values"""
    s = new_st("MV")
    s += T("var") + E                                 # VAR / empty / END_VAR
    s += T("a : int := 7; // seven") + E
    s += T("b : bool := true;") + E
    s += T("t : time := t#1s;") + E
    s += T("c : int; d : int;") + D + D                # split: one per line
    s += SE + T("%MW1 := a;") + E + T("%MX2.0 := b;") + E + T("%MW2 := t;") + E
    s += T("d := a + 1; %MW3 := d;") + E
    s += T("var") + U + "w20 shot:mv_var2 " + "k:SPACE w20 " + DEL * 3 + U
    ui.play(s + "w20 shot:mv_fold ")
    # line 0: Edit > Insert line refused (beep)
    ui.play(HOME + "k:SS+CS+7 w20 k:SS+CS+7 w20 " + MENU + "k:H w8 k:E w8 k:I w40 ")
    got = ui.st_lines("MV")
    exp = [(0, "VAR"), (1, "a : INT := 7; // seven"), (1, "b : BOOL := true;"),
           (1, "t : TIME := t#1s;"), (1, "c : INT;"), (1, "d : INT;"), (0, "END_VAR"),
           (0, "%MW1 := a;"), (0, "%MX2.0 := b;"), (0, "%MW2 := t;"),
           (0, "d := a + 1; %MW3 := d;"), (0, "")]     # (statements are not split)
    compare("manual: stored lines", got[:len(exp)], exp)
    ui.play(to_list() + main_call("MV") + run() + "shot:mv_run ")
    check("manual: a = 7", ui.mw(1) == 7, ui.mw(1))
    check("manual: b = TRUE", ui.mx(2, 0) == 1)
    check("manual: t = 1 s (50 ticks)", ui.mw(2) == 50, ui.mw(2))
    check("manual: d = a + 1", ui.mw(3) == 8, ui.mw(3))


def t_compl(ui):
    """SS+SPACE: one candidate at once, the list with a filter, FB members,
    BREAK keeps the typed filter, a letter that fits nothing closes it"""
    s = new_st("CM")
    s += T("var") + E + T("speed : int;") + E + T("spare : bool;") + D + SE
    s += T("Le") + COMPL + T(" := ")                   # one: Level
    s += T("sp") + COMPL + "shot:cm_list " + "k:CS+6 w20 k:ENTER w40 " + T(";") + E
    s += T("TValve.") + COMPL + "k:CS+6 w20 k:ENTER w40 " + T(" := TRUE;") + E
    s += T("T") + COMPL + T("o") + "shot:cm_filter k:CS+SPACE w40 "  # BREAK: "To" stays
    s += COMPL + T(" := 0;") + E                     # one left: Total
    s += T("T") + COMPL + T("q") + "w20 shot:cm_close "  # nothing fits: closed, "Tq"
    s += T("x;") + U + "k:SPACE w20 " + DEL * 4 + T("%MW1 := 1;") + U
    ui.play(s + "w20 shot:cm ")
    got = ui.st_lines("CM")
    exp = [(0, "VAR"), (1, "speed : INT;"), (1, "spare : BOOL;"), (0, "END_VAR"),
           (0, "%MW0 := spare;"), (0, "TOF1.PT := TRUE;"), (0, "%MW1 := 0;"),
           (0, "%MW1 := 1;")]
    compare("compl: stored lines", got, exp)


def t_autorun(ui):
    """auto-declared variables compile and run"""
    s = new_st("AR")
    s += T("count := count + 1;") + E + "k:I w60 "
    s += T("%MW4 := count;") + U
    ui.play(s + to_list() + main_call("AR") + run() + "w100 ")
    check("autorun: count counts", ui.mw(4) > 20, ui.mw(4))


def t_errors(ui):
    """a deleted declaration and a VAR block pasted in the middle are
    compile errors at the right line"""
    s = new_st("ER")
    s += T("var") + E + T("x : int;") + D + SE
    s += T("x := 1;") + E + T("%MW1 := x;") + U
    ui.play(s)
    # delete the declaration line (Edit > Delete line), then Run
    ui.play(U + U + MENU + "k:H w8 k:E w8 k:D w60 " + "shot:er_del ")
    compare("errors: declaration deleted", ui.st_lines("ER"),
            [(0, "VAR"), (0, "END_VAR"), (0, "x := 1;"), (0, "%MW1 := x;")])
    ui.play(to_list() + main_call("ER") + run() + "shot:er_run1 ")
    check("errors: unknown name", ui.compile_error() == ("Unknown name: X", 3),
          ui.compile_error())


def t_varpaste(ui):
    """a VAR block pasted into the code: refused by the compiler"""
    s = new_st("EV")
    s += T("var") + E + T("y : int;") + D + SE
    s += T("y := 1;") + E + T("%MW1 := y;") + U        # -> line 3
    s += U + U + U + MARK + D + D + COPY + MARK         # lines 0-2
    s += D + D + D + D + PASTE + "shot:ev_paste "       # in front of line 4
    ui.play(s)
    compare("varpaste: pasted", ui.st_lines("EV"),
            [(0, "VAR"), (1, "y : INT;"), (0, "END_VAR"), (0, "y := 1;"),
             (0, "VAR"), (1, "y : INT;"), (0, "END_VAR"), (0, "%MW1 := y;")])
    # the cursor is on the pasted VAR: leaving the line is refused
    ui.play(U + "w20 shot:ev_refused " + "k:SPACE w20 ")
    check("varpaste: refused in the editor (cursor stays)", ui.st_cur() == 4, ui.st_cur())
    ui.play(DEL * 3 + U + "w20 shot:ev_fixed ")     # VAR removed: the line is empty
    got = ui.st_lines("EV")
    check("varpaste: fixed by deleting VAR", got[4] == (0, "") and got[0] == (0, "VAR"),
          got)
    ui.play(to_list() + main_call("EV") + run() + "shot:ev_run ")
    check("varpaste: the stray declaration is a compile error",
          ui.compile_error()[1] == 6, ui.compile_error())


def t_toolong(ui):
    """a line wider than the screen: the rest is refused (beep), the text
    stays a correct prefix"""
    text = "%MW1 := %MW2 + %MW3 + %MW4 + %MW5 + %MW6 + %MW7 + %MW8 + %MW9;"
    ui.play(new_st("TL") + T(text) + "w10 shot:tl ")
    ui.play(T(";") + U)
    got = ui.st_lines("TL")[0][1]
    check("toolong: a prefix was kept", text.startswith(got[:-1]) and len(got) > 30,
          repr(got))


def t_view(ui):
    """operands are stored as addresses; View > Symbols / Addresses changes
    how they are shown (and edited); the status bar shows the symbol"""
    s = new_st("VW")
    s += T("var") + E + T("n : int;") + D + SE
    s += T("Level := Level + 1; n := 2;") + E + T("UpEdge(CLK := Up);") + U + "w20 "
    s += HOME + R + R + "w20 "                                  # on "%MW0"
    ui.play(s)
    exp = [(0, "VAR"), (1, "n : INT;"), (0, "END_VAR"),
           (0, "%MW0 := %MW0 + 1; n := 2;"), (0, "RT1(CLK := %IX0.2);")]
    compare("view: stored as addresses", ui.st_lines("VW"), exp)
    check("view: addresses shown", ui.fbd_str("se_buf") == "%MW0 := %MW0 + 1; n := 2;",
          ui.fbd_str("se_buf"))
    st = ui.status_left()
    check("view: status bar = symbol + comment", "Level" in st and "Level 0-5" in st, repr(st))
    ui.play(MENU + "k:H w8 k:V w8 k:S w100 shot:view_sym ")      # View > Symbols
    check("view: symbols shown", ui.fbd_str("se_buf") == "Level := Level + 1; n := 2;",
          ui.fbd_str("se_buf"))
    ui.play(D + "w30 ")
    check("view: FB + input as symbols", ui.fbd_str("se_buf") == "UpEdge(CLK := Up);",
          ui.fbd_str("se_buf"))
    compare("view: storage unchanged", ui.st_lines("VW"), exp)
    ui.play(U + "w30 " + END + L + L + L + L + "w20 ")             # on "n"
    st = ui.status_left()
    check("view: status bar = local", "local INT" in st, repr(st))


PAL = "k:SS+E w60 "


def t_palette(ui):
    """SS+E: the command palette on every screen: POUs and menu commands,
    filtered by a part of the name"""
    # POU list: "dem", the second one (DEMO_LD) -> its editor
    ui.play(PAL + T("dem") + "shot:pal_filter " + D + "k:ENTER w100 shot:pal_pou ")
    check("palette: POU opened", ui.mem(ui.sym("cur_pou"))[0] == ui.slot_of("DEMO_LD"),
          ui.mem(ui.sym("cur_pou"))[0])
    # BREAK: no command, the screen restored
    ui.play(PAL + "k:CS+SPACE w40 shot:pal_break ")
    check("palette: BREAK keeps the POU", ui.mem(ui.sym("cur_pou"))[0] == ui.slot_of("DEMO_LD"))
    # a letter with no match is refused: "runq" stays "run"
    ui.play(PAL + T("runq") + "shot:pal_run ")
    ui.play("k:ENTER w300 shot:pal_sim ")                # Run > Run
    check("palette: Run runs the simulation", ui.mw(0) >= 0 and ui.sim_running(),
          ui.sim_running())


def t_palmouse(ui):
    """a click on an entry of the palette"""
    ui.play("w60 k:CS+1 w10 k:H w10 k:O w10 k:M w30 ")    # Options > Mouse
    ui.play(PAL + T("st") + "w20 at:100,28 w10 cl:L w100 shot:pal_click ")
    check("palette: click opens DEMO_ST", ui.mem(ui.sym("cur_pou"))[0] == ui.slot_of("DEMO_ST"),
          ui.mem(ui.sym("cur_pou"))[0])


TESTS = {"long": t_long, "edit": t_edit, "clip": t_clip, "autodecl": t_autodecl,
         "manual": t_manual, "compl": t_compl, "autorun": t_autorun,
         "errors": t_errors, "varpaste": t_varpaste, "toolong": t_toolong,
         "view": t_view, "palette": t_palette, "palmouse": t_palmouse}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tests", nargs="*")
    ap.add_argument("--shots", default=None)
    a = ap.parse_args()
    if a.shots:
        os.makedirs(a.shots, exist_ok=True)
    for name in (a.tests or TESTS):
        print("[%s]" % name)
        TESTS[name](UI(a.shots))
    bad = [r for r in RESULTS if not r[1]]
    print("%d checks, %d failed" % (len(RESULTS), len(bad)))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
