package sim8086

import "core:fmt"
import "core:os"

main :: proc() {
	if len(os.args) == 3 {
		mode := os.args[1]
		if mode == "-disasm" {
			if binary_instructions, ok := os.read_entire_file(os.args[2]); ok {
				instructions, labels, ok := disasm8086(binary_instructions)
				fmt.printf("; %s\n", os.args[2])
				fmt.println("bits 16")
				label_index := 0
				for instruction, index in instructions {
					if label_index < len(labels) && labels[label_index].instruction_index == index {
						fmt.printf("label_%d:\n", labels[label_index].index)
						label_index += 1
					}
					print_instruction(os.stdout, instruction)
					fmt.println()
				}
				if !ok {
					fmt.printf("; Failed beyond this point\n")
				}
			} else {
				fmt.fprintf(os.stderr, "Could not read file %v\n", os.args[2])
			}
		} else if mode == "-exec" {
			if binary_instructions, ok := os.read_entire_file(os.args[2]); ok {
				instructions, labels, ok := disasm8086(binary_instructions)
				sim := init_sim()
				set_output_stream(&sim, os.stdout)
				
				fmt.printf("--- %s execution ---\n", os.args[2])
				for instruction, index in instructions {
					print_instruction(os.stdout, instruction)
					fmt.printf(" ; ")
					execute_instruction(&sim, instruction)
					fmt.println()
				}
				
				fmt.printf("\nFinal registers:\n")
				
				reg_indices := [?]int {0, 3, 1, 2, 4, 5, 6, 7, 8, 9, 10, 11}
				
				for i in 0 ..< len(sim.registers) {
					index := reg_indices[i]
					reg_name := index < FIRST_SEGMENT_REG ? reg_names[index + 8] : seg_names[index - FIRST_SEGMENT_REG]
					value := sim.registers[index].value
					if value != 0 do fmt.printf("      %s: 0x%04x (%d)\n", reg_name, value, value)
				}
				
				if flags_differ(sim.flags, FlagsRegister{}) {
					fmt.printf("   flags: ")
					sim_print_flags(&sim, sim.flags)
					fmt.println()
				}
				cleanup_sim(&sim)
				if !ok {
					fmt.printf("; Failed beyond this point\n")
				}
			} else {
				fmt.fprintf(os.stderr, "Could not read file %v\n", os.args[1])
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
