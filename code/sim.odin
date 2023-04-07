package sim8086

import "core:fmt"
import "core:os"

FIRST_SEGMENT_REG :: 8
FIRST_HIGH_REG    :: 4

ES :: 8
CS :: 9
SS :: 10
DS :: 11

IP :: 12
FLAGS :: 13

CF :: 1 << 0
PF :: 1 << 2
AF :: 1 << 4
ZF :: 1 << 6
SF :: 1 << 7
TF :: 1 << 8
IF :: 1 << 9
DF :: 1 << 10
OF :: 1 << 11

Simulator :: struct {
	registers: [14]u16,
	memory:    []byte,
	
	program_start: int,
	program_end:   int,
	
	out_stream: os.Handle,
}

init_sim :: proc() -> Simulator {
	return Simulator {
		memory = make([]byte, 1024*1024),
		out_stream = os.INVALID_HANDLE,
	}
}

load_program :: proc(sim: ^Simulator, file_path: string, address: int = 0) -> (data: []byte, success: bool) {
	fd, err := os.open(file_path, os.O_RDONLY, 0)
	if err != 0 {
		fmt.fprintf(os.stderr, "Could not open %s\n", file_path)
		return nil, false
	}
	defer os.close(fd)
	
	length: i64
	if length, err = os.file_size(fd); err != 0 {
		fmt.fprintf(os.stderr, "Size of %s could not be determined\n", file_path)
		return nil, false
	}
	
	if length <= 0 {
		fmt.fprintf(os.stderr, "Length of %s was %d\n", file_path, length)
		return nil, false
	}
	
	if int(length) > len(sim.memory) - address {
		fmt.fprintf(os.stderr, "Length of %s was too large (%d > %d)\n", file_path, length, len(sim.memory) - address)
		return nil, false
	}
	
	bytes_read, read_err := os.read_at_least(fd, sim.memory[address:], int(length))
	if read_err != os.ERROR_NONE {
		fmt.fprintf(os.stderr, "Error reading from file %s (Error: %d)\n", file_path, read_err)
		return nil, false
	}
	
	sim.program_start = address
	sim.program_end   = address + int(length)
	
	return sim.memory[address:bytes_read], true
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
			result = sim.registers[reg.index] & 0xff
		} else {
			result = (sim.registers[reg.index - FIRST_HIGH_REG] >> 8) & 0xff
		}
	} else if reg.segment {
		result = sim.registers[reg.index + FIRST_SEGMENT_REG]
	} else {
		result = sim.registers[reg.index]
	}
	return result
}

write_register :: proc(sim: ^Simulator, reg: Register, value: u16) {
	old_value: u16
	new_value := value
	wide_name: string
	if reg.size == 1 {
		if reg.index < FIRST_HIGH_REG {
			old_value = sim.registers[reg.index]
			new_value = (old_value & 0xff00) | (value & 0xff)
			sim.registers[reg.index] = new_value
			wide_name = reg_names[reg.index + 8]
		} else {
			old_value = sim.registers[reg.index - FIRST_HIGH_REG]
			new_value = (value << 8) | (old_value & 0xff)
			sim.registers[reg.index - FIRST_HIGH_REG] = new_value
			wide_name = reg_names[reg.index + 4]
		}
	} else if reg.segment {
		old_value = sim.registers[reg.index + FIRST_SEGMENT_REG]
		sim.registers[reg.index + FIRST_SEGMENT_REG] = new_value
		wide_name = seg_names[reg.index]
	} else {
		old_value = sim.registers[reg.index]
		sim.registers[reg.index] = new_value
		wide_name = reg_names[reg.index + 8]
	}
	sim_print(sim, " %s:0x%x->0x%x", wide_name, old_value, new_value)
}

sim_print_flags :: proc(sim: ^Simulator, flags: u16) {
	sim_print(sim, "%s%s%s%s%s%s",
	          (flags & CF) != 0 ? "C" : "",
	          (flags & PF) != 0 ? "P" : "",
	          (flags & AF) != 0 ? "A" : "",
	          (flags & ZF) != 0 ? "Z" : "",
	          (flags & SF) != 0 ? "S" : "",
	          (flags & OF) != 0 ? "O" : "")
}

