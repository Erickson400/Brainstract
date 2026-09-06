package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:strings"
import "core:strconv"

Char :: bit_set[u8(0)..=127]
DIGITS : Char : {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'}
WHITESPACES : Char : {' ', '\t', '\n'} 
INSTRUCTION : Char : {'+', '-', '<', '>', '[', ']', ',', '.'}
COMPILER_CHARS : Char : {'{', '}', '=', '\"', '!', '(', ':', ')'}
MACRO_NAME_CHARS : Char : {
	'\'', '*', '/', ';', '?', '@', '\\', '^', '_', '`', '|', '~',
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
} + DIGITS

ByteCode :: union {
	Instruction,
	Snapshot,
}

Instruction :: struct {
	inst: enum u8 {Add, Subtract, MoveLeft, MoveRight, OpenBracket, CloseBracket, Input, Output},
}

Snapshot :: struct {
	min, max: u16
}

ParsingInfo :: struct {
	line: uint,
	lexer: []u8,
	macro_defs: map[string][]ByteCode,
	final_instructions: [dynamic]ByteCode,
}

MacroError :: enum {
	None,
	UndefinedName,
	MissingCloseBracket,
	MissingName,
	MissingEqualsign,
	Other,
}

main :: proc() {
	script_underlying_data: []u8
	err: os.Error
	output_raw_bf := false
	if len(os.args) == 1 {
		fmt.println("Not enough arguments")
		fmt.println("Do: <File>")
		fmt.println("Or: -raw <File>")
		return
	}
	if os.args[1] == "-raw" {
		if len(os.args) < 3 {
			fmt.println("You forgot the file name after the -raw command")
			return
		}
		output_raw_bf = true
		script_underlying_data, err = os.read_entire_file(os.args[2], allocator = context.allocator)
	} else {
		script_underlying_data, err = os.read_entire_file(os.args[1], allocator = context.allocator)
	}
	if err != nil {
		fmt.println("Could not read input script")
		return
	}
	defer delete(script_underlying_data)

	// Tokinize, validate, and turn the script into clean bytecode.
	parsing_info := ParsingInfo {
		1,
		script_underlying_data,
		make(map[string][]ByteCode),
		make([dynamic]ByteCode, 0, mem.Megabyte),
	}
	parsing_loop: for {
		skip_whitespaces(&parsing_info)
		if len(parsing_info.lexer) == 0 do break	// Turned the whole file into bytecode
		ok: bool
		char := parsing_info.lexer[0]
		switch {
		case char == '\"':
			ok = read_comment(&parsing_info)
			if !ok do return
		case char == '!':
			ok = read_snapshot(&parsing_info, nil)
			if !ok do return
		case char in INSTRUCTION:
			switch char {
				case '+': append(&parsing_info.final_instructions, Instruction{.Add})
				case '-': append(&parsing_info.final_instructions, Instruction{.Subtract})
				case '<': append(&parsing_info.final_instructions, Instruction{.MoveLeft})
				case '>': append(&parsing_info.final_instructions, Instruction{.MoveRight})
				case '[': append(&parsing_info.final_instructions, Instruction{.OpenBracket})
				case ']': append(&parsing_info.final_instructions, Instruction{.CloseBracket})
				case ',': append(&parsing_info.final_instructions, Instruction{.Input})
				case '.': append(&parsing_info.final_instructions, Instruction{.Output})
			}
			parsing_info.lexer = parsing_info.lexer[1:]
		case char == '{':
			backup_lexer := parsing_info.lexer[:]
			err := read_macro_call(&parsing_info, &parsing_info.final_instructions)
			if err == .None {
				continue
			} else if err == .MissingCloseBracket {
				parsing_info.lexer = backup_lexer
				err2 := read_macro_def(&parsing_info) 
				if err2 != .None do return
			} else {
				return
			}
		case:
			fmt.printf("Error: Invalid instruction or keyword '%c' in line %d\n", char, parsing_info.line)
			return
		}
	}

	// Clear the macro definitions
	for def in parsing_info.macro_defs {
		delete(parsing_info.macro_defs[def])
		delete(def)
	}
	delete(parsing_info.macro_defs)

	// Run the bytecode instructions or output raw brainfuck
	if output_raw_bf {
		output_raw_to_file(parsing_info.final_instructions[:])
	} else {
		run_bytecodes(parsing_info.final_instructions[:])
	}
}

run_bytecodes :: proc(bytecodes: []ByteCode) {
	program_counter: uint
	memory_pointer: uint
	memory: [30000]u8

    open_bracket_stack := make([dynamic]uint) // Holds position for open brackets
    defer delete(open_bracket_stack)
	is_being_skipped: bool
	
    for {
		if len(bytecodes) == 0 do break
        instruction := bytecodes[program_counter]
		switch v in instruction {
		case Snapshot:
			print_snapshot(uint(v.min), uint(v.max), memory_pointer, memory[:])
		case Instruction:
			switch v.inst {
			case .Add:
				if !is_being_skipped {
					memory[memory_pointer] += 1
				}
			case .Subtract:
				if !is_being_skipped {
					memory[memory_pointer] -= 1
				}
			case .MoveLeft:
				if !is_being_skipped {
					memory_pointer -= 1
					if memory_pointer < 0 {
						fmt.panicf("Runtime Error: Memory pointer went out of bounds from the range 0 - 29,999")
					}
				}
			case .MoveRight:
				if !is_being_skipped {
					memory_pointer += 1
					if memory_pointer > 29999 {
						fmt.panicf("Runtime Error: Memory pointer went out of bounds from the range 0 - 29,999")
					}
				}
			case .OpenBracket:
				is_being_skipped = memory[memory_pointer] == 0
				append(&open_bracket_stack, program_counter)
			case .CloseBracket:
				open_bracket, ok := pop_safe(&open_bracket_stack)
				if !ok {
					fmt.println("Runtime Error: Program has missing closing brackets")
					return
				}
				if memory[memory_pointer] != 0 {
					program_counter = open_bracket - 1
				}
			case .Input: 
				if !is_being_skipped {
					buff: [1]u8
					os.read(os.stdin, buff[:])
					memory[memory_pointer] = buff[0]
				}
			case .Output:
				if !is_being_skipped {
					fmt.printf("%c", memory[memory_pointer])
				}
			} 
		}
		program_counter += 1
        if program_counter >= len(bytecodes) do break
	}
    fmt.println()
}

print_snapshot :: proc(min, max, memory_pointer: uint, memory: []u8, ) {
	assert(max < 30_000)
	assert(min < max)
	assert(memory != nil)

	column := 0
	fmt.printf("\nMemory Pointer: %d\n", memory_pointer)
	fmt.printf("% 5d: ", min)
	for i in min..<max {
		if column == 10 {
			fmt.printf("\n% 5d: ", i + 1)
			column = 0
		}
		fmt.printf("% 3d, ", memory[i])
		column += 1
	}
	fmt.println()
}

output_raw_to_file :: proc(bytecodes: []ByteCode) {
	output := make([dynamic]u8)
	column := 0
	for bytecode in bytecodes {
		switch v in bytecode {
		case Instruction:
			switch v.inst {
			case .Add: 			append(&output, '+')
			case .Subtract: 	append(&output, '-')
			case .MoveLeft: 	append(&output, '<')
			case .MoveRight: 	append(&output, '>')
			case .OpenBracket: 	append(&output, '[')
			case .CloseBracket: append(&output, ']')
			case .Input: 		append(&output, ',')
			case .Output: 		append(&output, '.')
			}
		case Snapshot: continue
		case:
		}
		if column == 100 {
			append(&output, '\n')
			column = 0
		}
		column += 1
	}
	err := os.write_entire_file_from_bytes("./raw.bf", output[:])
	assert(err == nil)
	fmt.println("Raw brainfuck outputted to file raw.bf")
}

read_macro_def :: proc(parsing_info: ^ParsingInfo) -> MacroError {
	assert(parsing_info.lexer[0] == '{')

	// Read '{'
	parsing_info.lexer = parsing_info.lexer[1:]

	// Read the macro name
	macro_name, ok := read_macro_name(parsing_info)
	if !ok do return .MissingName

	// Read '='
	skip_whitespaces(parsing_info)
	if parsing_info.lexer[0] != '=' {
		fmt.printf("Error: Missing macro definition equal sign in line %d\n", parsing_info.line)
		return .MissingEqualsign
	}
	parsing_info.lexer = parsing_info.lexer[1:]

	// Read instructions. And macro calls.
	skip_whitespaces(parsing_info)
	macro_instructions := make([dynamic]ByteCode)
	macro_parsing_loop: for {
		skip_whitespaces(parsing_info)
		ok: bool
		char := parsing_info.lexer[0]
		switch {
		case char == '\"':
			ok = read_comment(parsing_info)
			if !ok do return .Other
		case char == '!':
			ok = read_snapshot(parsing_info, &macro_instructions)
			if !ok do return .Other
		case char in INSTRUCTION:
			switch char {
				case '+': append(&macro_instructions, Instruction{.Add})
				case '-': append(&macro_instructions, Instruction{.Subtract})
				case '<': append(&macro_instructions, Instruction{.MoveLeft})
				case '>': append(&macro_instructions, Instruction{.MoveRight})
				case '[': append(&macro_instructions, Instruction{.OpenBracket})
				case ']': append(&macro_instructions, Instruction{.CloseBracket})
				case ',': append(&macro_instructions, Instruction{.Input})
				case '.': append(&macro_instructions, Instruction{.Output})
			}
			parsing_info.lexer = parsing_info.lexer[1:]
		case char == '{':
			err := read_macro_call(parsing_info, &macro_instructions)
			if err != .None do return err
		case char == '}':
			break macro_parsing_loop
		case:
			fmt.printf("Error: Invalid instruction or keyword '%c' in line %d\n", char, parsing_info.line)
			return .Other
		}
	}

	// Read '}'
	skip_whitespaces(parsing_info)
	if parsing_info.lexer[0] != '}' {
		fmt.printf("Error: Macro is missing a } in line %d\n", parsing_info.line)
		return .None
	}
	parsing_info.lexer = parsing_info.lexer[1:]

	// Add macro instructions to definitions
	if macro_name in parsing_info.macro_defs {
		delete_key(&parsing_info.macro_defs, macro_name)	// Overwrite
	}
	parsing_info.macro_defs[macro_name] = macro_instructions[:]

	return .None
}

read_macro_call :: proc(parsing_info: ^ParsingInfo, add_to: ^[dynamic]ByteCode) -> MacroError {
	assert(parsing_info.lexer[0] == '{')

	// Read '{'
	parsing_info.lexer = parsing_info.lexer[1:]

	// Read the macro name
	macro_name, ok := read_macro_name(parsing_info)
	if !ok do return .MissingName

	// Read '}'
	skip_whitespaces(parsing_info)
	if parsing_info.lexer[0] != '}' {
		// fmt.printf("Error: Macro is missing a } in line %d\n", parsing_info.line)
		return .MissingCloseBracket
	}
	parsing_info.lexer = parsing_info.lexer[1:]

	// Paste the bytecodes into the program or macro definition.
	if macro_name not_in parsing_info.macro_defs {
		fmt.printf("Error: Macro %s is not defined, called in line %d\n", macro_name, parsing_info.line)
		return .UndefinedName
	}
	append(add_to, ..parsing_info.macro_defs[macro_name][:])
	return .None
}

read_macro_name :: proc(parsing_info: ^ParsingInfo) -> (string, bool) {
	skip_whitespaces(parsing_info)
	macro_name := make([dynamic]u8)
	for {
		char := parsing_info.lexer[0]
		if char not_in MACRO_NAME_CHARS {
			break
		}
		append(&macro_name, char)
		parsing_info.lexer = parsing_info.lexer[1:]
	}
	if len(macro_name) == 0 {
		fmt.printf("Error: Macro name not provided in line %d\n", parsing_info.line)
		return "", false
	}
	return strings.string_from_ptr(raw_data(macro_name[:]), len(macro_name)), true
}

read_snapshot :: proc(parsing_info: ^ParsingInfo, macro_instruction: ^[dynamic]ByteCode) -> bool {
	assert(parsing_info.lexer[0] == '!')
	starting_line := parsing_info.line

	// Read '!'
	parsing_info.lexer = parsing_info.lexer[1:]

	// Read '('
	skip_whitespaces(parsing_info)
	if parsing_info.lexer[0] != '(' {
		fmt.printf("Error: Invalid snapshot command in line %d. Missing '('\n", starting_line)
		return false
	}
	parsing_info.lexer = parsing_info.lexer[1:]

	// Read range's min integer
	skip_whitespaces(parsing_info)
	if parsing_info.lexer[0] not_in DIGITS {
		fmt.printf("Error: Invalid snapshot command in line %d\n", starting_line)
		return false
	}
	min_digits: [dynamic; 6]u8
	for {
		if len(parsing_info.lexer) == 0 {
			fmt.printf("Error: Invalid snapshot command in line %d\n", starting_line)
			return false
		}
		char := parsing_info.lexer[0]
		if char not_in DIGITS {
			break
		}
		append(&min_digits, char)
		if len(min_digits) == 6 {
			fmt.printf("Error: Snapshot command range is not between 0 and 30000 in line %d\n", starting_line)
			return false
		}
		parsing_info.lexer = parsing_info.lexer[1:]
	}
	min_range, ok := strconv.parse_uint(strings.string_from_ptr(raw_data(min_digits[:]), len(min_digits)), 10)
	assert(ok)

	// Read colon ':'
	skip_whitespaces(parsing_info)
	if parsing_info.lexer[0] != ':' {
		fmt.printf("Error: Invalid snapshot command in line %d. Missing ':'\n", starting_line)
		return false
	}
	parsing_info.lexer = parsing_info.lexer[1:]

	// Read range's max integer
	skip_whitespaces(parsing_info)
	if parsing_info.lexer[0] not_in DIGITS {
		fmt.printf("Error: Invalid snapshot command in line %d\n", starting_line)
		return false
	}
	max_digits: [dynamic; 6]u8
	for {
		if len(parsing_info.lexer) == 0 {
			fmt.printf("Error: Invalid snapshot command in line %d\n", starting_line)
			return false
		}
		char := parsing_info.lexer[0]
		if char not_in DIGITS {
			break
		}
		append(&max_digits, char)
		if len(max_digits) == 6 {
			fmt.printf("Error: Snapshot command range is not between 0 and 29999 in line %d\n", starting_line)
			return false
		}
		parsing_info.lexer = parsing_info.lexer[1:]
	}
	max_range: uint
	max_range, ok = strconv.parse_uint(strings.string_from_ptr(raw_data(max_digits[:]), len(max_digits)), 10)
	assert(ok)

	// Read ')'
	skip_whitespaces(parsing_info)
	if parsing_info.lexer[0] != ')' {
		fmt.printf("Error: Invalid snapshot command in line %d. Missing ')'\n", starting_line)
		return false
	}
	parsing_info.lexer = parsing_info.lexer[1:]

	// Confirm the range is valid
	if min_range >= max_range || min_range >= 30_000 || max_range >= 30_000 {
		fmt.printf("Error: Invalid snapshot command range in line %d\n", starting_line)
		return false
	}
	if macro_instruction == nil {
		append(&parsing_info.final_instructions, Snapshot{u16(min_range), u16(max_range)})
	} else {
		append(macro_instruction, Snapshot{u16(min_range), u16(max_range)})
	}
	return true
}

read_comment :: proc(parsing_info: ^ParsingInfo) -> bool {
	assert(parsing_info.lexer[0] == '\"')
	starting_line := parsing_info.line
	for i in 1..<len(parsing_info.lexer) {
		if len(parsing_info.lexer) <= 1 do break	// If the quotes is right at the end of the file.
		if parsing_info.lexer[i] == '\n' {
			parsing_info.line += 1
		}
		if parsing_info.lexer[i] == '\"' {
			parsing_info.lexer = parsing_info.lexer[i + 1:]
			return true
		}
	}
	fmt.printf("Error: Missing double quotes in line %d\n", starting_line)
	return false
}

skip_whitespaces :: proc(parsing_info: ^ParsingInfo) {
	for {
		if len(parsing_info.lexer) == 0 do return
		char := parsing_info.lexer[0]
		if char in WHITESPACES {
			if char == '\n' {
				parsing_info.line += 1
			}
			parsing_info.lexer = parsing_info.lexer[1:]
			continue
		}
		return 
	}
}
