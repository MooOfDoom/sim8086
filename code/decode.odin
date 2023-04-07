package sim8086

// 8086 / 88
//
//           [      8086      ]
//           [     16-bit     ]      [     ]
// Inst ---> [ [    |    ] AX ] <--> [ Mem ]
//           [ [    |    ] BX ]      [     ]
//           [ [    |    ] CX ]
//           [            ... ]
//
// Inst. Decode
//
// "Mnemonic" - "MOV" "CPY"
//     D = S
// MOV AX, BX   "Operands"
//    8 bit       8 bit
// [100010|DW][MOD|REG|R/M]
//  6 bit  ..   2   3   3
//         11   11 000 001
//
// MOV AX, BX
// MOV AL, BL
// MOV AH, BH

import "core:fmt"
import "core:os"
import "core:slice"

Register :: struct {
	size:    u8,
	index:   u8,
	segment: bool,
}

Memory :: struct {
	size:           u8,
	formula:        u8,
	displacement:   i16,
	direct_address: bool,
	segment:        i8,
	explicit_size:  bool,
}

Immediate :: struct {
	size:  u8,
	value: i16,
}

Label :: struct {
	offset: i16,
}

Intersegment :: struct {
	cs: u16,
	ip: u16,
}

Operand :: union {
	Register,
	Memory,
	Immediate,
	Label,
	Intersegment,
}

Instruction :: struct {
	address:       int,
	mnemonic:      Mnemonic,
	dest:          Operand,
	source:        Operand,
	lock:          bool,
	rep:           bool,
	size:          u8,
}

make_register :: proc(reg: byte, w: byte) -> Register {
	return Register {
		size  = w + 1,
		index = reg,
	}
}

make_segment :: proc(seg: byte) -> Register {
	return Register {
		size    = 2,
		index   = seg,
		segment = true,
	}
}

make_memory :: proc(r_m: byte, w: byte, displacement: i16, direct_address: bool,
                    segment: i8 = -1, explicit_size: bool = false) -> Memory {
	return Memory {
		size           = w + 1,
		formula        = r_m,
		displacement   = displacement,
		direct_address = direct_address,
		segment        = segment,
		explicit_size  = explicit_size,
	}
}

make_memory_direct :: proc(address: u16, w: byte, segment: i8 = -1) -> Memory {
	return Memory {
		size           = w + 1,
		formula        = 0b110,
		displacement   = i16(address),
		direct_address = true,
		segment        = segment,
		explicit_size  = false,
	}
}

make_immediate :: proc(value: i16, w: byte) -> Immediate {
	return Immediate {
		size  = w + 1,
		value = value,
	}
}

make_label :: proc(offset: i16) -> Label {
	return Label {
		offset = offset,
	}
}

make_intersegment :: proc(cs: u16, ip: u16) -> Intersegment {
	return Intersegment {
		cs = cs,
		ip = ip,
	}
}

make_instruction :: proc(address: int, mnemonic: Mnemonic, dest: Operand, source: Operand, lock: bool,
                         rep: bool = false, size: u8 = 0) -> Instruction {
	return Instruction {
		address       = address,
		mnemonic      = mnemonic,
		dest          = dest,
		source        = source,
		lock          = lock,
		rep           = rep,
		size          = size,
	}
}

print_operand :: proc(fd: os.Handle, operand: Operand) {
	switch o in operand {
		case Register:
			if o.segment do fmt.fprint(fd, seg_names[o.index])
			else         do fmt.fprint(fd, reg_names[o.index + (o.size == 2 ? 8 : 0)])
		
		case Memory:
			if o.explicit_size do fmt.fprint(fd, o.size == 2 ? "word " : "byte ")
			if o.segment >= 0  do fmt.fprintf(fd, "%s:", seg_names[o.segment])
			if o.direct_address {
				fmt.fprintf(fd, "[%d]", o.displacement)
			} else if o.displacement == 0 {
				fmt.fprintf(fd, "[%s]", effective_address_calcs[o.formula])
			} else if o.displacement > 0 {
				fmt.fprintf(fd, "[%s + %d]", effective_address_calcs[o.formula], o.displacement)
			} else {
				fmt.fprintf(fd, "[%s - %d]", effective_address_calcs[o.formula], -o.displacement)
			}
		
		case Immediate:
			fmt.fprint(fd, o.value)
		
		case Label:
			fmt.fprintf(fd, "$%+d", o.offset + 2)
		
		case Intersegment:
			fmt.fprintf(fd, "%d:%d", o.cs, o.ip)
		
		case:
			// Do nothing
	}
}

