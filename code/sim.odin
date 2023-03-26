package sim8086

import "core:fmt"
import "core:os"

FIRST_SEGMENT_REG :: 8
FIRST_HIGH_REG    :: 4

Simulator :: struct {
	registers: [12]SimRegister,
	memory:    []byte,
	
	out_stream: os.Handle,
}

SimRegister :: struct {
	value: u16,
}

init_sim :: proc() -> Simulator {
	return Simulator {
		memory = make([]byte, 1024*1024),
		
		out_stream = os.INVALID_HANDLE,
	}
}

cleanup_sim :: proc(sim: ^Simulator) {
	delete(sim.memory)
}

set_output_stream :: proc(sim: ^Simulator, out_stream: os.Handle) {
	sim.out_stream = out_stream
}

sim_print :: proc(sim: ^Simulator, fmt_string: string, args: ..any) {
	if sim.out_stream != os.INVALID_HANDLE {
		fmt.fprintf(sim.out_stream, fmt_string, ..args)
	}
}

execute_instruction :: proc(sim: ^Simulator, instruction: Instruction) {
	switch instruction.mnemonic {
		case .NONE: {
			fmt.fprintf(os.stderr, "Invalid instruction\n")
		}
		case .MOV: {
			source := instruction.source
			value: u16
			switch s in source {
				case Register: {
					if s.size == 1 {
						if s.index < FIRST_HIGH_REG {
							value = sim.registers[s.index].value & 0xff
						} else {
							value = (sim.registers[s.index - FIRST_HIGH_REG].value >> 8) & 0xff
						}
					} else if s.segment {
						value = sim.registers[s.index + FIRST_SEGMENT_REG].value
					} else {
						value = sim.registers[s.index].value
					}
				}
				case Memory: {
					sim_print(sim, "TODO: Not implemented");
				}
				case Immediate: {
					value = u16(s.value)
				}
				case Label:
				case Intersegment:
				case: {
					fmt.fprintf(os.stderr, "Invalid mov instruction\n")
				}
			}
			dest := instruction.dest
			old_value: u16
			new_value := value
			switch d in dest {
				case Register: {
					wide_name: string
					if d.size == 1 {
						if d.index < FIRST_HIGH_REG {
							old_value = sim.registers[d.index].value
							new_value = (old_value & 0xff00) | (value & 0xff)
							sim.registers[d.index].value = new_value
							wide_name = reg_names[d.index + 8]
						} else {
							old_value = sim.registers[d.index - FIRST_HIGH_REG].value
							new_value = (value << 8) | (old_value & 0xff)
							sim.registers[d.index - FIRST_HIGH_REG].value = new_value
							wide_name = reg_names[d.index + 4]
						}
					} else if d.segment {
						old_value = sim.registers[d.index + FIRST_SEGMENT_REG].value
						sim.registers[d.index + FIRST_SEGMENT_REG].value = new_value
						wide_name = seg_names[d.index]
					} else {
						old_value = sim.registers[d.index].value
						sim.registers[d.index].value = new_value
						wide_name = reg_names[d.index + 8]
					}
					sim_print(sim, "%s:0x%x->0x%x", wide_name, old_value, new_value)
				}
				case Memory: {
					sim_print(sim, "TODO: Not implemented");
				}
				case Immediate:
				case Label:
				case Intersegment:
				case: {
					fmt.fprintf(os.stderr, "Invalid mov instruction\n")
				}
			}
		}
		case .PUSH:
		case .POP:
		case .XCHG:
		case .IN:
		case .OUT:
		case .XLAT:
		case .LEA:
		case .LDS:
		case .LES:
		case .LAHF:
		case .SAHF:
		case .PUSHF:
		case .POPF:
		case .ADD:
		case .ADC:
		case .INC:
		case .AAA:
		case .DAA:
		case .SUB:
		case .SBB:
		case .DEC:
		case .NEG:
		case .CMP:
		case .AAS:
		case .DAS:
		case .MUL:
		case .IMUL:
		case .AAM:
		case .DIV:
		case .IDIV:
		case .AAD:
		case .CBW:
		case .CWD:
		case .NOT:
		case .SHL:
		case .SHR:
		case .SAR:
		case .ROL:
		case .ROR:
		case .RCL:
		case .RCR:
		case .AND:
		case .TEST:
		case .OR:
		case .XOR:
		case .REP:
		case .MOVS:
		case .CMPS:
		case .SCAS:
		case .LODS:
		case .STOS:
		case .CALL:
		case .JMP:
		case .RET:
		case .JE:
		case .JL:
		case .JLE:
		case .JB:
		case .JBE:
		case .JP:
		case .JO:
		case .JS:
		case .JNE:
		case .JNL:
		case .JG:
		case .JNB:
		case .JA:
		case .JNP:
		case .JNO:
		case .JNS:
		case .LOOP:
		case .LOOPZ:
		case .LOOPNZ:
		case .JCXZ:
		case .INT:
		case .INTO:
		case .IRET:
		case .CLC:
		case .CMC:
		case .STC:
		case .CLD:
		case .STD:
		case .CLI:
		case .STI:
		case .HLT:
		case .WAIT:
		case .ESC:
		case: {
			fmt.fprintf(os.stderr, "TODO: Implement this instruction\n")
			sim_print(sim, "Executed instruction (supposedly!)")
		}
	}
}