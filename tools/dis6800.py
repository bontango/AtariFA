#!/usr/bin/env python3
"""
dis6800.py  —  Motorola 6800 disassembler for AtariFA / Middle Earth ROM analysis
Reads rom/609.hex (mapped @0x7000) and rom/608.hex (mapped @0x7800) into a 64K map.
Emits an annotated listing to tools/listing.txt and optionally a boot-path trace.

Usage:
    python tools/dis6800.py              # full listing of both ROMs
    python tools/dis6800.py --trace      # also follows boot path from RESET vector

Author: Claude Code / bontango 2026-06
"""

import sys, os, struct

# ──────────────────────────────────────────────────────────────────────────────
# IO address symbols  (PinMAME src/wpc/atari.c + AtariFA address decode)
# ──────────────────────────────────────────────────────────────────────────────
IO_SYMS = {
    # Display/score RAM shadow  0x00–0x1F
    **{a: f"DISP_RAM+${a:02X}" for a in range(0x00, 0x20)},
    # Lamp RAM  0x20–0x3F
    **{a: f"LAMP_RAM+${a:02X}" for a in range(0x20, 0x40)},
    # NVRAM (fake single byte)
    0x0200: "NVRAM_0200",
    # Solenoid latches  (Phase B, not yet wired in FPGA)
    0x1080: "SOL_LATCH1",
    0x1084: "SOL_LATCH2",
    0x1088: "SOL_LATCH3",
    0x108C: "SOL_LATCH4",
    # DIP switch / strobe registers  0x2000–0x200F
    0x2000: "DIP_STROBE0",
    0x2001: "DIP_STROBE1",
    0x2002: "DIP_STROBE2",
    0x2003: "DIP_STROBE3",
    0x2004: "DIP_STROBE4",
    0x2005: "DIP_STROBE5",
    0x2006: "DIP_STROBE6",
    0x2007: "DIP_STROBE7",
    0x2008: "DIP_STROBE8",
    0x2009: "DIP_STROBE9",
    0x200A: "DIP_STROBE10",
    0x200B: "DIP_STROBE11",
    0x200C: "DIP_STROBE12",
    0x200D: "DIP_STROBE13",
    0x200E: "DIP_STROBE14",
    0x200F: "DIP_STROBE15",
    # Switch matrix  0x2010–0x204F
    **{a: f"SW_ROW+${a-0x2010:02X}" for a in range(0x2010, 0x2050)},
    # Audio
    0x3000: "AUDIO_OUT_3000",
    0x6000: "AUDIO_OUT_6000",
    # ROM vectors (end of ROM1 608 @ 0x7FF8–0x7FFF = CPU 0xFFF8–0xFFFF)
    0x7FF8: "VEC_IRQ_HI",  0x7FF9: "VEC_IRQ_LO",
    0x7FFA: "VEC_SWI_HI",  0x7FFB: "VEC_SWI_LO",
    0x7FFC: "VEC_NMI_HI",  0x7FFD: "VEC_NMI_LO",
    0x7FFE: "VEC_RST_HI",  0x7FFF: "VEC_RST_LO",
}

def sym(addr):
    return IO_SYMS.get(addr, "")

# ──────────────────────────────────────────────────────────────────────────────
# 6800 opcode table  format: (mnemonic, mode, size)
# Modes: INH=inherent, IMM1=imm byte, IMM2=imm word,
#        DIR=direct(byte addr), EXT=extended(word addr),
#        IDX=indexed(byte offset), REL=relative branch
# ──────────────────────────────────────────────────────────────────────────────
INH  = "INH"
IMM1 = "IMM1"
IMM2 = "IMM2"
DIR  = "DIR"
EXT  = "EXT"
IDX  = "IDX"
REL  = "REL"