print_instruction :: proc(fd: os.Handle, instruction: Instruction) {
	fmt.fprintf(fd, "%s%s%s",
	           instruction.lock ? "lock " : "",
	           instruction.rep  ? "rep "  : "",
	           mnemonic_strings[instruction.mnemonic])
	if instruction.size > 0 do fmt.fprint(fd, instruction.size == 2 ? "w" : "b")
	if instruction.dest != nil {
		fmt.fprint(fd, " ")
		print_operand(fd, instruction.dest)
	}
	if instruction.source != nil {
		if instruction.dest != nil do fmt.fprint(fd, ",")
		fmt.fprint(fd, " ")
		print_operand(fd, instruction.source)
	}
}

Mnemonic :: enum {
	NONE,
	MOV,
	PUSH,
	POP,
	XCHG,
	IN,
	OUT,
	XLAT,
	LEA,
	LDS,
	LES,
	LAHF,
	SAHF,
	PUSHF,
	POPF,
	ADD,
	ADC,
	INC,
	AAA,
	DAA,
	SUB,
	SBB,
	DEC,
	NEG,
	CMP,
	AAS,
	DAS,
	MUL,
	IMUL,
	AAM,
	DIV,
	IDIV,
	AAD,
	CBW,
	CWD,
	NOT,
	SHL,
	SHR,
	SAR,
	ROL,
	ROR,
	RCL,
	RCR,
	AND,
	TEST,
	OR,
	XOR,
	REP,
	MOVS,
	CMPS,
	SCAS,
	LODS,
	STOS,
	CALL,
	JMP,
	RET,
	JE,
	JL,
	JLE,
	JB,
	JBE,
	JP,
	JO,
	JS,
	JNE,
	JNL,
	JG,
	JNB,
	JA,
	JNP,
	JNO,
	JNS,
	LOOP,
	LOOPZ,
	LOOPNZ,
	JCXZ,
	INT,
	INTO,
	IRET,
	CLC,
	CMC,
	STC,
	CLD,
	STD,
	CLI,
	STI,
	HLT,
	WAIT,
	ESC,
}

mnemonic_strings := []string {
	"",
	"mov",
	"push",
	"pop",
	"xchg",
	"in",
	"out",
	"xlat",
	"lea",
	"lds",
	"les",
	"lahf",
	"sahf",
	"pushf",
	"popf",
	"add",
	"adc",
	"inc",
	"aaa",
	"daa",
	"sub",
	"sbb",
	"dec",
	"neg",
	"cmp",
	"aas",
	"das",
	"mul",
	"imul",
	"aam",
	"div",
	"idiv",
	"aad",
	"cbw",
	"cwd",
	"not",
	"shl",
	"shr",
	"sar",
	"rol",
	"ror",
	"rcl",
	"rcr",
	"and",
	"test",
	"or",
	"xor",
	"rep",
	"movs",
	"cmps",
	"scas",
	"lods",
	"stos",
	"call",
	"jmp",
	"ret",
	"je",
	"jl",
	"jle",
	"jb",
	"jbe",
	"jp",
	"jo",
	"js",
	"jne",
	"jnl",
	"jg",
	"jnb",
	"ja",
	"jnp",
	"jno",
	"jns",
	"loop",
	"loopz",
	"loopnz",
	"jcxz",
	"int",
	"into",
	"iret",
	"clc",
	"cmc",
	"stc",
	"cld",
	"std",
	"cli",
	"sti",
	"hlt",
	"wait",
	"esc",
}

Mod :: enum {
	no_displacement = 0b00,
	displacement_8  = 0b01,
	displacement_16 = 0b10,
	register        = 0b11,
}

AL :: 0b000
CL :: 0b001
DL :: 0b010
BL :: 0b011
AH :: 0b100
CH :: 0b101
DH :: 0b110
BH :: 0b111

AX :: 0b000
CX :: 0b001
DX :: 0b010
BX :: 0b011
SP :: 0b100
BP :: 0b101
SI :: 0b110
DI :: 0b111

reg_names := []string {
	// W = 0
	"al",
	"cl",
	"dl",
	"bl",
	"ah",
	"ch",
	"dh",
	"bh",
	
	// W = 1
	"ax",
	"cx",
	"dx",
	"bx",
	"sp",
	"bp",
	"si",
	"di",
}

seg_names := []string {
	"es",
	"cs",
	"ss",
	"ds",
}

effective_address_calcs := []string {
	"bx + si",
	"bx + di",
	"bp + si",
	"bp + di",
	"si",
	"di",
	"bp",
	"bx",
}

all_ones := []Mnemonic {
	.INC,
	.DEC,
	.CALL,
	.CALL,
	.JMP,
	.JMP,
	.PUSH,
}

