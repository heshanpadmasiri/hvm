# Heshan's Virtual Machine (HVM)
Simple, but turing complete virtual machine developed mostly because I was too bored to do anything else.

# Instructions

## Arithmetic Instructions
- `add`: Pops two integers from the stack, adds them, and pushes the result
- `sub`: Pops two integers from the stack, subtracts the second from the first, and pushes the result
- `mul`: Pops two integers from the stack, multiplies them, and pushes the result
- `div`: Pops two integers from the stack, divides the first by the second, and pushes the result
- `i_comp`: Pops two integers from the stack and performs a comparison operation:
  - `eq`: Equal to
  - `ne`: Not equal to
  - `lt`: Less than
  - `gt`: Greater than
  - `lte`: Less than or equal to
  - `gte`: Greater than or equal to
  Pushes a boolean result (true/false)

## String Instructions
- `concat`: Pops two strings from the stack, concatenates them, and pushes the result
- `str_eq`: Pops two strings from the stack, compares them for equality, and pushes a boolean result

## Boolean Instructions
- `or`: Pops two booleans from the stack, performs logical OR, and pushes the result
- `and`: Pops two booleans from the stack, performs logical AND, and pushes the result
- `not`: Pops one boolean from the stack, performs logical NOT, and pushes the result

## Stack Manipulation Instructions
- `dup`: Duplicates the top value on the stack
- `drop`: Removes the top value from the stack

## Value Creation Instructions
- `push_int`: Pushes an integer value onto the stack
- `push_string`: Pushes a string value onto the stack
- `push_boolean`: Pushes a boolean value onto the stack

## Control Flow Instructions
- `halt`: Stops program execution
- `jmp`: Unconditionally jumps to a specified instruction index
- `cond_jmp`: Conditionally jumps to a specified instruction index if the top of stack is true

## Error Handling
The VM can raise the following errors:
- `IntegerOverflow`: When an arithmetic operation results in an overflow
- `DivByZero`: When attempting to divide by zero
- `TypeMismatch`: When operations are performed on incompatible types
- `StackUnderflow`: When attempting to pop from an empty stack
- `StackOverflow`: When attempting to push to a full stack
- `OutOfMemory`: When memory allocation fails
- `ProgramOverflow`: When program execution reaches the end without a halt instruction