OPCODES = {
    0x01: ("NOP",   INH,  1),
    0x06: ("TAP",   INH,  1),
    0x07: ("TPA",   INH,  1),
    0x08: ("INX",   INH,  1),
    0x09: ("DEX",   INH,  1),
    0x0A: ("CLV",   INH,  1),
    0x0B: ("SEV",   INH,  1),
    0x0C: ("CLC",   INH,  1),
    0x0D: ("SEC",   INH,  1),
    0x0E: ("CLI",   INH,  1),
    0x0F: ("SEI",   INH,  1),
    0x10: ("SBA",   INH,  1),
    0x11: ("CBA",   INH,  1),
    0x16: ("TAB",   INH,  1),
    0x17: ("TBA",   INH,  1),
    0x19: ("DAA",   INH,  1),
    0x1B: ("ABA",   INH,  1),
    0x1C: ("?1C",   INH,  1),   # undoc / 6801 BSET
    0x1D: ("?1D",   INH,  1),   # undoc / 6801 BCLR
    0x20: ("BRA",   REL,  2),
    0x21: ("BRN",   REL,  2),
    0x22: ("BHI",   REL,  2),
    0x23: ("BLS",   REL,  2),
    0x24: ("BCC",   REL,  2),
    0x25: ("BCS",   REL,  2),
    0x26: ("BNE",   REL,  2),
    0x27: ("BEQ",   REL,  2),
    0x28: ("BVC",   REL,  2),
    0x29: ("BVS",   REL,  2),
    0x2A: ("BPL",   REL,  2),
    0x2B: ("BMI",   REL,  2),
    0x2C: ("BGE",   REL,  2),
    0x2D: ("BLT",   REL,  2),
    0x2E: ("BGT",   REL,  2),
    0x2F: ("BLE",   REL,  2),
    0x30: ("TSX",   INH,  1),
    0x31: ("INS",   INH,  1),
    0x32: ("PULA",  INH,  1),
    0x33: ("PULB",  INH,  1),
    0x34: ("DES",   INH,  1),
    0x35: ("TXS",   INH,  1),
    0x36: ("PSHA",  INH,  1),
    0x37: ("PSHB",  INH,  1),
    0x38: ("?38",   INH,  1),
    0x39: ("RTS",   INH,  1),
    0x3A: ("?3A",   INH,  1),
    0x3B: ("RTI",   INH,  1),
    0x3C: ("?3C",   INH,  1),
    0x3D: ("?3D",   INH,  1),
    0x3E: ("WAI",   INH,  1),
    0x3F: ("SWI",   INH,  1),
    0x40: ("NEGA",  INH,  1),
    0x43: ("COMA",  INH,  1),
    0x44: ("LSRA",  INH,  1),
    0x46: ("RORA",  INH,  1),
    0x47: ("ASRA",  INH,  1),
    0x48: ("ASLA",  INH,  1),
    0x49: ("ROLA",  INH,  1),
    0x4A: ("DECA",  INH,  1),
    0x4C: ("INCA",  INH,  1),
    0x4D: ("TSTA",  INH,  1),
    0x4F: ("CLRA",  INH,  1),
    0x50: ("NEGB",  INH,  1),
    0x53: ("COMB",  INH,  1),
    0x54: ("LSRB",  INH,  1),
    0x56: ("RORB",  INH,  1),
    0x57: ("ASRB",  INH,  1),
    0x58: ("ASLB",  INH,  1),
    0x59: ("ROLB",  INH,  1),
    0x5A: ("DECB",  INH,  1),
    0x5C: ("INCB",  INH,  1),
    0x5D: ("TSTB",  INH,  1),
    0x5F: ("CLRB",  INH,  1),
    0x60: ("NEG",   IDX,  2),
    0x63: ("COM",   IDX,  2),
    0x64: ("LSR",   IDX,  2),
    0x66: ("ROR",   IDX,  2),
    0x67: ("ASR",   IDX,  2),
    0x68: ("ASL",   IDX,  2),
    0x69: ("ROL",   IDX,  2),
    0x6A: ("DEC",   IDX,  2),
    0x6C: ("INC",   IDX,  2),
    0x6D: ("TST",   IDX,  2),
    0x6E: ("JMP",   IDX,  2),
    0x6F: ("CLR",   IDX,  2),
    0x70: ("NEG",   EXT,  3),
    0x73: ("COM",   EXT,  3),
    0x74: ("LSR",   EXT,  3),
    0x76: ("ROR",   EXT,  3),
    0x77: ("ASR",   EXT,  3),
    0x78: ("ASL",   EXT,  3),
    0x79: ("ROL",   EXT,  3),
    0x7A: ("DEC",   EXT,  3),
    0x7C: ("INC",   EXT,  3),
    0x7D: ("TST",   EXT,  3),
    0x7E: ("JMP",   EXT,  3),
    0x7F: ("CLR",   EXT,  3),
    0x80: ("SUBA",  IMM1, 2),
    0x81: ("CMPA",  IMM1, 2),
    0x82: ("SBCA",  IMM1, 2),
    0x84: ("ANDA",  IMM1, 2),
    0x85: ("BITA",  IMM1, 2),
    0x86: ("LDAA",  IMM1, 2),
    0x88: ("EORA",  IMM1, 2),
    0x89: ("ADCA",  IMM1, 2),
    0x8A: ("ORAA",  IMM1, 2),
    0x8B: ("ADDA",  IMM1, 2),
    0x8C: ("CPX",   IMM2, 3),
    0x8D: ("BSR",   REL,  2),
    0x8E: ("LDS",   IMM2, 3),
    0x90: ("SUBA",  DIR,  2),
    0x91: ("CMPA",  DIR,  2),
    0x92: ("SBCA",  DIR,  2),
    0x94: ("ANDA",  DIR,  2),
    0x95: ("BITA",  DIR,  2),
    0x96: ("LDAA",  DIR,  2),
    0x97: ("STAA",  DIR,  2),
    0x98: ("EORA",  DIR,  2),
    0x99: ("ADCA",  DIR,  2),
    0x9A: ("ORAA",  DIR,  2),
    0x9B: ("ADDA",  DIR,  2),
    0x9C: ("CPX",   DIR,  2),
    0x9D: ("JSR",   DIR,  2),
    0x9E: ("LDS",   DIR,  2),
    0x9F: ("STS",   DIR,  2),
    0xA0: ("SUBA",  IDX,  2),
    0xA1: ("CMPA",  IDX,  2),
    0xA2: ("SBCA",  IDX,  2),
    0xA4: ("ANDA",  IDX,  2),
    0xA5: ("BITA",  IDX,  2),
    0xA6: ("LDAA",  IDX,  2),
    0xA7: ("STAA",  IDX,  2),
    0xA8: ("EORA",  IDX,  2),
    0xA9: ("ADCA",  IDX,  2),
    0xAA: ("ORAA",  IDX,  2),
    0xAB: ("ADDA",  IDX,  2),
    0xAC: ("CPX",   IDX,  2),
    0xAD: ("JSR",   IDX,  2),
    0xAE: ("LDS",   IDX,  2),
    0xAF: ("STS",   IDX,  2),
    0xB0: ("SUBA",  EXT,  3),
    0xB1: ("CMPA",  EXT,  3),
    0xB2: ("SBCA",  EXT,  3),
    0xB4: ("ANDA",  EXT,  3),
    0xB5: ("BITA",  EXT,  3),
    0xB6: ("LDAA",  EXT,  3),
    0xB7: ("STAA",  EXT,  3),
    0xB8: ("EORA",  EXT,  3),
    0xB9: ("ADCA",  EXT,  3),
    0xBA: ("ORAA",  EXT,  3),
    0xBB: ("ADDA",  EXT,  3),
    0xBC: ("CPX",   EXT,  3),
    0xBD: ("JSR",   EXT,  3),
    0xBE: ("LDS",   EXT,  3),
    0xBF: ("STS",   EXT,  3),
    0xC0: ("SUBB",  IMM1, 2),
    0xC1: ("CMPB",  IMM1, 2),
    0xC2: ("SBCB",  IMM1, 2),
    0xC4: ("ANDB",  IMM1, 2),
    0xC5: ("BITB",  IMM1, 2),
    0xC6: ("LDAB",  IMM1, 2),
    0xC8: ("EORB",  IMM1, 2),
    0xC9: ("ADCB",  IMM1, 2),
    0xCA: ("ORAB",  IMM1, 2),
    0xCB: ("ADDB",  IMM1, 2),
    0xCE: ("LDX",   IMM2, 3),
    0xD0: ("SUBB",  DIR,  2),
    0xD1: ("CMPB",  DIR,  2),
    0xD2: ("SBCB",  DIR,  2),
    0xD4: ("ANDB",  DIR,  2),
    0xD5: ("BITB",  DIR,  2),
    0xD6: ("LDAB",  DIR,  2),
    0xD7: ("STAB",  DIR,  2),
    0xD8: ("EORB",  DIR,  2),
    0xD9: ("ADCB",  DIR,  2),
    0xDA: ("ORAB",  DIR,  2),
    0xDB: ("ADDB",  DIR,  2),
    0xDE: ("LDX",   DIR,  2),
    0xDF: ("STX",   DIR,  2),
    0xE0: ("SUBB",  IDX,  2),
    0xE1: ("CMPB",  IDX,  2),
    0xE2: ("SBCB",  IDX,  2),
    0xE4: ("ANDB",  IDX,  2),
    0xE5: ("BITB",  IDX,  2),
    0xE6: ("LDAB",  IDX,  2),
    0xE7: ("STAB",  IDX,  2),
    0xE8: ("EORB",  IDX,  2),
    0xE9: ("ADCB",  IDX,  2),
    0xEA: ("ORAB",  IDX,  2),
    0xEB: ("ADDB",  IDX,  2),
    0xEE: ("LDX",   IDX,  2),
    0xEF: ("STX",   IDX,  2),
    0xF0: ("SUBB",  EXT,  3),
    0xF1: ("CMPB",  EXT,  3),
    0xF2: ("SBCB",  EXT,  3),
    0xF4: ("ANDB",  EXT,  3),
    0xF5: ("BITB",  EXT,  3),
    0xF6: ("LDAB",  EXT,  3),
    0xF7: ("STAB",  EXT,  3),
    0xF8: ("EORB",  EXT,  3),
    0xF9: ("ADCB",  EXT,  3),
    0xFA: ("ORAB",  EXT,  3),
    0xFB: ("ADDB",  EXT,  3),
    0xFE: ("LDX",   EXT,  3),
    0xFF: ("STX",   EXT,  3),
}

