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
    push_const_int: u64,
};

const VMTrap = error{
    // Arithmetic errors
    IntegerOverflow,
    DivByZero,

    // Type errors
    TypeMismatch,

    // Stack errors
    StackUnderflow,
    StackOverflow,
};

const VM = struct {
    stack: [MAX_STACK_SIZE]Word,
    stack_pointer: usize,
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    allocator: std.mem.Allocator,

    pub fn init() VM {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const self = VM{
            .stack = [_]Word{0} ** MAX_STACK_SIZE,
            .stack_pointer = 0,
            .gpa = gpa,
            .allocator = gpa.allocator(),
        };
        return self;
    }

    pub fn deinit(self: *VM) void {
        _ = self.gpa.deinit();
    }

    pub fn exec(self: *VM, instruction: Instruction) VMTrap!void {
        switch (instruction) {
            .add => {
                const b = try self.pop_int();
                const a = try self.pop_int();
                const result = std.math.add(Word, a, b) catch return error.IntegerOverflow;
                try self.push_int(result);
            },
            .sub => {
                const b = try self.pop_int();
                const a = try self.pop_int();
                const result = std.math.sub(Word, a, b) catch return error.IntegerOverflow;
                try self.push_int(result);
            },
            .mul => {
                const b = try self.pop_int();
                const a = try self.pop_int();
                const result = std.math.mul(Word, a, b) catch return error.IntegerOverflow;
                try self.push_int(result);
            },
            .div => {
                const b = try self.pop_int();
                const a = try self.pop_int();
                if (b == 0) return error.DivByZero;
                try self.push_int(a / b);
            },
            .dup => {
                if (self.stack_pointer >= MAX_STACK_SIZE) return error.StackOverflow;
                self.stack[self.stack_pointer] = self.stack[self.stack_pointer - 1];
                self.stack_pointer += 1;
            },
            .drop => {
                if (self.stack_pointer == 0) return error.StackUnderflow;
                self.stack_pointer -= 1;
            },
            .push_const_int => |value| {
                if (self.stack_pointer >= MAX_STACK_SIZE) return error.StackOverflow;
                self.stack[self.stack_pointer] = value;
                self.stack_pointer += 1;
            },
        }
    }

    fn pop_int(self: *VM) VMTrap!Word {
        if (self.stack_pointer == 0) return error.StackUnderflow;
        self.stack_pointer -= 1;
        return self.stack[self.stack_pointer];
    }

    fn push_int(self: *VM, value: Word) VMTrap!void {
        if (self.stack_pointer >= MAX_STACK_SIZE) return error.StackOverflow;
        self.stack[self.stack_pointer] = value;
        self.stack_pointer += 1;
    }

    fn alloc_int(_: *VM, value: u64) VMTrap!Word {
        return value;
    }
};

pub fn main() !void {
    var vm = VM.init();
    defer vm.deinit();

    // Test push and add
    try vm.exec(.{ .push_const_int = 1 });
    try vm.exec(.{ .push_const_int = 2 });
    print_vm(&vm);
    try vm.exec(.add);
    print_vm(&vm);
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
    var vm = VM.init();
    defer vm.deinit();

    // Test push_const_int
    try vm.exec(.{ .push_const_int = 42 });
    try std.testing.expectEqual(@as(usize, 1), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);

    // Test dup
    try vm.exec(.dup);
    try std.testing.expectEqual(@as(usize, 2), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[1]);

    // Test drop
    try vm.exec(.drop);
    try std.testing.expectEqual(@as(usize, 1), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);

    // Test multiple push operations
    try vm.exec(.{ .push_const_int = 10 });
    try vm.exec(.{ .push_const_int = 20 });
    try vm.exec(.{ .push_const_int = 30 });
    try std.testing.expectEqual(@as(usize, 4), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);
    try std.testing.expectEqual(@as(Word, 10), vm.stack[1]);
    try std.testing.expectEqual(@as(Word, 20), vm.stack[2]);
    try std.testing.expectEqual(@as(Word, 30), vm.stack[3]);

    // Test multiple drops
    try vm.exec(.drop);
    try vm.exec(.drop);
    try std.testing.expectEqual(@as(usize, 2), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);
    try std.testing.expectEqual(@as(Word, 10), vm.stack[1]);

    // Test dup with multiple items on stack
    try vm.exec(.dup);
    try std.testing.expectEqual(@as(usize, 3), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), vm.stack[0]);
    try std.testing.expectEqual(@as(Word, 10), vm.stack[1]);
    try std.testing.expectEqual(@as(Word, 10), vm.stack[2]);
}