flags_ops := []Mnemonic {
	.PUSHF,
	.POPF,
	.SAHF,
	.LAHF,
}

arithmetic_ops := []Mnemonic {
	.ADD,
	.OR,
	.ADC,
	.SBB,
	.AND,
	.SUB,
	.XOR,
	.CMP,
}

adjust_a_s_ops := []Mnemonic {
	.DAA,
	.DAS,
	.AAA,
	.AAS,
}

unary_ops := []Mnemonic {
	.TEST,
	.NONE,
	.NOT,
	.NEG,
	.MUL,
	.IMUL,
	.DIV,
	.IDIV,
}

logic_ops := []Mnemonic {
	.ROL,
	.ROR,
	.RCL,
	.RCR,
	.SHL,
	.SHR,
	.NONE,
	.SAR,
}

string_ops := []Mnemonic {
	.NONE,
	.NONE,
	.MOVS,
	.CMPS,
	.NONE,
	.STOS,
	.LODS,
	.SCAS,
}

conditional_jmps := []Mnemonic {
	.JO,
	.JNO,
	.JB,
	.JNB,
	.JE,
	.JNE,
	.JBE,
	.JA,
	.JS,
	.JNS,
	.JP,
	.JNP,
	.JL,
	.JNL,
	.JLE,
	.JG,
}

loops := []Mnemonic {
	.LOOPNZ,
	.LOOPZ,
	.LOOP,
	.JCXZ,
}

Decoder :: struct {
	binary_instructions: []byte,
	address:             int,
	error:               bool,
}

decode_error :: proc(fmt_str: string, args: ..any) {
	fmt.fprintf(os.stderr, fmt_str, ..args)
}

has_bytes :: proc(decoder: ^Decoder) -> bool {
	return decoder.address < len(decoder.binary_instructions)
}

read :: proc(decoder: ^Decoder, $T: typeid) -> T {
	if decoder.address + size_of(T) > len(decoder.binary_instructions) {
		decoder.error = true
		return 0
	}
	result := (cast(^T)&decoder.binary_instructions[decoder.address])^
	decoder.address += size_of(T)
	return result
}

read_mod_reg_r_m :: proc(decoder: ^Decoder) -> (mod: Mod, reg: byte, r_m: byte) {
	instruction_byte := read(decoder, byte)
	if decoder.error {
		return
	}
	mod = Mod(instruction_byte >> 6)
	reg = (instruction_byte & 0b00111000) >> 3
	r_m =  instruction_byte & 0b00000111
	return
}

NO_SIZE :: 2

effective_address_calculation :: proc(decoder: ^Decoder, mod: Mod, r_m: byte, w: byte = NO_SIZE, segment: i8 = -1) -> Memory {
	disp: i16
	direct_address := mod == .no_displacement && r_m == 0b110
	if mod == .displacement_8 {
		disp = i16(read(decoder, i8));
	} else if mod == .displacement_16 || direct_address {
		disp = read(decoder, i16);
	}
	if decoder.error {
		decode_error("Missing displacement for effective address calculation\n")
		return {}
	}
	
	return make_memory(r_m, w, disp, direct_address, segment, w != NO_SIZE)
}

// MOV
is_mov_reg_r_m :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b10001000
}
is_mov_r_m_imm :: proc(opcode: byte) -> bool {
	return opcode & 0b11111110 == 0b11000110
}
is_mov_reg_imm :: proc(opcode: byte) -> bool {
	return opcode & 0b11110000 == 0b10110000
}
is_mov_acc_mem :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b10100000
}
is_mov_r_m_seg :: proc(opcode: byte) -> bool {
	return opcode & 0b11111101 == 0b10001100
}

// PUSH, POP
is_all_ones :: proc(opcode: byte) -> bool { // Also handles register/memory variants of INC, DEC, CALL, JMP
	return opcode & 0b11111111 == 0b11111111
}
is_pop_r_m :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b10001111
}
is_push_pop_reg :: proc(opcode: byte) -> bool {
	return opcode & 0b11110000 == 0b01010000
}
is_push_pop_seg :: proc(opcode: byte) -> bool {
	return opcode & 0b11100110 == 0b00000110
}

// XCHG
is_xchg_reg_r_m :: proc(opcode: byte) -> bool {
	return opcode & 0b11111110 == 0b10000110
}
is_xchg_acc_reg :: proc(opcode: byte) -> bool {
	return opcode & 0b11111000 == 0b10010000
}

// IN, OUT
is_in_out_fixed :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b11100100
}
is_in_out_variable :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b11101100
}

// XLAT
is_xlat :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11010111
}

// LEA
is_lea :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b10001101
}

// LDS
is_lds :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11000101
}

