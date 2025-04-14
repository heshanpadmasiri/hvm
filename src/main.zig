const std = @import("std");

const MAX_STACK_SIZE = 512;
const Word = u64;

const Instruction = union(enum) {
    // Arithmetic instructions
    add,
    sub,
    mul,
    div,

    // Stack manipulation instructions
    dup,
    drop,
    push_const: Word,
};

const VMTrap = error{
    // Arithmetic errors
    IntegerOverflow,
    DivByZero,

    // Stack errors
    StackUnderflow,
    StackOverflow,
};

const VM = struct {
    stack: [MAX_STACK_SIZE]Word,
    stack_pointer: usize,
};

pub fn main() !void {
    // Empty main function since we're using tests
    var vm = VM{
        .stack = [_]Word{0} ** MAX_STACK_SIZE,
        .stack_pointer = 0,
    };

    // Test push and add
    try exec(&vm, .{ .push_const = 1 });
    try exec(&vm, .{ .push_const = 2 });
    print_vm(&vm);
    try exec(&vm, .add);
    print_vm(&vm);
}

fn exec(vm: *VM, instruction: Instruction) VMTrap!void {
    switch (instruction) {
        .add => {
            if (vm.stack_pointer < 2) return error.StackUnderflow;
            const a = vm.stack[vm.stack_pointer - 2];
            const b = vm.stack[vm.stack_pointer - 1];
            vm.stack[vm.stack_pointer - 2] = std.math.add(Word, a, b) catch return error.IntegerOverflow;
            vm.stack_pointer -= 1;
        },
        .sub => {
            if (vm.stack_pointer < 2) return error.StackUnderflow;
            const a = vm.stack[vm.stack_pointer - 2];
            const b = vm.stack[vm.stack_pointer - 1];
            vm.stack[vm.stack_pointer - 2] = std.math.sub(Word, a, b) catch return error.IntegerOverflow;
            vm.stack_pointer -= 1;
        },
        .mul => {
            if (vm.stack_pointer < 2) return error.StackUnderflow;
            const a = vm.stack[vm.stack_pointer - 2];
            const b = vm.stack[vm.stack_pointer - 1];
            vm.stack[vm.stack_pointer - 2] = std.math.mul(Word, a, b) catch return error.IntegerOverflow;
            vm.stack_pointer -= 1;
        },
        .div => {
            if (vm.stack_pointer < 2) return error.StackUnderflow;
            if (vm.stack[vm.stack_pointer - 1] == 0) return error.DivByZero;
            // Division by zero is already handled so we can't overflow
            vm.stack[vm.stack_pointer - 2] /= vm.stack[vm.stack_pointer - 1];
            vm.stack_pointer -= 1;
        },
        .dup => {
            if (vm.stack_pointer >= MAX_STACK_SIZE) return error.StackOverflow;
            vm.stack[vm.stack_pointer] = vm.stack[vm.stack_pointer - 1];
            vm.stack_pointer += 1;
        },
        .drop => {
            if (vm.stack_pointer == 0) return error.StackUnderflow;
            vm.stack_pointer -= 1;
        },
        .push_const => |value| {
            if (vm.stack_pointer >= MAX_STACK_SIZE) return error.StackOverflow;
            vm.stack[vm.stack_pointer] = value;
            vm.stack_pointer += 1;
        },
    }
}

fn print_vm(vm: *const VM) void {
    if (vm.stack_pointer == 0) {
        std.debug.print("Stack is empty\n", .{});
        return;
    }

    std.debug.print("Stack: ", .{});
    for (vm.stack[0..vm.stack_pointer]) |value| {
        std.debug.print("{d} ", .{value});
    }
    std.debug.print("\n", .{});
}

test "VM stack manipulation instructions" {
    var vm = VM{
        .stack = [_]Word{0} ** MAX_STACK_SIZE,
        .stack_pointer = 0,
    };

    // Test push_const
    try exec(&vm, .{ .push_const = 42 });
    try std.testing.expectEqual(@as(usize, 1), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);

    // Test dup
    try exec(&vm, .dup);
    try std.testing.expectEqual(@as(usize, 2), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[1]);

    // Test drop
    try exec(&vm, .drop);
    try std.testing.expectEqual(@as(usize, 1), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);

    // Test multiple push operations
    try exec(&vm, .{ .push_const = 10 });
    try exec(&vm, .{ .push_const = 20 });
    try exec(&vm, .{ .push_const = 30 });
    try std.testing.expectEqual(@as(usize, 4), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);
    try std.testing.expectEqual(@as(Word, 10), vm.stack[1]);
    try std.testing.expectEqual(@as(Word, 20), vm.stack[2]);
    try std.testing.expectEqual(@as(Word, 30), vm.stack[3]);

    // Test multiple drops
    try exec(&vm, .drop);
    try exec(&vm, .drop);
    try std.testing.expectEqual(@as(usize, 2), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);
    try std.testing.expectEqual(@as(Word, 10), vm.stack[1]);

    // Test dup with multiple items on stack
    try exec(&vm, .dup);
    try std.testing.expectEqual(@as(usize, 3), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);
    try std.testing.expectEqual(@as(Word, 10), vm.stack[1]);
    try std.testing.expectEqual(@as(Word, 10), vm.stack[2]);
}

