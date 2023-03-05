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
			if mnemonic_instructions, ok := disasm8086(binary_instructions); ok {
				fmt.printf("; %s\n", os.args[1])
				fmt.println("bits 16")
				for line in mnemonic_instructions {
					fmt.println(line)
				}
			}
		} else {
			fmt.fprintf(os.stderr, "Could not read file %v\n", os.args[1])
		}
	} else {
		fmt.fprintf(os.stderr, "Usage: %v <binary-file>\n", os.args[0])
	}
}

Opcode :: enum {
	MOV = 0b100010,
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

disasm8086 :: proc(binary_instructions: []byte) -> (mnemonic_instructions: []string, success: bool) {
	success = true
	output_buf: [dynamic]string
	for i := 0; i < len(binary_instructions); i += 1 {
		byte1 := binary_instructions[i]
		opcode := Opcode(byte1 >> 2)
		d := (byte1 & 0b1) >> 1
		w := byte1 & 0b1
		switch opcode {
			case .MOV:
				i += 1
				if i < len(binary_instructions) {
					mod_reg_rm := binary_instructions[i]
					mod := Mod(mod_reg_rm >> 6)
					reg := Reg((mod_reg_rm & 0b111000) >> 3)
					r_m := Reg(mod_reg_rm & 0b111)
					if (mod == .register) {
						opd1, opd2: byte
						if d == 0 {
							opd1 = byte(r_m)
							opd2 = byte(reg)
						} else {
							opd1 = byte(reg)
							opd2 = byte(r_m)
						}
						opd1 |= (w << 3)
						opd2 |= (w << 3)
						append(&output_buf, fmt.aprintf("mov %s, %s", reg_names[opd1], reg_names[opd2]))
					} else {
						fmt.fprintf(os.stderr, "Modes other than register not implemented. Got %b\n", byte(mod))
						success = false
						break
					}
				} else {
					fmt.fprintf(os.stderr, "Missing byte 2 of MOV instruction\n")
					success = false
					break
				}
			
			case:
				fmt.fprintf(os.stderr, "Unknown opcode: %b\n", byte(opcode))
				success = false
				break
		}
	}
	
	mnemonic_instructions = output_buf[:]
	return
}