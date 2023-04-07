package sim8086

import "core:fmt"
import "core:os"

main :: proc() {
	if len(os.args) == 3 {
		mode := os.args[1]
		if mode == "-disasm" {
			sim := init_sim()
			defer cleanup_sim(&sim)
			
			if binary_instructions, ok := load_program(&sim, os.args[2]); ok {
				instructions, ok := disasm8086(binary_instructions)
				fmt.printf("; %s\n", os.args[2])
				fmt.println("bits 16")
				decoder := &Decoder{binary_instructions = binary_instructions}
				for has_bytes(decoder) {
					if instruction, ok := decode_instruction(decoder); ok {
						print_instruction(os.stdout, instruction)
						fmt.println()
					} else {
						fmt.printf("; Failed beyond this point\n")
						break
					}
				}
			} else {
				fmt.fprintf(os.stderr, "Failed to load program %v\n", os.args[2])
			}
		} else if mode == "-exec" {
			sim := init_sim()
			defer cleanup_sim(&sim)
			
			if binary_instructions, ok := load_program(&sim, os.args[2]); ok {
				set_output_stream(&sim, os.stdout)
				
				fmt.printf("--- %s execution ---\n", os.args[2])
				for is_inside_program(&sim) {
					if !execute_instruction(&sim) {
						fmt.printf("; Failed beyond this point\n")
						break
					}
				}
				
				fmt.printf("\nFinal registers:\n")
				
				reg_indices := [?]int {AX, BX, CX, DX, SP, BP, SI, DI, ES, CS, SS, DS}
				
				for i in 0 ..< len(reg_indices) {
					index := reg_indices[i]
					reg_name := index < FIRST_SEGMENT_REG ? reg_names[index + 8] : seg_names[index - FIRST_SEGMENT_REG]
					value := sim.registers[index]
					if value != 0 do fmt.printf("      %s: 0x%04x (%d)\n", reg_name, value, value)
				}
				fmt.printf("      ip: 0x%04x (%d)\n", sim.registers[IP], sim.registers[IP])
				if sim.registers[FLAGS] != 0 {
					fmt.printf("   flags: ")
					sim_print_flags(&sim, sim.registers[FLAGS])
					fmt.println()
				}
				cleanup_sim(&sim)
			} else {
				fmt.fprintf(os.stderr, "Failed to load program %v\n", os.args[2])
			}
		} else {
			fmt.fprintf(os.stderr, "Unrecognized mode: %v\n", os.args[1])
			print_usage()
		}
	} else {
		print_usage()
	}
}

print_usage :: proc() {
	fmt.fprintf(os.stderr, "Usage: %v <mode> <binary-file>\n", os.args[0])
	fmt.fprintf(os.stderr, "  <mode> can be any of the following:\n")
	fmt.fprintf(os.stderr, "  -disasm   Print disassembly\n")
	fmt.fprintf(os.stderr, "  -exec     Simulate execution of the code\n")
}