// LES
is_les :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11000100
}

// LAHF, SAHF, PUSHF, POPF
is_flags :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b10011100
}

// ADD, ADC, SUB, SBB, CMP, AND, OR, XOR
is_arithmetic_op_reg_r_m :: proc(opcode: byte) -> bool {
	return opcode & 0b11000100 == 0b00000000
}
is_arithmetic_op_r_m_imm :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b10000000
}
is_arithmetic_op_acc_imm :: proc(opcode: byte) -> bool {
	return opcode & 0b11000110 == 0b00000100
}

// INC, DEC
is_inc_dec_r_m :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11111110
}
is_inc_dec_reg :: proc(opcode: byte) -> bool {
	return opcode & 0b11110000 == 0b01000000
}

// AAA, DAA, AAS, DAS
is_adjust_a_s :: proc(opcode: byte) -> bool {
	return opcode & 0b11100111 == 0b00100111
}

// AAM, AAD
is_adjust_m_d :: proc(opcode: byte) -> bool {
	return opcode & 0b11111110 == 0b11010100
}

// CBW, CWD
is_convert :: proc(opcode: byte) -> bool {
	return opcode & 0b11111110 == 0b10011000
}

// NEG, MUL, IMUL, DIV, IDIV, NOT, TEST
is_unary :: proc(opcode: byte) -> bool {
	return opcode & 0b11111110 == 0b11110110
}

// SHL, SHR, SAR, ROL, ROR, RCL, RCR
is_logic :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b11010000
}

// TEST
is_test_reg_r_m :: proc(opcode: byte) -> bool {
	return opcode & 0b11111110 == 0b10000100
}
is_test_acc_imm :: proc(opcode: byte) -> bool {
	return opcode & 0b11111110 == 0b10101000
}

// REP
is_rep :: proc(opcode: byte) -> bool {
	return opcode & 0b11111110 == 0b11110010
}

// MOVS, CMPS, SCAS, LODS, STOS
is_string_op :: proc(opcode: byte) -> bool {
	return opcode & 0b11110000 == 0b10100000 // NOTE: Assumes MOV and TEST have been filtered out!
}

// CALL, JMP
is_call_jmp_direct :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b11101000
}
is_call_direct_interseg :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b10011010
}

// RET
is_ret :: proc(opcode: byte) -> bool {
	return opcode & 0b11110110 == 0b11000010
}

// JE, JL, JLE, JB, JBE, JP, JO, JS, JNE, JNL, JG, JNB, JA, JNP, JNP, JNS
is_conditional_jmp :: proc(opcode: byte) -> bool {
	return opcode & 0b11110000 == 0b01110000
}

// LOOP, LOOPZ, LOOPNZ, JCXZ
is_loop_or_jcxz :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b11100000
}

// INT, INTO, IRET
is_interrupt :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b11001100
}

// CLC, CMC, STC, CLD, STD, CLI, STI, HLT, WAIT
is_clc :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11111000
}
is_cmc :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11110101
}
is_stc :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11111001
}
is_cld :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11111100
}
is_std :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11111101
}
is_cli :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11111010
}
is_sti :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11111011
}
is_hlt :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11110100
}
is_wait :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b10011011
}

// ESC
is_esc :: proc(opcode: byte) -> bool {
	return opcode & 0b11111000 == 0b11011000
}

// LOCK prefix
is_lock :: proc(opcode: byte) -> bool {
	return opcode & 0b11111111 == 0b11110000
}

// SEGMENT prefix
is_segment :: proc(opcode: byte) -> bool {
	return opcode & 0b11100111 == 0b00100110
}

