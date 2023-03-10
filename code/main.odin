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

main :: proc() {
	if len(os.args) == 2 {
		if binary_instructions, ok := os.read_entire_file(os.args[1]); ok {
			mnemonic_instructions, ok := disasm8086(binary_instructions)
			fmt.printf("; %s\n", os.args[1])
			fmt.println("bits 16")
			for line in mnemonic_instructions {
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

op_names := []string {
	"add",
	"or",
	"adc",
	"sbb",
	"and",
	"sub",
	"xor",
	"cmp",
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

Decoder :: struct {
	binary_instructions: []byte,
	index:               int,
	error:               bool,
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

is_mov_reg_imm :: proc(opcode: byte) -> bool {
	return opcode & 0b11110000 == 0b10110000
}

is_mov_reg_r_m :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b10001000
}

is_mov_r_m_imm :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b11000100
}

is_mov_acc_mem :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b10100000
}

is_mov_r_m_seg :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b10001100
}

is_arithmetic_op_reg_r_m :: proc(opcode: byte) -> bool {
	return opcode & 0b11000100 == 0b00000000
}

is_arithmetic_op_r_m_imm :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b10000000
}

is_arithmetic_op_acc_imm :: proc(opcode: byte) -> bool {
	return opcode & 0b11000110 == 0b00000100
}

is_conditional_jmp :: proc(opcode: byte) -> bool {
	return opcode & 0b11110000 == 0b01110000
}

is_loop_or_jcxz :: proc(opcode: byte) -> bool {
	return opcode & 0b11111100 == 0b11100000
}

register_name :: proc(reg: byte, w: byte) -> string {
	return reg_names[reg | (w << 3)]
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

disasm8086 :: proc(binary_instructions: []byte) -> (mnemonic_instructions: []string, success: bool) {
	success = true
	output_buf: [dynamic]string
	decoder := &Decoder{binary_instructions = binary_instructions}
	
	// debug_printf("\n%s\n\n", os.args[1])
	for !decoder.error && has_bytes(decoder) {
		opcode := read(decoder, byte)
		// debug_printf("%08b\n", opcode)
		d := (opcode & 0b00000010) >> 1
		w :=  opcode & 0b00000001
		if is_mov_reg_imm(opcode) {
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
		} else if is_mov_reg_r_m(opcode) {
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
				mem := effective_address_calculation(decoder, mod, r_m)
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
			if d != 1 {
				decode_error("Unhandled instruction: %08b\n", opcode)
				break
			}
			
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for mov immediate to register/memory\n")
				break
			}
			
			if reg != 0b000 {
				decode_error("Illegal register field in mov immediate to register/memory\n")
				break
			}
			
			dest: string
			if mod == .register {
				dest = register_name(reg, w)
			} else {
				dest = effective_address_calculation(decoder, mod, r_m)
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
			
			append(&output_buf, fmt.aprintf("mov %s, %s %d", dest, w == 1 ? "word": "byte", imm))
		} else if is_mov_acc_mem(opcode) {
			addr := read(decoder, u16)
			
			if d == 0 {
				append(&output_buf, fmt.aprintf("mov %s, [%d]", register_name(AX, w), addr))
			} else {
				append(&output_buf, fmt.aprintf("mov [%d], %s", addr, register_name(AX, w)))
			}
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
				mem := effective_address_calculation(decoder, mod, r_m)
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
			append(&output_buf, fmt.aprintf("%s %s, %s", op_names[op], dest, source))
		} else if is_arithmetic_op_r_m_imm(opcode) {
			mod, reg, r_m := read_mod_reg_r_m(decoder)
			if decoder.error {
				decode_error("Missing mod/reg/rm byte for arithmetic op register/memory with register to either\n")
				break
			}
			
			s := (opcode & 0b00000010) >> 1
			
			dest: string
			if mod == .register {
				dest = register_name(reg, w)
			} else {
				dest = effective_address_calculation(decoder, mod, r_m)
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
			
			append(&output_buf, fmt.aprintf("%s %s, %s %d", op_names[reg], dest, w == 1 ? "word": "byte", imm))
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
			
			append(&output_buf, fmt.aprintf("%s %s, %d", op_names[op], register_name(AX, w), imm))
		} else if is_conditional_jmp(opcode) {
			type := opcode & 0b00001111
			
			disp := read(decoder, i8)
			if decoder.error {
				decode_error("Missing short label for %s\n", conditional_jmps[type])
				break
			}
			
			append(&output_buf, fmt.aprintf("%s %d", conditional_jmps[type], disp))
		} else if is_loop_or_jcxz(opcode) {
			type := opcode & 0b00000011
			
			disp := read(decoder, i8)
			if decoder.error {
				decode_error("Missing short label for %s\n", loops[type])
				break
			}
			
			append(&output_buf, fmt.aprintf("%s %d", loops[type], disp))
		} else {
			decode_error("Unhandled instruction: %08b\n", opcode)
			decoder.error = true
			break
		}
	}
	
	success = !decoder.error
	mnemonic_instructions = output_buf[:]
	return
}

effective_address_calculation :: proc(decoder: ^Decoder, mod: Mod, r_m: byte) -> string {
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
	
	result: string
	if direct_address {
		result = fmt.tprintf("[%d]", disp)
	} else if mod == .no_displacement || disp == 0 {
		result = fmt.tprintf("[%s]", effective_address_calcs[r_m])
	} else if disp > 0 {
		result = fmt.tprintf("[%s + %d]", effective_address_calcs[r_m], disp)
	} else {
		result = fmt.tprintf("[%s - %d]", effective_address_calcs[r_m], -disp)
	}
	return result
}