# ──────────────────────────────────────────────────────────────────────────────
# Intel HEX loader
# ──────────────────────────────────────────────────────────────────────────────
def load_hex(path, mem, base=0x0000):
    """Load an Intel HEX file into bytearray mem (64K) with an address offset.
    The HEX file's internal addresses are relative to 0; base shifts them to CPU space.
    E.g. 609.hex (0-based) loaded with base=0x7000 → CPU address 0x7000.
    """
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line.startswith(':'):
                continue
            data = bytes.fromhex(line[1:])
            rec_type = data[3]
            if rec_type == 0x00:   # data record
                addr  = ((data[1] << 8) | data[2]) + base
                count = data[0]
                for i in range(count):
                    if 0 <= addr + i < 0x10000:
                        mem[addr + i] = data[4 + i]
            elif rec_type == 0x01:  # EOF
                break

# ──────────────────────────────────────────────────────────────────────────────
# Disassemble one instruction, return (text, size, target_addr_or_None)
# ──────────────────────────────────────────────────────────────────────────────
def disasm_one(mem, pc):
    op = mem[pc]
    if op not in OPCODES:
        return (f"???  ${op:02X}", 1, None)

    mnem, mode, size = OPCODES[op]

    target = None
    note   = ""

    if mode == INH:
        operand = ""
    elif mode == IMM1:
        v = mem[pc+1]
        operand = f"#${v:02X}"
    elif mode == IMM2:
        v = (mem[pc+1] << 8) | mem[pc+2]
        operand = f"#${v:04X}"
        target = v
    elif mode == DIR:
        v = mem[pc+1]
        operand = f"${v:02X}"
        target = v
        note = sym(v)
    elif mode == EXT:
        v = (mem[pc+1] << 8) | mem[pc+2]
        operand = f"${v:04X}"
        target = v
        note = sym(v)
    elif mode == IDX:
        v = mem[pc+1]
        operand = f"${v:02X},X"
    elif mode == REL:
        offset = mem[pc+1]
        if offset >= 0x80:
            offset -= 0x100   # sign-extend
        dest = (pc + 2 + offset) & 0xFFFF
        operand = f"${dest:04X}"
        target = dest
    else:
        operand = "?"

    text = f"{mnem:<6} {operand}"
    if note:
        text += f"   ; {note}"

    return (text, size, target)