decode_instruction :: proc(decoder: ^Decoder) -> (instruction: Instruction, success: bool) {
	success = false
	
	lock := false
	segment: i8 = -1
	
	for !decoder.error && has_bytes(decoder) {
		address := decoder.address
		opcode  := read(decoder, byte)
		d       := (opcode & 0b00000010) >> 1
		w       :=  opcode & 0b00000001
	
		if is_mov_reg_r_m(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for mov register/memory to/from register\n")
				break
			}
			
			dest, source: Operand
			if mod == .register {
				if d == 0 {
					dest   = make_register(r_m, w)
					source = make_register(reg, w)
				} else {
					dest   = make_register(reg, w)
					source = make_register(r_m, w)
				}
			} else {
				mem := effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
				
				if d == 0 {
					dest = mem
					source = make_register(reg, w)
				} else {
					dest = make_register(reg, w)
					source = mem
				}
			}
			
			instruction = make_instruction(address, .MOV, dest, source, lock)
		} else if is_mov_r_m_imm(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for mov immediate to register/memory\n")
				break
			}
			
			if reg != 0b000 {
				decoder.error = true
				decode_error("Illegal register field in mov immediate to register/memory\n")
				break
			}
			
			dest: Operand
			if mod == .register {
				dest = make_register(reg, w)
			} else {
				dest = effective_address_calculation(decoder, mod, r_m, w, segment)
				if decoder.error {
					break
				}
			}
			
			imm: i16
			if w == 1 {
				imm = read(decoder, i16)
			} else {
				imm = i16(read(decoder, i8))
			}
			if decoder.error {
				decode_error("Missing immediate for mov immediate to register/memory")
				break
			}
			
			instruction = make_instruction(address, .MOV, dest, make_immediate(imm, w), lock)
		} else if is_mov_reg_imm(opcode) {
			w    = (opcode & 0b0001000) >> 3
			reg :=  opcode & 0b0000111
			imm: i16
			if w == 1 {
				imm = read(decoder, i16)
			} else {
				imm = i16(read(decoder, i8))
			}
			if decoder.error {
				decode_error("Missing immediate for mov immediate to register\n")
				break
			}
			
			instruction = make_instruction(address, .MOV, make_register(reg, w), make_immediate(imm, w), lock)
		} else if is_mov_acc_mem(opcode) {
			addr := read(decoder, u16)
			if decoder.error {
				decode_error("Missing memory address for mov memory %s accumulator\n", d == 0 ? "to" : "from")
				break
			}
			
			acc := make_register(AX, w)
			mem := make_memory_direct(addr, w, segment)
			if d == 0 {
				instruction = make_instruction(address, .MOV, acc, mem, lock)
			} else {
				instruction = make_instruction(address, .MOV, mem, acc, lock)
			}
		} else if is_mov_r_m_seg(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for mov register/memory to/from segment register\n")
				break
			}
			
			if reg > 0b011 {
				decoder.error = true
				decode_error("Illegal segment register in mov register/memory to/from segment register\n")
				break
			}
			
			dest, source: Operand
			if mod == .register {
				if d == 0 {
					dest   = make_register(r_m, 1)
					source = make_segment(reg)
				} else {
					dest   = make_segment(reg)
					source = make_register(r_m, 1)
				}
			} else {
				mem := effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
				
				if d == 0 {
					dest   = mem
					source = make_segment(reg)
				} else {
					dest   = make_segment(reg)
					source = mem
				}
			}
			
			instruction = make_instruction(address, .MOV, dest, source, lock)
		} else if is_all_ones(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for 11111111 instruction\n")
				break
			}
			
			type := reg
			if type == 0b111 {
				decoder.error = true
				decode_error("Illegal instruction: %b with mod/reg/rm field 0bxx111xxx\n", opcode)
				break
			}
			
			source: Operand
			if mod == .register {
				source = make_register(r_m, w)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, w, segment)
				if decoder.error {
					break
				}
			}
			
			if type == 0b011 || type == 0b101 { // Intersegment call or jmp
				// TODO: Support call far and jmp far
				// instruction =  fmt.aprintf("%s far %s", all_ones[type], source))
				if mem, ok := source.(Memory); ok {
					mem.explicit_size = false
				}
				instruction = make_instruction(address, all_ones[type], nil, source, lock)
			} else {
				instruction = make_instruction(address, all_ones[type], nil, source, lock)
			}
		} else if is_pop_r_m(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for pop from register/memory\n")
				break
			}
			
			if reg != 0b000 {
				decoder.error = true
				decode_error("Illegal register field in pop from register/memory\n")
				break
			}
			
			source: Operand
			if mod == .register {
				source = make_register(r_m, w)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, w, segment)
				if decoder.error {
					break
				}
			}
			
			instruction = make_instruction(address, .POP, nil, source, lock)
		} else if is_push_pop_reg(opcode) {
			type := (opcode & 0b00001000) >> 3
			reg  :=  opcode & 0b00000111
			
			instruction = make_instruction(address, type == 1 ? .POP : .PUSH, nil, make_register(reg, 1), lock)
		} else if is_push_pop_seg(opcode) {
			type :=  opcode & 0b00000001
			seg  := (opcode & 0b00011000) >> 3
			
			instruction = make_instruction(address, type == 1 ? .POP : .PUSH, nil, make_segment(seg), lock)
		} else if is_xchg_reg_r_m(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for xchg register/memory with register\n")
				break
			}
			
			source: Operand
			if mod == .register {
				source = make_register(r_m, w)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
			}
			
			instruction = make_instruction(address, .XCHG, make_register(reg, w), source, lock)
		} else if is_xchg_acc_reg(opcode) {
			reg := opcode & 0b00000111
			
			instruction = make_instruction(address, .XCHG, make_register(AX, 1), make_register(reg, 1), lock)
		} else if is_in_out_fixed(opcode) {
			imm := i16(read(decoder, u8))
			if decoder.error {
				decode_error("Missing port for %s with fixed port\n", d == 1 ? "out" : "in")
				break
			}
			
			if d == 1 {
				instruction = make_instruction(address, .OUT, make_immediate(imm, w), make_register(AX, w), lock)
			} else {
				instruction = make_instruction(address, .IN, make_register(AX, w), make_immediate(imm, w), lock)
			}
		} else if is_in_out_variable(opcode) {
			if d == 1 {
				instruction = make_instruction(address, .OUT, make_register(DX, 1), make_register(AX, w), lock)
			} else {
				instruction = make_instruction(address, .IN, make_register(AX, w), make_register(DX, 1), lock)
			}
		} else if is_xlat(opcode) {
			instruction = make_instruction(address, .XLAT, nil, nil, lock)
		} else if is_lea(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for lea\n")
				break
			}
			
			source: Operand
			if mod == .register { // This probably should never be the case???
				source = make_register(r_m, 1)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
			}
			
			instruction = make_instruction(address, .LEA, make_register(reg, 1), source, lock)
		} else if is_lds(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for lds\n")
				break
			}
			
			source: Operand
			if mod == .register { // This probably should never be the case???
				source = make_register(r_m, 1)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
			}
			
			instruction = make_instruction(address, .LDS, make_register(reg, 1), source, lock)
		} else if is_les(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for les\n")
				break
			}
			
			source: Operand
			if mod == .register { // This probably should never be the case???
				source = make_register(r_m, 1)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
			}
			
			instruction = make_instruction(address, .LES, make_register(reg, 1), source, lock)
		} else if is_flags(opcode) {
			type := opcode & 0b00000011
			
			instruction = make_instruction(address, flags_ops[type], nil, nil, lock)
		} else if is_arithmetic_op_reg_r_m(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for arithmetic op register/memory with register to either\n")
				break
			}
			
			op := (opcode & 0b00111000) >> 3
			
			dest, source: Operand
			if mod == .register {
				if d == 0 {
					dest   = make_register(r_m, w)
					source = make_register(reg, w)
				} else {
					dest   = make_register(reg, w)
					source = make_register(r_m, w)
				}
			} else {
				mem := effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
				
				if d == 0 {
					dest = mem
					source = make_register(reg, w)
				} else {
					dest = make_register(reg, w)
					source = mem
				}
			}
			
			instruction = make_instruction(address, arithmetic_ops[op], dest, source, lock)
		} else if is_arithmetic_op_r_m_imm(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for arithmetic op register/memory with register to either\n")
				break
			}
			
			s := (opcode & 0b00000010) >> 1
			
			dest: Operand
			if mod == .register {
				dest = make_register(r_m, w)
			} else {
				dest = effective_address_calculation(decoder, mod, r_m, w, segment)
				if decoder.error {
					break
				}
			}
			
			imm: i16
			if s == 0 && w == 1 {
				imm = read(decoder, i16)
			} else if s == 1 {
				imm = i16(read(decoder, i8))
			} else {
				imm = i16(read(decoder, u8))
			}
			if decoder.error {
				decode_error("Missing immediate for arithmetic op immediate to register/memory")
				break
			}
			
			instruction = make_instruction(address, arithmetic_ops[reg], dest, make_immediate(imm, w), lock)
		} else if is_arithmetic_op_acc_imm(opcode) {
			op := (opcode & 0b00111000) >> 3
			
			imm: i16
			if w == 1 {
				imm = read(decoder, i16)
			} else {
				imm = i16(read(decoder, i8))
			}
			if decoder.error {
				decode_error("Missing immediate for mov immediate to register\n")
				break
			}
			
			instruction = make_instruction(address, arithmetic_ops[op], make_register(AX, w), make_immediate(imm, w), lock)
		} else if is_inc_dec_r_m(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for inc or dec register/memory\n")
				break
			}
			
			if reg > 0b001 {
				decoder.error = true
				decode_error("Illegal register field in inc or dec register/memory\n")
				break
			}
			
			dest: Operand
			if mod == .register {
				dest = make_register(r_m, w)
			} else {
				dest = effective_address_calculation(decoder, mod, r_m, w, segment)
				if decoder.error {
					break
				}
			}
			
			instruction = make_instruction(address, reg == 0b000 ? .INC : .DEC, dest, nil, lock)
		} else if is_inc_dec_reg(opcode) {
			is_dec := (opcode & 0b00001000) >> 3
			reg    :=  opcode & 0b00000111
			
			instruction = make_instruction(address, is_dec == 1 ? .DEC : .INC, make_register(reg, 1), nil, lock)
		} else if is_adjust_a_s(opcode) {
			type := (opcode & 0b00011000) >> 3
			
			instruction = make_instruction(address, adjust_a_s_ops[type], nil, nil, lock)
		} else if is_adjust_m_d(opcode) {
			is_aad := opcode & 0b00000001
			
			next_byte := read(decoder, byte)
			if next_byte != 0b00001010 {
				decoder.error = true
				decode_error("Illegal second byte in %s\n", is_aad == 1 ? "aad" : "aam")
				break
			}
			
			instruction = make_instruction(address, is_aad == 1 ? .AAD : .AAM, nil, nil, lock)
		} else if is_convert(opcode) {
			is_cwd := opcode & 0b00000001
			
			instruction = make_instruction(address, is_cwd == 1 ? .CWD : .CBW, nil, nil, lock)
		} else if is_unary(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for test, not, neg, mul, imul, div, or idiv\n")
				break
			}
			
			if reg == 0b001 {
				decoder.error = true
				decode_error("Illegal register field in test, not, neg, mul, imul, div, or idiv\n")
				break
			}
			
			dest: Operand
			if mod == .register {
				dest = make_register(r_m, w)
			} else {
				dest = effective_address_calculation(decoder, mod, r_m, w, segment)
				if decoder.error {
					break
				}
			}
			
			if reg == 0b000 {
				imm: i16
				if w == 1 {
					imm = read(decoder, i16)
				} else {
					imm = i16(read(decoder, i8))
				}
				if decoder.error {
					decode_error("Missing immediate for test immediate data and register/memory\n")
					break
				}
				
				instruction = make_instruction(address, .TEST, dest, make_immediate(imm, w), lock)
			} else {
				instruction = make_instruction(address, unary_ops[reg], dest, nil, lock)
			}
		} else if is_logic(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for shl, shr, sar, rol, ror, rcl, or rcr\n")
				break
			}
			
			if reg == 0b110 {
				decoder.error = true
				decode_error("Illegal register field in shl, shr, sar, rol, ror, rcl, or rcr\n")
				break
			}
			
			dest: Operand
			if mod == .register {
				dest = make_register(r_m, w)
			} else {
				dest = effective_address_calculation(decoder, mod, r_m, w, segment)
				if decoder.error {
					break
				}
			}
			
			v := d
			instruction = make_instruction(address, logic_ops[reg], dest,
			                                     v == 1 ? Operand(make_register(CL, 0)) : Operand(make_immediate(1, 0)), lock)
		} else if is_test_reg_r_m(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for test register/memory and register\n")
				break
			}
			
			dest: Operand
			if mod == .register {
				dest = make_register(r_m, w)
			} else {
				dest = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
			}
			
			instruction = make_instruction(address, .TEST, dest, make_register(reg, w), lock)
		} else if is_test_acc_imm(opcode) {
			imm: i16
			if w == 1 {
				imm = read(decoder, i16)
			} else {
				imm = i16(read(decoder, i8))
			}
			if decoder.error {
				decode_error("Missing immediate for test immediate data and register/memory\n")
				break
			}
			
			instruction = make_instruction(address, .TEST, make_register(AX, w), make_immediate(imm, w), lock)
		} else if is_rep(opcode) {
			z := w
			string_op := read(decoder, byte)
			if decoder.error {
				decode_error("Missing string operation after rep\n")
				break
			}
			
			w     =  string_op & 0b00000001
			type := (string_op & 0b00001110) >> 1
			if !is_string_op(string_op) || type < 0b010 || type == 0b100 {
				decoder.error = true
				decode_error("Instruction after rep is not a string operation\n")
				break
			}
			
			// TODO: Support z != 1
			instruction = make_instruction(address, string_ops[type], nil, nil, lock, true, w + 1)
		} else if is_string_op(opcode) {
			type := (opcode & 0b00001110) >> 1
			// NOTE: Types that are not string ops have been filtered out by this point.
			
			instruction = make_instruction(address, string_ops[type], nil, nil, lock, false, w + 1)
		} else if is_call_jmp_direct(opcode) {
			type := opcode & 0b000000011
			mnemonic: Mnemonic = type == 0b00 ? .CALL : .JMP
			
			if type != 0b10 {
				disp: i16
				if type == 0b11 {
					disp = i16(read(decoder, i8))
				} else {
					disp = read(decoder, i16)
				}
				if decoder.error {
					decode_error("Missing IP-inc for %s\n", mnemonic_strings[mnemonic])
					break
				}
				
				instruction = make_instruction(address, mnemonic, make_label(disp), nil, lock)
			} else {
				ip := read(decoder, u16)
				cs := read(decoder, u16)
				if decoder.error {
					decode_error("Missing some of IP-lo, IP-hi, CS-lo, CS-hi bytes from jmp direct intersegment\n")
					break
				}
				
				instruction = make_instruction(address, .JMP, make_intersegment(cs, ip), nil, lock)
			}
		} else if is_call_direct_interseg(opcode) {
			ip := read(decoder, u16)
			cs := read(decoder, u16)
			if decoder.error {
				decode_error("Missing some of IP-lo, IP-hi, CS-lo, CS-hi bytes from call direct intersegment\n")
				break
			}
			
			instruction = make_instruction(address, .CALL, make_intersegment(cs, ip), nil, lock)
		} else if is_ret(opcode) {
			// TODO: Within segment vs intersegment?
			if w == 0 {
				imm := read(decoder, i16)
				if decoder.error {
					decode_error("Missing immediate for ret adding immediate to sp\n")
					break
				}
				
				instruction = make_instruction(address, .RET, make_immediate(imm, 1), nil, lock)
			} else {
				instruction = make_instruction(address, .RET, nil, nil, lock)
			}
		} else if is_interrupt(opcode) {
			type := opcode & 0b00000011
			if type == 0b00 {
				instruction = make_instruction(address, .INT, make_immediate(3, 0), nil, lock)
			} else if type == 0b01 {
				imm := i16(read(decoder, byte))
				if decoder.error {
					decode_error("Missing immediate for int with type specified\n")
					break
				}
				
				instruction = make_instruction(address, .INT, make_immediate(imm, 0), nil, lock)
			} else if type == 0b10 {
				instruction = make_instruction(address, .INTO, nil, nil, lock)
			} else{
				instruction = make_instruction(address, .IRET, nil, nil, lock)
			}
		} else if is_clc(opcode) {
			instruction = make_instruction(address, .CLC, nil, nil, lock)
		} else if is_cmc(opcode) {
			instruction = make_instruction(address, .CMC, nil, nil, lock)
		} else if is_stc(opcode) {
			instruction = make_instruction(address, .STC, nil, nil, lock)
		} else if is_cld(opcode) {
			instruction = make_instruction(address, .CLD, nil, nil, lock)
		} else if is_std(opcode) {
			instruction = make_instruction(address, .STD, nil, nil, lock)
		} else if is_cli(opcode) {
			instruction = make_instruction(address, .CLI, nil, nil, lock)
		} else if is_sti(opcode) {
			instruction = make_instruction(address, .STI, nil, nil, lock)
		} else if is_hlt(opcode) {
			instruction = make_instruction(address, .HLT, nil, nil, lock)
		} else if is_wait(opcode) {
			instruction = make_instruction(address, .WAIT, nil, nil, lock)
		} else if is_esc(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for esc\n")
				break
			}
			
			code := ((opcode & 0b00000111) << 3) | reg
			source: Operand
			if mod == .register {
				source = make_register(r_m, 1)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment) // Unsure about size
				if decoder.error {
					break
				}
			}
			
			instruction = make_instruction(address, .ESC, make_immediate(i16(code), 0), source, lock)
		} else if is_conditional_jmp(opcode) || is_loop_or_jcxz(opcode) {
			mnemonic: Mnemonic
			if is_conditional_jmp(opcode) {
				type := opcode & 0b00001111
				mnemonic = conditional_jmps[type]
			} else {
				type := opcode & 0b00000011
				mnemonic = loops[type]
			}
			
			disp := i16(read(decoder, i8))
			if decoder.error {
				decode_error("Missing short label for %s\n", mnemonic_strings[mnemonic])
				break
			}
			
			instruction = make_instruction(address, mnemonic, make_label(disp), nil, lock)
		} else if is_lock(opcode) {
			lock = true
			continue
		} else if is_segment(opcode) {
			segment = i8((opcode & 0b00011000) >> 3)
			continue
		} else {
			decode_error("Unhandled instruction: %08b\n", opcode)
			decoder.error = true
			break
		}
		
		success = true
		break
	}
	
	return
}

disasm8086 :: proc(binary_instructions: []byte) -> (instructions: []Instruction, success: bool) {
	output_buf: [dynamic]Instruction
	decoder := &Decoder{binary_instructions = binary_instructions}
	
	for !decoder.error && has_bytes(decoder) {
		if instruction, ok := decode_instruction(decoder); ok {
			append(&output_buf, instruction)
		}
	}
	
	instructions = output_buf[:]
	success = !decoder.error
	return
}