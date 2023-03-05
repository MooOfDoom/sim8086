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

Opcode :: enum {
	MOV_rm_to_from_reg  = 0b100010,
	MOV_imm_to_rm       = 0b110001,
	MOV_imm_to_reg      = 0b1011,
	MOV_mem_to_from_acc = 0b101000,
	MOV_rm_to_from_seg  = 0b100011,
}

Mod :: enum {
	no_displacement = 0b00,
	displacement_8  = 0b01,
	displacement_16 = 0b10,
	register        = 0b11,
}

Reg :: enum {
	// W = 0
	AL = 0b000,
	CL = 0b001,
	DL = 0b010,
	BL = 0b011,
	AH = 0b100,
	CH = 0b101,
	DH = 0b110,
	BH = 0b111,
	
	// W = 1
	AX = 0b000,
	CX = 0b001,
	DX = 0b010,
	BX = 0b011,
	SP = 0b100,
	BP = 0b101,
	SI = 0b110,
	DI = 0b111,
}

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

register_name :: proc(reg: Reg, w: byte) -> string {
	return reg_names[byte(reg) | (w << 3)]
}

mod_reg_rm :: proc(instruction_byte: byte) -> (mod: Mod, reg: Reg, r_m: byte) {
	mod = Mod(instruction_byte >> 6)
	reg = Reg((instruction_byte & 0b111000) >> 3)
	r_m = instruction_byte & 0b111
	return
}

disasm8086 :: proc(binary_instructions: []byte) -> (mnemonic_instructions: []string, success: bool) {
	success = true
	output_buf: [dynamic]string
	
	loop: for i := 0; i < len(binary_instructions); i += 1 {
		byte1 := binary_instructions[i]
		if Opcode(byte1 >> 4) == .MOV_imm_to_reg {
			i += 1
			if i >= len(binary_instructions) {
				fmt.fprintf(os.stderr, "Missing data of immediate to register MOV instruction\n")
				success = false
				break loop
			}
			
			reg := byte1 & 0b1111
			imm := i16(binary_instructions[i])
			if reg > 7 {
				i += 1
				if i >= len(binary_instructions) {
					fmt.fprintf(os.stderr, "Missing second byte of data of wide immediate to register MOV instruction\n")
					success = false
					break loop
				}
				
				imm |= i16(binary_instructions[i]) << 8
			}
			append(&output_buf, fmt.aprintf("mov %s, %d", reg_names[reg], imm))
		} else {
			opcode := Opcode(byte1 >> 2)
			d := (byte1 & 0b10) >> 1
			w := byte1 & 0b1
			switch opcode {
				case .MOV_rm_to_from_reg:
					i += 1
					if i >= len(binary_instructions) {
						fmt.fprintf(os.stderr, "Missing byte 2 of MOV instruction\n")
						success = false
						break loop
					}
					
					mod, reg, r_m := mod_reg_rm(binary_instructions[i])
					dest, source: string
					if mod == .register {
						if d == 0 {
							dest   = register_name(Reg(r_m), w)
							source = register_name(reg, w)
						} else {
							dest   = register_name(reg, w)
							source = register_name(Reg(r_m), w)
						}
					} else {
						mem, ok := effective_address_calculation(&i, binary_instructions, mod, r_m)
						if !ok {
							break loop
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
				
				case .MOV_imm_to_rm:
					if d != 1 {
						fmt.fprintf(os.stderr, "Unhandled instruction: %8b\n", byte1)
						success = false
						break loop
					}
					
					i += 1
					if i >= len(binary_instructions) {
						fmt.fprintf(os.stderr, "Missing byte 2 of MOV instruction\n")
						success = false
						break loop
					}
					
					mod, reg, r_m := mod_reg_rm(binary_instructions[i])
					
					if reg != Reg(0) {
						fmt.fprintf(os.stderr, "Illegal register field in MOV imm to reg/mem instruction\n")
						success = false
						break loop
					}
					
					dest: string
					if mod == .register {
						dest = register_name(reg, w)
					} else {
						mem, ok := effective_address_calculation(&i, binary_instructions, mod, r_m)
						if !ok {
							break loop
						}
						
						dest = mem
					}
					
					i += 1
					if i >= len(binary_instructions) {
						fmt.fprintf(os.stderr, "Missing data of immediate to reg/mem MOV instruction\n")
						success = false
						break loop
					}
					
					imm := i16(binary_instructions[i])
					if w == 1 {
						i += 1
						if i >= len(binary_instructions) {
							fmt.fprintf(os.stderr, "Missing second byte of data of wide immediate to reg/mem MOV instruction\n")
							success = false
							break loop
						}
						
						imm |= i16(binary_instructions[i]) << 8
					}
					
					append(&output_buf, fmt.aprintf("mov %s, %s %d", dest, w == 1 ? "word": "byte", imm))
					
				case .MOV_mem_to_from_acc:
					i += 1
					if i + 1 >= len(binary_instructions) {
						fmt.fprintf(os.stderr, "Missing address of memory to/from accumulator MOV instruction\n")
						success = false
						break loop
					}
					
					addr := u16(binary_instructions[i])
					i += 1
					addr |= u16(binary_instructions[i]) << 8
					
					if d == 0 {
						append(&output_buf, fmt.aprintf("mov %s, [%d]", register_name(.AX, w), addr))
					} else {
						append(&output_buf, fmt.aprintf("mov [%d], %s", addr, register_name(.AX, w)))
					}
					
				case .MOV_rm_to_from_seg:
				
				case .MOV_imm_to_reg: // NOTE: Looks like XOR imm, SS, or AAA
				case:
					fmt.fprintf(os.stderr, "Unknown opcode: %b\n", byte(opcode))
					success = false
					break loop
			}
		}
	}
	
	mnemonic_instructions = output_buf[:]
	return
}

effective_address_calculation :: proc(i: ^int, binary_instructions: []byte, mod: Mod, r_m: byte) ->
                                     (result: string, success: bool) {
	disp: i16
	direct_address := mod == .no_displacement && r_m == 0b110
	if mod != .no_displacement || direct_address {
		i^ += 1
		if i^ >= len(binary_instructions) {
			fmt.fprintf(os.stderr, "Missing displacement for effective address calculation\n")
			success = false
			return
		}
		
		disp = i16(binary_instructions[i^])
		if mod == .displacement_16 || direct_address {
			i^ +=1
			if i^ >= len(binary_instructions) {
				fmt.fprintf(os.stderr, "Missing second displacement for effective address calculation\n")
				success = false
				return
			}
			disp |= i16(binary_instructions[i^]) << 8
		} else if disp > 128 {
			disp -= 256
		}
	}
	
	if direct_address {
		result = fmt.tprintf("[%d]", disp)
	} else if mod == .no_displacement {
		result = fmt.tprintf("[%s]", effective_address_calcs[r_m])
	} else if disp > 0 {
		result = fmt.tprintf("[%s + %d]", effective_address_calcs[r_m], disp)
	} else {
		result = fmt.tprintf("[%s - %d]", effective_address_calcs[r_m], -disp)
	}
	success = true
	return
}