set_flag :: proc(sim: ^Simulator, flag: u16, value: bool) {
	if value {
		sim.registers[FLAGS] |= flag
	} else {
		sim.registers[FLAGS] &= ~flag
	}
}

compute_pf :: proc(value: u32) -> bool {
	return (((value >> 0) ~ (value >> 1) ~ (value >> 2) ~ (value >> 3) ~
	         (value >> 4) ~ (value >> 5) ~ (value >> 6) ~ (value >> 7)) & 0b1) == 0
}

physical_address_from_logical :: proc(segment: u16, logical_address: u16) -> int {
	return (int(segment) << 4) + int(logical_address)
}

is_inside_program :: proc(sim: ^Simulator) -> bool {
	address := physical_address_from_logical(sim.registers[CS], sim.registers[IP])
	return address >= sim.program_start && address < sim.program_end
}

execute_instruction :: proc(sim: ^Simulator) -> bool {
	result  := true
	address := physical_address_from_logical(sim.registers[CS], sim.registers[IP])
	decoder := &Decoder{
		binary_instructions = sim.memory[sim.program_start:sim.program_end],
		address = address,
	}
	
	if instruction, ok := decode_instruction(decoder); ok {
		if sim.out_stream != os.INVALID_HANDLE {
			print_instruction(sim.out_stream, instruction)
			fmt.fprintf(sim.out_stream, " ;")
		}
		old_ip    := sim.registers[IP]
		old_flags := sim.registers[FLAGS]
		sim.registers[IP] += u16(decoder.address - address)
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
						set_flag(sim, CF, result & 0x10000 != 0)
						set_flag(sim, PF, compute_pf(result))
						set_flag(sim, AF, ((value ~ old_value ~ u16(result)) & 0x10) != 0)
						set_flag(sim, ZF, u16(result) == 0)
						set_flag(sim, SF, d.size == 2 ? (result & 0x8000) != 0 : (result & 0x80) != 0)
						set_flag(sim, OF, ((i16(result) < 0 && i16(old_value) > 0 && i16(value) > 0) ||
						                   (i16(result) > 0 && i16(old_value) < 0 && i16(value) < 0)))
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
			case .CMP, .SUB: {
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
						if instruction.mnemonic == .SUB do write_register(sim, d, u16(result))
						
						// Update flags
						set_flag(sim, CF, i32(value) > i32(old_value))
						set_flag(sim, PF, compute_pf(u32(result)))
						set_flag(sim, AF, (value & 0b1111) > (old_value & 0b1111))
						set_flag(sim, ZF, u16(result) == 0)
						set_flag(sim, SF, d.size == 2 ? (result & 0x8000) != 0 : (result & 0x80) != 0)
						set_flag(sim, OF, ((i16(result) < 0 && i16(old_value) > 0 && i16(value) < 0) ||
						                   (i16(result) > 0 && i16(old_value) < 0 && i16(value) > 0)))
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
			case .JE: {
				if dest, ok := instruction.dest.(Label); ok {
					if sim.registers[FLAGS] & ZF != 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid je instruction\n")
				}
			}
			case .JL: {
				if dest, ok := instruction.dest.(Label); ok {
					if (sim.registers[FLAGS] & SF != 0) ~ (sim.registers[FLAGS] & OF != 0) {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jl instruction\n")
				}
			}
			case .JLE: {
				if dest, ok := instruction.dest.(Label); ok {
					if ((sim.registers[FLAGS] & SF != 0) ~ (sim.registers[FLAGS] & OF != 0)) || (sim.registers[FLAGS] & ZF != 0) {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jle instruction\n")
				}
			}
			case .JB: {
				if dest, ok := instruction.dest.(Label); ok {
					if sim.registers[FLAGS] & CF != 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jb instruction\n")
				}
			}
			case .JBE: {
				if dest, ok := instruction.dest.(Label); ok {
					if (sim.registers[FLAGS] & CF != 0) || (sim.registers[FLAGS] & ZF != 0) {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jbe instruction\n")
				}
			}
			case .JP: {
				if dest, ok := instruction.dest.(Label); ok {
					if sim.registers[FLAGS] & PF != 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jp instruction\n")
				}
			}
			case .JO: {
				if dest, ok := instruction.dest.(Label); ok {
					if sim.registers[FLAGS] & OF != 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jo instruction\n")
				}
			}
			case .JS: {
				if dest, ok := instruction.dest.(Label); ok {
					if sim.registers[FLAGS] & SF != 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid js instruction\n")
				}
			}
			case .JNE: {
				if dest, ok := instruction.dest.(Label); ok {
					if sim.registers[FLAGS] & ZF == 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jne instruction\n")
				}
			}
			case .JNL: {
				if dest, ok := instruction.dest.(Label); ok {
					if !((sim.registers[FLAGS] & SF != 0) ~ (sim.registers[FLAGS] & OF != 0)) {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jnl instruction\n")
				}
			}
			case .JG: {
				if dest, ok := instruction.dest.(Label); ok {
					if !(((sim.registers[FLAGS] & SF != 0) ~ (sim.registers[FLAGS] & OF != 0)) || (sim.registers[FLAGS] & ZF != 0)) {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jg instruction\n")
				}
			}
			case .JNB: {
				if dest, ok := instruction.dest.(Label); ok {
					if sim.registers[FLAGS] & CF == 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jnb instruction\n")
				}
			}
			case .JA: {
				if dest, ok := instruction.dest.(Label); ok {
					if (sim.registers[FLAGS] & CF == 0) && (sim.registers[FLAGS] & ZF == 0) {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid ja instruction\n")
				}
			}
			case .JNP: {
				if dest, ok := instruction.dest.(Label); ok {
					if sim.registers[FLAGS] & PF == 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jnp instruction\n")
				}
			}
			case .JNO: {
				if dest, ok := instruction.dest.(Label); ok {
					if sim.registers[FLAGS] & OF == 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jno instruction\n")
				}
			}
			case .JNS: {
				if dest, ok := instruction.dest.(Label); ok {
					if sim.registers[FLAGS] & SF == 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid jns instruction\n")
				}
			}
			case .LOOP: {
				if dest, ok := instruction.dest.(Label); ok {
					old_cx := sim.registers[CX]
					sim.registers[CX] -= 1
					sim_print(sim, " cx:0x%x->0x%x", old_cx, sim.registers[CX])
					if sim.registers[CX] != 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid loop instruction\n")
				}
			}
			case .LOOPZ: {
				if dest, ok := instruction.dest.(Label); ok {
					old_cx := sim.registers[CX]
					sim.registers[CX] -= 1
					sim_print(sim, " cx:0x%x->0x%x", old_cx, sim.registers[CX])
					if (sim.registers[CX] != 0) && (sim.registers[FLAGS] & ZF != 0) {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid loopz instruction\n")
				}
			}
			case .LOOPNZ: {
				if dest, ok := instruction.dest.(Label); ok {
					old_cx := sim.registers[CX]
					sim.registers[CX] -= 1
					sim_print(sim, " cx:0x%x->0x%x", old_cx, sim.registers[CX])
					if (sim.registers[CX] != 0) && (sim.registers[FLAGS] & ZF == 0) {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid loopnz instruction\n")
				}
			}
			case .JCXZ: {
				if dest, ok := instruction.dest.(Label); ok {
					if sim.registers[CX] == 0 {
						sim.registers[IP] += u16(dest.offset)
					}
				} else {
					fmt.fprintf(os.stderr, "Invalid je instruction\n")
				}
			}
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
		sim_print(sim, " ip:0x%x->0x%x", old_ip, sim.registers[IP])
		if old_flags != sim.registers[FLAGS] {
			sim_print(sim, " flags:")
			sim_print_flags(sim, old_flags)
			sim_print(sim, "->")
			sim_print_flags(sim, sim.registers[FLAGS])
		}
		sim_print(sim, "\n")
	} else {
		fmt.fprintf(os.stderr, "Error decoding instruction\n")
		result = false
	}
	return result
}