# ──────────────────────────────────────────────────────────────────────────────
# Full linear disassembly of a memory range
# ──────────────────────────────────────────────────────────────────────────────
def disasm_range(mem, start, end, labels):
    lines = []
    pc = start
    while pc < end:
        # emit label if known
        if pc in labels:
            lines.append(f"\n{labels[pc]}:")

        op_bytes = ""
        for i in range(min(3, end - pc)):
            op_bytes += f"{mem[pc+i]:02X} "

        text, size, _ = disasm_one(mem, pc)
        lines.append(f"  {pc:04X}:  {op_bytes:<9}  {text}")
        pc += size
    return lines

# ──────────────────────────────────────────────────────────────────────────────
# Boot-path trace: follow execution from RESET vector, record every IO access,
# detect tight loops (backward branch landing inside last 16 instructions).
# Stops after MAX_INSN instructions or on ambiguous indirect branch.
# ──────────────────────────────────────────────────────────────────────────────
BRANCH_OPS = {"BRA","BRN","BHI","BLS","BCC","BCS","BNE","BEQ","BVC","BVS",
              "BPL","BMI","BGE","BLT","BGT","BLE","BSR"}
CALL_OPS   = {"JSR","BSR"}
RETURN_OPS = {"RTS","RTI","SWI","WAI"}
JUMP_OPS   = {"JMP"}