test "VM integer overflow" {
    var vm = VM.init();
    defer vm.deinit();

    // Test addition overflow
    try vm.exec(.{ .push_const_int = std.math.maxInt(Word) });
    try vm.exec(.{ .push_const_int = 1 });
    try std.testing.expectError(error.IntegerOverflow, vm.exec(.add));

    // Reset stack
    vm.stack_pointer = 0;

    // Test subtraction overflow (underflow)
    try vm.exec(.{ .push_const_int = 0 });
    try vm.exec(.{ .push_const_int = 1 });
    try std.testing.expectError(error.IntegerOverflow, vm.exec(.sub));

    // Reset stack
    vm.stack_pointer = 0;

    // Test multiplication overflow
    try vm.exec(.{ .push_const_int = std.math.maxInt(Word) });
    try vm.exec(.{ .push_const_int = 2 });
    try std.testing.expectError(error.IntegerOverflow, vm.exec(.mul));

    // Reset stack
    vm.stack_pointer = 0;

    // Test large multiplication overflow
    try vm.exec(.{ .push_const_int = std.math.maxInt(Word) / 2 + 1 });
    try vm.exec(.{ .push_const_int = 2 });
    try std.testing.expectError(error.IntegerOverflow, vm.exec(.mul));
}

test "VM stack underflow" {
    var vm = VM.init();
    defer vm.deinit();

    // Test underflow on empty stack
    try std.testing.expectError(error.StackUnderflow, vm.exec(.add));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.sub));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.mul));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.div));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.drop));

    // Test underflow with only one item on stack
    try vm.exec(.{ .push_const_int = 5 });
    try std.testing.expectError(error.StackUnderflow, vm.exec(.add));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.sub));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.mul));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.div));
}

test "VM stack overflow" {
    var vm = VM.init();
    defer vm.deinit();

    // Fill the stack to capacity
    var i: usize = 0;
    while (i < MAX_STACK_SIZE) : (i += 1) {
        try vm.exec(.{ .push_const_int = @intCast(i) });
    }

    // Next push should overflow
    try std.testing.expectError(error.StackOverflow, vm.exec(.{ .push_const_int = 100 }));
    try std.testing.expectError(error.StackOverflow, vm.exec(.dup));
}

test "VM division by zero" {
    var vm = VM.init();
    defer vm.deinit();

    try vm.exec(.{ .push_const_int = 10 });
    try vm.exec(.{ .push_const_int = 0 });
    try std.testing.expectError(error.DivByZero, vm.exec(.div));
}

test "VM arithmetic operations" {
    var vm = VM.init();
    defer vm.deinit();

    // Test push and add
    try vm.exec(.{ .push_const_int = 1 });
    try vm.exec(.{ .push_const_int = 2 });
    try vm.exec(.add);
    try std.testing.expectEqual(@as(Word, 3), vm.stack[vm.stack_pointer - 1]);

    // Test multiplication
    try vm.exec(.{ .push_const_int = 4 });
    try vm.exec(.mul);
    try std.testing.expectEqual(@as(Word, 12), vm.stack[vm.stack_pointer - 1]);

    // Test subtraction
    try vm.exec(.{ .push_const_int = 2 });
    try vm.exec(.sub);
    try std.testing.expectEqual(@as(Word, 10), vm.stack[vm.stack_pointer - 1]);

    // Test division
    try vm.exec(.{ .push_const_int = 2 });
    try vm.exec(.div);
    try std.testing.expectEqual(@as(Word, 5), vm.stack[vm.stack_pointer - 1]);

    // Test stack underflow
    try std.testing.expectError(error.StackUnderflow, vm.exec(.add));
}