test "VM integer overflow" {
    var vm = VM{
        .stack = [_]Word{0} ** MAX_STACK_SIZE,
        .stack_pointer = 0,
    };

    // Test addition overflow
    try exec(&vm, .{ .push_const = std.math.maxInt(Word) });
    try exec(&vm, .{ .push_const = 1 });
    try std.testing.expectError(error.IntegerOverflow, exec(&vm, .add));

    // Reset stack
    vm.stack_pointer = 0;

    // Test subtraction overflow (underflow)
    try exec(&vm, .{ .push_const = 0 });
    try exec(&vm, .{ .push_const = 1 });
    try std.testing.expectError(error.IntegerOverflow, exec(&vm, .sub));

    // Reset stack
    vm.stack_pointer = 0;

    // Test multiplication overflow
    try exec(&vm, .{ .push_const = std.math.maxInt(Word) });
    try exec(&vm, .{ .push_const = 2 });
    try std.testing.expectError(error.IntegerOverflow, exec(&vm, .mul));

    // Reset stack
    vm.stack_pointer = 0;

    // Test large multiplication overflow
    try exec(&vm, .{ .push_const = std.math.maxInt(Word) / 2 + 1 });
    try exec(&vm, .{ .push_const = 2 });
    try std.testing.expectError(error.IntegerOverflow, exec(&vm, .mul));
}

test "VM stack underflow" {
    var vm = VM{
        .stack = [_]Word{0} ** MAX_STACK_SIZE,
        .stack_pointer = 0,
    };

    // Test underflow on empty stack
    try std.testing.expectError(error.StackUnderflow, exec(&vm, .add));
    try std.testing.expectError(error.StackUnderflow, exec(&vm, .sub));
    try std.testing.expectError(error.StackUnderflow, exec(&vm, .mul));
    try std.testing.expectError(error.StackUnderflow, exec(&vm, .div));
    try std.testing.expectError(error.StackUnderflow, exec(&vm, .drop));

    // Test underflow with only one item on stack
    try exec(&vm, .{ .push_const = 5 });
    try std.testing.expectError(error.StackUnderflow, exec(&vm, .add));
    try std.testing.expectError(error.StackUnderflow, exec(&vm, .sub));
    try std.testing.expectError(error.StackUnderflow, exec(&vm, .mul));
    try std.testing.expectError(error.StackUnderflow, exec(&vm, .div));
}

test "VM stack overflow" {
    var vm = VM{
        .stack = [_]Word{0} ** MAX_STACK_SIZE,
        .stack_pointer = 0,
    };

    // Fill the stack to capacity
    var i: usize = 0;
    while (i < MAX_STACK_SIZE) : (i += 1) {
        try exec(&vm, .{ .push_const = @intCast(i) });
    }

    // Next push should overflow
    try std.testing.expectError(error.StackOverflow, exec(&vm, .{ .push_const = 100 }));
    try std.testing.expectError(error.StackOverflow, exec(&vm, .dup));
}

test "VM division by zero" {
    var vm = VM{
        .stack = [_]Word{0} ** MAX_STACK_SIZE,
        .stack_pointer = 0,
    };

    try exec(&vm, .{ .push_const = 10 });
    try exec(&vm, .{ .push_const = 0 });
    try std.testing.expectError(error.DivByZero, exec(&vm, .div));
}

test "VM arithmetic operations" {
    var vm = VM{
        .stack = [_]Word{0} ** MAX_STACK_SIZE,
        .stack_pointer = 0,
    };

    // Test push and add
    try exec(&vm, .{ .push_const = 1 });
    try exec(&vm, .{ .push_const = 2 });
    try exec(&vm, .add);
    try std.testing.expectEqual(@as(Word, 3), vm.stack[vm.stack_pointer - 1]);

    // Test multiplication
    try exec(&vm, .{ .push_const = 4 });
    try exec(&vm, .mul);
    try std.testing.expectEqual(@as(Word, 12), vm.stack[vm.stack_pointer - 1]);

    // Test subtraction
    try exec(&vm, .{ .push_const = 2 });
    try exec(&vm, .sub);
    try std.testing.expectEqual(@as(Word, 10), vm.stack[vm.stack_pointer - 1]);

    // Test division
    try exec(&vm, .{ .push_const = 2 });
    try exec(&vm, .div);
    try std.testing.expectEqual(@as(Word, 5), vm.stack[vm.stack_pointer - 1]);

    // Test stack underflow
    try std.testing.expectError(error.StackUnderflow, exec(&vm, .add));
}
