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

main :: proc() {
	if len(os.args) == 2 {
		if binary_instructions, ok := os.read_entire_file(os.args[1]); ok {
			mnemonic_instructions, labels, ok := disasm8086(binary_instructions)
			fmt.printf("; %s\n", os.args[1])
			fmt.println("bits 16")
			label_index := 0
			for line, index in mnemonic_instructions {
				if label_index < len(labels) && labels[label_index].instruction_index == index {
					fmt.printf("label_%d:\n", labels[label_index].index)
					label_index += 1
				}
				fmt.println(line)
			}
			if !ok {
				fmt.printf("; Failed beyond this point\n")
			}
		} else {
			fmt.fprintf(os.stderr, "Could not read file %v\n", os.args[1])
		}
	} else {
		fmt.fprintf(os.stderr, "Usage: %v <binary-file>\n", os.args[0])
	}
}

debug_printf :: proc(fmt_str: string, args: ..any) {
	fmt.fprintf(os.stderr, fmt_str, ..args)
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

all_ones := []string {
	"inc",
	"dec",
	"call",
	"call",
	"jmp",
	"jmp",
	"push",
}

flags_ops := []string {
	"pushf",
	"popf",
	"sahf",
	"lahf",
}

arithmetic_ops := []string {
	"add",
	"or",
	"adc",
	"sbb",
	"and",
	"sub",
	"xor",
	"cmp",
}

adjust_a_s_ops := []string {
	"daa",
	"das",
	"aaa",
	"aas",
}

unary_ops := []string {
	"test",
	"",
	"not",
	"neg",
	"mul",
	"imul",
	"div",
	"idiv",
}

logic_ops := []string {
	"rol",
	"ror",
	"rcl",
	"rcr",
	"shl",
	"shr",
	"",
	"sar",
}

string_ops := []string {
	"",
	"",
	"movs",
	"cmps",
	"",
	"stds",
	"lods",
	"scas",
}

conditional_jmps := []string {
	"jo",
	"jno",
	"jb",
	"jnb",
	"je",
	"jne",
	"jbe",
	"ja",
	"js",
	"jns",
	"jp",
	"jnp",
	"jl",
	"jnl",
	"jle",
	"jg",
}

loops := []string {
	"loopnz",
	"loopz",
	"loop",
	"jcxz",
}

Label :: struct {
	index:             int,
	instruction_index: int,
}

Decoder :: struct {
	binary_instructions:   []byte,
	labels_buf:            [dynamic]Label,
	instruction_addresses: [dynamic]int,
	address_to_label:      map[int]^Label,
	index:                 int,
	error:                 bool,
}

decode_error :: proc(fmt_str: string, args: ..any) {
	fmt.fprintf(os.stderr, fmt_str, ..args)
}

has_bytes :: proc(decoder: ^Decoder) -> bool {
	return decoder.index < len(decoder.binary_instructions)
}

read :: proc(decoder: ^Decoder, $T: typeid) -> T {
	if decoder.index + size_of(T) > len(decoder.binary_instructions) {
		decoder.error = true
		return 0
	}
	result := (cast(^T)&decoder.binary_instructions[decoder.index])^
	decoder.index += size_of(T)
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

cleanup :: proc(decoder: ^Decoder) {
	delete(decoder.instruction_addresses)
	delete(decoder.address_to_label)
}

register_name :: proc(reg: byte, w: byte) -> string {
	return reg_names[reg | (w << 3)]
}

NO_SIZE :: 2

effective_address_calculation :: proc(decoder: ^Decoder, mod: Mod, r_m: byte, w: byte = NO_SIZE, segment: int = -1) -> string {
	disp: i16
	direct_address := mod == .no_displacement && r_m == 0b110
	if mod == .displacement_8 {
		disp = i16(read(decoder, i8));
	} else if mod == .displacement_16 || direct_address {
		disp = read(decoder, i16);
	}
	if decoder.error {
		decode_error("Missing displacement for effective address calculation\n")
		return "?"
	}
	
	size := w < NO_SIZE ? (w == 1) ? "word " : "byte " : ""
	seg_str := segment >= 0 ? seg_names[segment] : ""
	seg_sep := segment >= 0 ? ":"                : ""
	
	result: string
	if direct_address {
		result = fmt.tprintf("%s%s%s[%d]", size, seg_str, seg_sep, disp)
	} else if mod == .no_displacement || disp == 0 {
		result = fmt.tprintf("%s%s%s[%s]", size, seg_str, seg_sep, effective_address_calcs[r_m])
	} else if disp > 0 {
		result = fmt.tprintf("%s%s%s[%s + %d]", size, seg_str, seg_sep, effective_address_calcs[r_m], disp)
	} else {
		result = fmt.tprintf("%s%s%s[%s - %d]", size, seg_str, seg_sep, effective_address_calcs[r_m], -disp)
	}
	return result
}

update_labels :: proc(decoder: ^Decoder, instruction_index: int) {
	append(&decoder.instruction_addresses, decoder.index)
	if label, ok := decoder.address_to_label[decoder.index]; ok {
		label.instruction_index = instruction_index
	}
}

get_or_create_label :: proc(decoder: ^Decoder, disp: int, mnemonic: string) -> ^Label {
	target_address := decoder.index + disp
	label, ok := decoder.address_to_label[target_address]
	if !ok {
		append(&decoder.labels_buf, Label{
			index             = len(decoder.labels_buf),
			instruction_index = -1,
		})
		label = &decoder.labels_buf[len(decoder.labels_buf) - 1]
		decoder.address_to_label[target_address] = label
		if target_address < decoder.index {
			index := len(decoder.instruction_addresses) - 1
			address := decoder.instruction_addresses[index]
			for index > 0 && address > target_address {
				index -= 1
				address = decoder.instruction_addresses[index]
			}
			if address != target_address {
				decoder.error = true
				decode_error("Cannot find location for short label for %s (disp=%d, address=%d)", mnemonic, disp, target_address)
			}
			
			label.instruction_index = index
		}
	}
	return label
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

// MOVS, CMPS, SCAS, LODS, STDS
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

disasm8086 :: proc(binary_instructions: []byte) -> (mnemonic_instructions: []string, labels: []Label, success: bool) {
	output_buf: [dynamic]string
	decoder := &Decoder{binary_instructions = binary_instructions}
	defer cleanup(decoder)
	
	lock    := false
	segment := -1
	
	// debug_printf("\n%s\n\n", os.args[1])
	for !decoder.error && has_bytes(decoder) {
		update_labels(decoder, len(output_buf))
		opcode := read(decoder, byte)
		// debug_printf("%08b\n", opcode)
		d := (opcode & 0b00000010) >> 1
		w :=  opcode & 0b00000001
		
		if is_mov_reg_r_m(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for mov register/memory to/from register\n")
				break
			}
			
			dest, source: string
			if mod == .register {
				if d == 0 {
					dest   = register_name(r_m, w)
					source = register_name(reg, w)
				} else {
					dest   = register_name(reg, w)
					source = register_name(r_m, w)
				}
			} else {
				mem := effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
				
				if d == 0 {
					dest = mem
					source = register_name(reg, w)
				} else {
					dest = register_name(reg, w)
					source = mem
				}
			}
			
			append(&output_buf, fmt.aprintf("mov %s, %s", dest, source))
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
			
			dest: string
			if mod == .register {
				dest = register_name(reg, w)
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
			
			append(&output_buf, fmt.aprintf("mov %s, %d", dest, imm))
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
			
			append(&output_buf, fmt.aprintf("mov %s, %d", register_name(reg, w), imm))
		} else if is_mov_acc_mem(opcode) {
			addr := read(decoder, u16)
			
			if d == 0 {
				append(&output_buf, fmt.aprintf("mov %s, [%d]", register_name(AX, w), addr))
			} else {
				append(&output_buf, fmt.aprintf("mov [%d], %s", addr, register_name(AX, w)))
			}
		} else if is_mov_r_m_seg(opcode) {
			addr := read(decoder, u16)
			
			if d == 0 {
				append(&output_buf, fmt.aprintf("mov %s, [%d]", register_name(AX, w), addr))
			} else {
				append(&output_buf, fmt.aprintf("mov [%d], %s", addr, register_name(AX, w)))
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
			
			dest, source: string
			if mod == .register {
				if d == 0 {
					dest   = register_name(r_m, 1)
					source = seg_names[reg]
				} else {
					dest   = seg_names[reg]
					source = register_name(r_m, 1)
				}
			} else {
				mem := effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
				
				if d == 0 {
					dest   = mem
					source = seg_names[reg]
				} else {
					dest   = seg_names[reg]
					source = mem
				}
			}
			
			append(&output_buf, fmt.aprintf("mov %s, %s", dest, source))
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
			
			source: string
			if mod == .register {
				source = register_name(r_m, w)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, w, segment)
				if decoder.error {
					break
				}
			}
			
			append(&output_buf, fmt.aprintf("%s %s", all_ones[type], source))
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
			
			source: string
			if mod == .register {
				source = register_name(r_m, w)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, w, segment)
				if decoder.error {
					break
				}
			}
			
			append(&output_buf, fmt.aprintf("pop %s", source))
		} else if is_push_pop_reg(opcode) {
			type := (opcode & 0b00001000) >> 3
			reg  :=  opcode & 0b00000111
			
			append(&output_buf, fmt.aprintf("%s %s", type == 1 ? "pop" : "push", register_name(reg, 1)))
		} else if is_push_pop_seg(opcode) {
			type :=  opcode & 0b00000001
			seg  := (opcode & 0b00011000) >> 3
			
			append(&output_buf, fmt.aprintf("%s %s", type == 1 ? "pop" : "push", seg_names[seg]))
		} else if is_xchg_reg_r_m(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for xchg register/memory with register\n")
				break
			}
			
			source: string
			if mod == .register {
				source = register_name(r_m, w)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
			}
			
			append(&output_buf, fmt.aprintf("xchg %s, %s", register_name(reg, w), source))
		} else if is_xchg_acc_reg(opcode) {
			reg := opcode & 0b00000111
			
			append(&output_buf, fmt.aprintf("xchg ax, %s", register_name(reg, 1)))
		} else if is_in_out_fixed(opcode) {
			imm := read(decoder, u8)
			if decoder.error {
				decode_error("Missing port for %s with fixed port\n", d == 1 ? "out" : "in")
				break
			}
			
			if d == 1 {
				append(&output_buf, fmt.aprintf("out %d, %s", imm, register_name(AX, w)))
			} else {
				append(&output_buf, fmt.aprintf("in %s, %d", register_name(AX, w), imm))
			}
		} else if is_in_out_variable(opcode) {
			if d == 1 {
				append(&output_buf, fmt.aprintf("out dx, %s", register_name(AX, w)))
			} else {
				append(&output_buf, fmt.aprintf("in %s, dx", register_name(AX, w)))
			}
		} else if is_xlat(opcode) {
			append(&output_buf, "xlat")
		} else if is_lea(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for lea\n")
				break
			}
			
			source: string
			if mod == .register { // This probably should never be the case???
				source = register_name(r_m, 1)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
			}
			
			append(&output_buf, fmt.aprintf("lea %s, %s", register_name(reg, 1), source))
		} else if is_lds(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for lds\n")
				break
			}
			
			source: string
			if mod == .register { // This probably should never be the case???
				source = register_name(r_m, 1)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
			}
			
			append(&output_buf, fmt.aprintf("lds %s, %s", register_name(reg, 1), source))
		} else if is_les(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for les\n")
				break
			}
			
			source: string
			if mod == .register { // This probably should never be the case???
				source = register_name(r_m, 1)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
			}
			
			append(&output_buf, fmt.aprintf("les %s, %s", register_name(reg, 1), source))
		} else if is_flags(opcode) {
			type := opcode & 0b00000011
			
			append(&output_buf, flags_ops[type])
		} else if is_arithmetic_op_reg_r_m(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for arithmetic op register/memory with register to either\n")
				break
			}
			
			op := (opcode & 0b00111000) >> 3
			
			dest, source: string
			if mod == .register {
				if d == 0 {
					dest   = register_name(r_m, w)
					source = register_name(reg, w)
				} else {
					dest   = register_name(reg, w)
					source = register_name(r_m, w)
				}
			} else {
				mem := effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
				
				if d == 0 {
					dest = mem
					source = register_name(reg, w)
				} else {
					dest = register_name(reg, w)
					source = mem
				}
			}
			
			append(&output_buf, fmt.aprintf("%s %s, %s", arithmetic_ops[op], dest, source))
		} else if is_arithmetic_op_r_m_imm(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for arithmetic op register/memory with register to either\n")
				break
			}
			
			s := (opcode & 0b00000010) >> 1
			
			dest: string
			if mod == .register {
				dest = register_name(r_m, w)
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
			
			append(&output_buf, fmt.aprintf("%s %s, %d", arithmetic_ops[reg], dest, imm))
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
			
			append(&output_buf, fmt.aprintf("%s %s, %d", arithmetic_ops[op], register_name(AX, w), imm))
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
			
			dest: string
			if mod == .register {
				dest = register_name(r_m, w)
			} else {
				dest = effective_address_calculation(decoder, mod, r_m, w, segment)
				if decoder.error {
					break
				}
			}
			
			append(&output_buf, fmt.aprintf("%s %s", reg == 0b000 ? "inc" : "dec", dest))
		} else if is_inc_dec_reg(opcode) {
			is_dec := (opcode & 0b00001000) >> 3
			reg    :=  opcode & 0b00000111
			
			append(&output_buf, fmt.aprintf("%s %s", is_dec == 1 ? "dec" : "inc", register_name(reg, 1)))
		} else if is_adjust_a_s(opcode) {
			type := (opcode & 0b00011000) >> 3
			
			append(&output_buf, adjust_a_s_ops[type])
		} else if is_adjust_m_d(opcode) {
			is_aad := opcode & 0b00000001
			
			next_byte := read(decoder, byte)
			if next_byte != 0b00001010 {
				decoder.error = true
				decode_error("Illegal second byte in %s\n", is_aad == 1 ? "aad" : "aam")
				break
			}
			
			append(&output_buf, is_aad == 1 ? "aad" : "aam")
		} else if is_convert(opcode) {
			is_cwd := opcode & 0b00000001
			
			append(&output_buf, is_cwd == 1 ? "cwd" : "cbw")
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
			
			dest: string
			if mod == .register {
				dest = register_name(r_m, w)
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
				
				append(&output_buf, fmt.aprintf("test %s, %d", dest, imm))
			} else {
				append(&output_buf, fmt.aprintf("%s %s", unary_ops[reg], dest))
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
			
			dest: string
			if mod == .register {
				dest = register_name(r_m, w)
			} else {
				dest = effective_address_calculation(decoder, mod, r_m, w, segment)
				if decoder.error {
					break
				}
			}
			
			v := d
			append(&output_buf, fmt.aprintf("%s %s, %s", logic_ops[reg], dest, v == 1 ? "cl" : "1"))
		} else if is_test_reg_r_m(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for test register/memory and register\n")
				break
			}
			
			dest: string
			if mod == .register {
				dest = register_name(r_m, w)
			} else {
				dest = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment)
				if decoder.error {
					break
				}
			}
			
			append(&output_buf, fmt.aprintf("test %s, %s", dest, register_name(reg, w)))
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
			
			append(&output_buf, fmt.aprintf("test %s, %d", register_name(AX, w), imm))
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
			
			append(&output_buf, fmt.aprintf("%s %s%s", z == 1 ? "rep" : "repne", string_ops[type], w == 1 ? "w" : "b"))
		} else if is_string_op(opcode) {
			type := (opcode & 0b00001110) >> 1
			// NOTE: Types that are not string ops have been filtered out by this point.
			
			append(&output_buf, fmt.aprintf("%s%s", string_ops[type], w == 1 ? "w" : "b"))
		} else if is_call_jmp_direct(opcode) {
			type := opcode & 0b000000011
			mnemonic := type == 0b00 ? "call" : "jmp"
			
			if type != 0b10 {
				disp: int
				if type == 0b11 {
					disp = int(read(decoder, i8))
				} else {
					disp = int(read(decoder, i16))
				}
				if decoder.error {
					decode_error("Missing IP-inc for %s\n", mnemonic)
					break
				}
				
				label := get_or_create_label(decoder, disp, mnemonic)
				if decoder.error {
					break
				}
				
				append(&output_buf, fmt.aprintf("%s label_%d", mnemonic, label.index))
			} else {
				ip := read(decoder, u16)
				cs := read(decoder, u16)
				if decoder.error {
					decode_error("Missing some of IP-lo, IP-hi, CS-lo, CS-hi bytes from jmp direct intersegment\n")
					break
				}
				
				append(&output_buf, fmt.aprintf("jmp %d:%d", cs, ip)) // NOTE: Guessing syntax
			}
		} else if is_call_direct_interseg(opcode) {
			ip := read(decoder, u16)
			cs := read(decoder, u16)
			if decoder.error {
				decode_error("Missing some of IP-lo, IP-hi, CS-lo, CS-hi bytes from call direct intersegment\n")
				break
			}
			
			append(&output_buf, fmt.aprintf("call %d:%d", cs, ip)) // NOTE: Guessing syntax
		} else if is_ret(opcode) {
			// TODO: Within segment vs intersegment?
			if w == 0 {
				imm := read(decoder, i16)
				if decoder.error {
					decode_error("Missing immediate for ret adding immediate to sp\n")
					break
				}
				
				append(&output_buf, fmt.aprintf("ret %d", imm))
			} else {
				append(&output_buf, "ret")
			}
		} else if is_interrupt(opcode) {
			type := opcode & 0b00000011
			if type == 0b00 {
				append(&output_buf, "int 3")
			} else if type == 0b01 {
				imm := read(decoder, byte)
				if decoder.error {
					decode_error("Missing immediate for int with type specified\n")
					break
				}
				
				append(&output_buf, fmt.aprintf("int %d", imm))
			} else if type == 0b10 {
				append(&output_buf, "into")
			} else{
				append(&output_buf, "iret")
			}
		} else if is_clc(opcode) {
			append(&output_buf, "clc")
		} else if is_cmc(opcode) {
			append(&output_buf, "cmc")
		} else if is_stc(opcode) {
			append(&output_buf, "stc")
		} else if is_cld(opcode) {
			append(&output_buf, "cld")
		} else if is_std(opcode) {
			append(&output_buf, "std")
		} else if is_cli(opcode) {
			append(&output_buf, "cli")
		} else if is_sti(opcode) {
			append(&output_buf, "sti")
		} else if is_hlt(opcode) {
			append(&output_buf, "hlt")
		} else if is_wait(opcode) {
			append(&output_buf, "wait")
		} else if is_esc(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for esc\n")
				break
			}
			
			code := ((opcode & 0b00000111) << 3) | reg
			source: string
			if mod == .register {
				source = register_name(r_m, 1)
			} else {
				source = effective_address_calculation(decoder, mod, r_m, NO_SIZE, segment) // Unsure about size
				if decoder.error {
					break
				}
			}
			
			append(&output_buf, fmt.aprintf("esc %d, %s", code, source))
		} else if is_conditional_jmp(opcode) || is_loop_or_jcxz(opcode) {
			mnemonic: string
			if is_conditional_jmp(opcode) {
				type := opcode & 0b00001111
				mnemonic = conditional_jmps[type]
			} else {
				type := opcode & 0b00000011
				mnemonic = loops[type]
			}
			
			disp := read(decoder, i8)
			if decoder.error {
				decode_error("Missing short label for %s\n", mnemonic)
				break
			}
			
			label := get_or_create_label(decoder, int(disp), mnemonic)
			if decoder.error {
				break
			}
			
			append(&output_buf, fmt.aprintf("%s label_%d", mnemonic, label.index))
		} else if is_lock(opcode) {
			lock = true
			continue
		} else if is_segment(opcode) {
			segment = int((opcode & 0b00011000) >> 3)
			continue
		} else {
			decode_error("Unhandled instruction: %08b\n", opcode)
			decoder.error = true
			break
		}
		
		if lock {
			output_buf[len(output_buf) - 1] = fmt.aprintf("lock %s", output_buf[len(output_buf) - 1]) // Leak!
		}
		lock    = false
		segment = -1
	}
	
	mnemonic_instructions = output_buf[:]
	labels = decoder.labels_buf[:]
	slice.sort_by(labels, proc(i, j: Label) -> bool {
		return i.instruction_index < j.instruction_index
	})
	success = !decoder.error
	return
}