def trace_boot(mem, reset_pc, labels, max_insn=8000):
    """
    Simple linear simulator: follows branches/jumps statically.
    Maintains a call stack (depth-limited) and detects loops.
    Returns list of annotated lines and a list of found IO polls.
    """
    visited  = {}           # pc → visit count
    call_stk = []           # return addresses
    pc       = reset_pc
    result   = []
    io_polls = []           # (pc, addr, mnem) for IO reads
    loop_hits= []           # (loop_start, loop_end, io_addr)

    recent   = []           # ring of last 32 PCs for loop detection

    ROM_RANGES = [(0x7000, 0x7800), (0x7800, 0x8000)]
    def in_rom(a):
        return any(lo <= a < hi for lo, hi in ROM_RANGES)

    for step in range(max_insn):
        if not in_rom(pc):
            result.append(f"  {pc:04X}: [outside ROM — stop]")
            break

        visited[pc] = visited.get(pc, 0) + 1
        if visited[pc] > 3:
            result.append(f"  {pc:04X}: [loop ×{visited[pc]} — stop tracing this path]")
            break

        # loop detection: is this PC in recent history?
        if pc in recent[-16:]:
            idx = recent.index(pc) if pc in recent else -1
            loop_seg = recent[max(0, len(recent)-16):]
            # collect IO in this segment
            loop_io = [x for x in io_polls if x[0] in loop_seg]
            loop_hits.append((pc, loop_seg, loop_io))

        recent.append(pc)
        if len(recent) > 64:
            recent.pop(0)

        lbl = f"{labels[pc]}:" if pc in labels else ""
        op_bytes = " ".join(f"{mem[pc+i]:02X}" for i in range(min(3, 0x8000-pc)))
        text, size, tgt = disasm_one(mem, pc)

        mnem = text.split()[0]

        # annotate IO accesses
        io_note = ""
        if size >= 2:
            # EXT absolute address accesses
            if mem[pc] in OPCODES:
                _, mode, _ = OPCODES[mem[pc]]
                if mode == EXT:
                    ea = (mem[pc+1] << 8) | mem[pc+2]
                    s  = sym(ea)
                    if s:
                        io_note = f"  *** IO: {s}"
                        if mnem in ("LDAA","LDAB","LDX","LDS"):
                            io_polls.append((pc, ea, mnem))
                elif mode == DIR:
                    ea = mem[pc+1]
                    s  = sym(ea)
                    if s and mnem in ("LDAA","LDAB"):
                        io_note = f"  *** IO: {s}"
                        io_polls.append((pc, ea, mnem))

        flag = "  <<<" if visited.get(pc, 0) > 1 else ""
        result.append(f"  {pc:04X}: {op_bytes:<9}  {lbl:<12} {text}{io_note}{flag}")

        next_pc = pc + size

        if mnem in RETURN_OPS:
            if call_stk:
                next_pc = call_stk.pop()
                result.append(f"          ; return → {next_pc:04X}")
            else:
                result.append("          ; return (stack empty — stop)")
                break
        elif mnem in CALL_OPS:
            if tgt and in_rom(tgt) and len(call_stk) < 6:
                call_stk.append(next_pc)
                next_pc = tgt
            else:
                result.append(f"          ; call {tgt:04X} (too deep or out-of-ROM — skip body)")
        elif mnem == "JMP":
            if tgt and in_rom(tgt):
                next_pc = tgt
            else:
                result.append(f"          ; JMP {tgt:04X} (out-of-ROM — stop)")
                break
        elif mnem == "BRA":
            if tgt:
                next_pc = tgt
        # conditional branches: follow fall-through for now (don't fork)

        pc = next_pc & 0xFFFF

    return result, io_polls, loop_hits

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
def main():
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    hex609 = os.path.join(base, "rom", "609.hex")
    hex608 = os.path.join(base, "rom", "608.hex")
    out    = os.path.join(base, "tools", "listing.txt")

    mem = bytearray(0x10000)
    load_hex(hex609, mem, base=0x7000)   # ROM2 (609): CPU addr 0x7000–0x77FF
    load_hex(hex608, mem, base=0x7800)   # ROM1 (608): CPU addr 0x7800–0x7FFF

    # Read vectors from end of ROM1 (608 is at 0x7800–0x7FFF)
    vec_nmi   = (mem[0x7FFC] << 8) | mem[0x7FFD]
    vec_reset = (mem[0x7FFE] << 8) | mem[0x7FFF]
    vec_irq   = (mem[0x7FF8] << 8) | mem[0x7FF9]
    vec_swi   = (mem[0x7FFA] << 8) | mem[0x7FFB]

    # Build label map
    labels = {
        vec_reset: "RESET",
        vec_nmi:   "NMI_ISR",
        vec_irq:   "IRQ_ISR",
        vec_swi:   "SWI_ISR",
        0x7000:    "ROM2_START",
        0x7800:    "ROM1_START",
        0x7FF8:    "VECTORS",
    }

    do_trace = "--trace" in sys.argv or "--full" not in sys.argv

    lines = []
    lines.append("=" * 78)
    lines.append("AtariFA — Middle Earth 608/609 — 6800 Disassembly")
    lines.append("=" * 78)
    lines.append(f"  ROM2 (609): 0x7000–0x77FF   ROM1 (608): 0x7800–0x7FFF")
    lines.append(f"  RESET={vec_reset:04X}  NMI={vec_nmi:04X}  IRQ={vec_irq:04X}  SWI={vec_swi:04X}")
    lines.append("")

    # ── Boot-path trace ───────────────────────────────────────────────────────
    lines.append("━" * 78)
    lines.append(f"BOOT PATH TRACE  (from RESET={vec_reset:04X}, call depth ≤ 6, max 8000 insn)")
    lines.append("━" * 78)

    trace_lines, io_polls, loop_hits = trace_boot(mem, vec_reset, labels)
    lines.extend(trace_lines)

    lines.append("")
    lines.append("━" * 78)
    lines.append("IO ACCESSES IN BOOT PATH")
    lines.append("━" * 78)
    for (pc, ea, mnem) in io_polls:
        lines.append(f"  {pc:04X}: {mnem}  ${ea:04X}  [{sym(ea)}]")

    if loop_hits:
        lines.append("")
        lines.append("━" * 78)
        lines.append("DETECTED TIGHT LOOPS (potential wait conditions)")
        lines.append("━" * 78)
        for (loop_pc, loop_seg, loop_io) in loop_hits:
            lines.append(f"  Loop back to {loop_pc:04X}")
            for (pc, ea, mnem) in loop_io:
                lines.append(f"    polls {pc:04X}: {mnem} ${ea:04X} [{sym(ea)}]")

    # ── Full linear disassembly ───────────────────────────────────────────────
    lines.append("")
    lines.append("━" * 78)
    lines.append("FULL DISASSEMBLY — ROM2 (609)  0x7000–0x77FF")
    lines.append("━" * 78)
    lines.extend(disasm_range(mem, 0x7000, 0x7800, labels))

    lines.append("")
    lines.append("━" * 78)
    lines.append("FULL DISASSEMBLY — ROM1 (608)  0x7800–0x7FFF")
    lines.append("━" * 78)
    lines.extend(disasm_range(mem, 0x7800, 0x8000, labels))

    # ── NMI ISR context ──────────────────────────────────────────────────────
    lines.append("")
    lines.append("━" * 78)
    lines.append(f"NMI ISR  context  @{vec_nmi:04X}  (±32 bytes)")
    lines.append("━" * 78)
    nmi_start = max(0x7000, vec_nmi - 4)
    nmi_end   = min(0x8000, vec_nmi + 60)
    lines.extend(disasm_range(mem, nmi_start, nmi_end, labels))

    txt = "\n".join(lines)
    with open(out, "w", encoding="utf-8") as f:
        f.write(txt)
    print(f"Written: {out}  ({len(lines)} lines)")

    # Quick summary to stdout
    print(f"\nVectors:  RESET=${vec_reset:04X}  NMI=${vec_nmi:04X}  IRQ=${vec_irq:04X}  SWI=${vec_swi:04X}")
    print(f"\nIO accesses in boot path ({len(io_polls)} total):")
    for (pc, ea, mnem) in io_polls:
        print(f"  {pc:04X}: {mnem}  ${ea:04X}  [{sym(ea)}]")
    if loop_hits:
        print(f"\nTight loops detected ({len(loop_hits)}):")
        for (lpc, _, lio) in loop_hits:
            print(f"  loop@{lpc:04X}  IO polls: {[(f'${ea:04X}[{sym(ea)}]') for _,ea,_ in lio]}")

if __name__ == "__main__":
    main()
