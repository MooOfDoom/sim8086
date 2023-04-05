package sim8086

import "core:fmt"
import "core:os"

FIRST_SEGMENT_REG :: 8
FIRST_HIGH_REG    :: 4

Simulator :: struct {
	registers: [12]SimRegister,
	memory:    []byte,
	flags:     FlagsRegister,
	
	out_stream: os.Handle,
}

SimRegister :: struct {
	value: u16,
}

FlagsRegister :: struct {
	cf: bool,
	pf: bool,
	af: bool,
	zf: bool,
	sf: bool,
	of: bool,
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

read_register :: proc(sim: ^Simulator, reg: Register) -> u16 {
	result: u16
	if reg.size == 1 {
		if reg.index < FIRST_HIGH_REG {
			result = sim.registers[reg.index].value & 0xff
		} else {
			result = (sim.registers[reg.index - FIRST_HIGH_REG].value >> 8) & 0xff
		}
	} else if reg.segment {
		result = sim.registers[reg.index + FIRST_SEGMENT_REG].value
	} else {
		result = sim.registers[reg.index].value
	}
	return result
}

write_register :: proc(sim: ^Simulator, reg: Register, value: u16) {
	old_value: u16
	new_value := value
	wide_name: string
	if reg.size == 1 {
		if reg.index < FIRST_HIGH_REG {
			old_value = sim.registers[reg.index].value
			new_value = (old_value & 0xff00) | (value & 0xff)
			sim.registers[reg.index].value = new_value
			wide_name = reg_names[reg.index + 8]
		} else {
			old_value = sim.registers[reg.index - FIRST_HIGH_REG].value
			new_value = (value << 8) | (old_value & 0xff)
			sim.registers[reg.index - FIRST_HIGH_REG].value = new_value
			wide_name = reg_names[reg.index + 4]
		}
	} else if reg.segment {
		old_value = sim.registers[reg.index + FIRST_SEGMENT_REG].value
		sim.registers[reg.index + FIRST_SEGMENT_REG].value = new_value
		wide_name = seg_names[reg.index]
	} else {
		old_value = sim.registers[reg.index].value
		sim.registers[reg.index].value = new_value
		wide_name = reg_names[reg.index + 8]
	}
	sim_print(sim, "%s:0x%x->0x%x", wide_name, old_value, new_value)
}

sim_print_flags :: proc(sim: ^Simulator, flags: FlagsRegister) {
	sim_print(sim, "%s%s%s%s%s%s",
	          flags.cf ? "C" : "",
	          flags.pf ? "P" : "",
	          flags.af ? "A" : "",
	          flags.zf ? "Z" : "",
	          flags.sf ? "S" : "",
	          flags.of ? "O" : "")
}

flags_differ :: proc(a: FlagsRegister, b: FlagsRegister) -> bool {
	return (a.cf != b.cf) || (a.pf != b.pf) || (a.af != b.af) || (a.zf != b.zf) || (a.sf != b.sf) || (a.of != b.of)
}

compute_pf :: proc(value: u32) -> bool {
	return (((value >> 0) ~ (value >> 1) ~ (value >> 2) ~ (value >> 3) ~
	         (value >> 4) ~ (value >> 5) ~ (value >> 6) ~ (value >> 7)) & 0b1) == 0
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
					value = read_register(sim, s)
				}
				case Memory: {
					sim_print(sim, "TODO: Not implemented")
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
			switch d in dest {
				case Register: {
					write_register(sim, d, value)
				}
				case Memory: {
					sim_print(sim, "TODO: Not implemented")
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
		case .ADD: {
			source := instruction.source
			value: u16
			switch s in source {
				case Register: {
					value = read_register(sim, s)
				}
				case Memory: {
					sim_print(sim, "TODO: Not implemented")
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
			switch d in dest {
				case Register: {
					old_value := read_register(sim, d)
					result := u32(old_value) + u32(value)
					write_register(sim, d, u16(result))
					
					// Update flags
					old_flags := sim.flags
					sim.flags.cf = (result & 0x10000) != 0
					sim.flags.pf = compute_pf(result)
					sim.flags.af = ((value ~ old_value ~ u16(result)) & 0x10) != 0
					sim.flags.zf = u16(result) == 0
					sim.flags.sf = d.size == 2 ? (result & 0x8000) != 0 : (result & 0x80) != 0
					sim.flags.of = ((i16(result) < 0 && i16(old_value) > 0 && i16(value) > 0) ||
					                (i16(result) > 0 && i16(old_value) < 0 && i16(value) < 0))
					if (flags_differ(old_flags, sim.flags)) {
						sim_print(sim, " flags:")
						sim_print_flags(sim, old_flags)
						sim_print(sim, "->")
						sim_print_flags(sim, sim.flags)
					}
				}
				case Memory: {
					sim_print(sim, "TODO: Not implemented")
				}
				case Immediate:
				case Label:
				case Intersegment:
				case: {
					fmt.fprintf(os.stderr, "Invalid mov instruction\n")
				}
			}
		}
		case .ADC:
		case .INC:
		case .AAA:
		case .DAA:
		case .SUB: {
			source := instruction.source
			value: u16
			switch s in source {
				case Register: {
					value = read_register(sim, s)
				}
				case Memory: {
					sim_print(sim, "TODO: Not implemented")
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
			switch d in dest {
				case Register: {
					old_value := read_register(sim, d)
					result := i32(old_value) - i32(value)
					write_register(sim, d, u16(result))
					
					// Update flags
					old_flags := sim.flags
					sim.flags.cf = i32(value) > i32(old_value)
					sim.flags.pf = compute_pf(u32(result))
					sim.flags.af = (value & 0b1111) > (old_value & 0b1111)
					sim.flags.zf = u16(result) == 0
					sim.flags.sf = d.size == 2 ? (result & 0x8000) != 0 : (result & 0x80) != 0
					sim.flags.of = ((i16(result) < 0 && i16(old_value) > 0 && i16(value) < 0) ||
					                (i16(result) > 0 && i16(old_value) < 0 && i16(value) > 0))
					if (flags_differ(old_flags, sim.flags)) {
						sim_print(sim, " flags:")
						sim_print_flags(sim, old_flags)
						sim_print(sim, "->")
						sim_print_flags(sim, sim.flags)
					}
				}
				case Memory: {
					sim_print(sim, "TODO: Not implemented")
				}
				case Immediate:
				case Label:
				case Intersegment:
				case: {
					fmt.fprintf(os.stderr, "Invalid mov instruction\n")
				}
			}
		}
		case .SBB:
		case .DEC:
		case .NEG:
		case .CMP: {
			source := instruction.source
			value: u16
			switch s in source {
				case Register: {
					value = read_register(sim, s)
				}
				case Memory: {
					sim_print(sim, "TODO: Not implemented")
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
			switch d in dest {
				case Register: {
					old_value := read_register(sim, d)
					result := i32(old_value) - i32(value)
					
					// Update flags
					old_flags := sim.flags
					sim.flags.cf = i32(value) > i32(old_value)
					sim.flags.pf = compute_pf(u32(result))
					sim.flags.af = (value & 0b1111) > (old_value & 0b1111)
					sim.flags.zf = u16(result) == 0
					sim.flags.sf = d.size == 2 ? (result & 0x8000) != 0 : (result & 0x80) != 0
					sim.flags.of = ((i16(result) < 0 && i16(old_value) > 0 && i16(value) < 0) ||
					                (i16(result) > 0 && i16(old_value) < 0 && i16(value) > 0))
					if flags_differ(old_flags, sim.flags) {
						sim_print(sim, " flags:")
						sim_print_flags(sim, old_flags)
						sim_print(sim, "->")
						sim_print_flags(sim, sim.flags)
					}
				}
				case Memory: {
					sim_print(sim, "TODO: Not implemented")
				}
				case Immediate:
				case Label:
				case Intersegment:
				case: {
					fmt.fprintf(os.stderr, "Invalid mov instruction\n")
				}
			}
		}
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