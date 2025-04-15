const std = @import("std");

const MAX_STACK_SIZE = 512;
const Word = u64;

// Pointer packing constants
const TAG_SIZE: u6 = 3;
const TAG_MASK: u64 = (1 << TAG_SIZE) - 1;
const IMMEDIATE_BIT: u64 = 0x1;
const TYPE_TAG_SIZE: u6 = 8;
const TYPE_MASK: u64 = 0xFF00000000000000;
const POINTER_MASK: u64 = ~(TAG_MASK | TYPE_MASK);

const MAX_IMMEDIATE_INT: u64 = (1 << @as(usize, 64 - @as(usize, TYPE_TAG_SIZE) - @as(usize, TAG_SIZE))) - 1;

const ValueType = enum(u8) {
    integer = 0x01,
    string = 0x02,
    boolean = 0x03,
};

const StringValue = struct {
    len: usize,
    bytes: []u8,
};

const Instruction = union(enum) {
    // Arithmetic instructions
    add,
    sub,
    mul,
    div,

    // String instructions
    concat,

    // Stack manipulation instructions
    dup,
    drop,

    // Value creation instructions
    push_int: u64,
    push_string: []const u8,
    push_boolean: bool,
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
    OutOfMemory,
};

fn value_type(word: Word) ValueType {
    return @as(ValueType, @enumFromInt((word & TYPE_MASK) >> 56));
}

fn type_mask(ty: ValueType) u64 {
    return (@as(u64, @intFromEnum(ty)) << 56);
}

const VM = struct {
    stack: [MAX_STACK_SIZE]Word,
    stack_pointer: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) VM {
        const self = VM{
            .stack = [_]Word{0} ** MAX_STACK_SIZE,
            .stack_pointer = 0,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: *VM) void {
        for (self.stack[0..self.stack_pointer]) |word| {
            if (is_pointer(word)) {
                const ptr = unpack_pointer(word);
                self.free(ptr, value_type(word));
            }
        }
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
            .concat => {
                const result = try self.string_concat();
                try self.push_string_owned(result);
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
            .push_int => |value| {
                try self.push_int(value);
            },
            .push_string => |str| {
                try self.push_string(str);
            },
            .push_boolean => |value| {
                try self.push_boolean(value);
            },
        }
    }

    fn string_concat(self: *VM) VMTrap![]u8 {
        const b_result = try self.pop_string_value();
        defer self.free(b_result.ptr, ValueType.string);
        const a_result = try self.pop_string_value();
        defer self.free(a_result.ptr, ValueType.string);
        const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ a_result.string_value.bytes, b_result.string_value.bytes });
        return result;
    }

    fn pop_int(self: *VM) VMTrap!Word {
        if (self.stack_pointer == 0) return error.StackUnderflow;
        self.stack_pointer -= 1;
        const word = self.stack[self.stack_pointer];
        const ty = value_type(word);
        if (ty != ValueType.integer) return error.TypeMismatch;

        if (is_immediate(word)) {
            const value = unpack_immediate(word);
            return value;
        }
        const ptr = unpack_pointer(word);
        const aligned_ptr = @as(*align(8) anyopaque, @alignCast(ptr));
        const value = @as(*align(8) u64, @ptrCast(aligned_ptr)).*;
        self.free(ptr, ty);
        return value;
    }

    fn pop_string(self: *VM) VMTrap![]const u8 {
        const pop_result = try self.pop_string_value();
        const ptr = pop_result.ptr;
        const string_value = pop_result.string_value;

        // Make a copy of the string bytes
        const result = try self.allocator.alloc(u8, string_value.len);
        @memcpy(result, string_value.bytes);

        self.free(ptr, ValueType.string);
        return result;
    }

    fn pop_string_value(self: *VM) VMTrap!struct { ptr: *anyopaque, string_value: *StringValue } {
        if (self.stack_pointer == 0) return error.StackUnderflow;
        self.stack_pointer -= 1;
        const word = self.stack[self.stack_pointer];
        const ty = value_type(word);
        if (ty != ValueType.string) return error.TypeMismatch;

        const ptr = unpack_pointer(word);
        const aligned_ptr = @as(*align(8) anyopaque, @alignCast(ptr));
        const string_value = @as(*StringValue, @ptrCast(aligned_ptr));
        return .{ .ptr = ptr, .string_value = string_value };
    }

    fn pop_boolean(self: *VM) VMTrap!bool {
        if (self.stack_pointer == 0) return error.StackUnderflow;
        self.stack_pointer -= 1;
        const word = self.stack[self.stack_pointer];
        const ty = value_type(word);
        if (ty != ValueType.boolean) return error.TypeMismatch;
        std.debug.assert(is_immediate(word));

        const value = unpack_immediate(word);
        return value != 0;
    }

    fn push_boolean(self: *VM, value: bool) VMTrap!void {
        if (self.stack_pointer >= MAX_STACK_SIZE) return error.StackOverflow;
        const word = if (value) pack_immediate(1, ValueType.boolean) else pack_immediate(0, ValueType.boolean);
        self.stack[self.stack_pointer] = word;
        self.stack_pointer += 1;
    }

    fn push_int(self: *VM, value: u64) VMTrap!void {
        if (self.stack_pointer >= MAX_STACK_SIZE) return error.StackOverflow;
        const word = if (value <= MAX_IMMEDIATE_INT)
            pack_immediate(value, ValueType.integer)
        else
            try alloc_int(self, value);
        self.stack[self.stack_pointer] = word;
        self.stack_pointer += 1;
    }

    fn push_string(self: *VM, str: []const u8) VMTrap!void {
        if (self.stack_pointer >= MAX_STACK_SIZE) return error.StackOverflow;
        const word = try alloc_string(self, str);
        self.stack[self.stack_pointer] = word;
        self.stack_pointer += 1;
    }

    fn push_string_owned(self: *VM, str: []u8) VMTrap!void {
        if (self.stack_pointer >= MAX_STACK_SIZE) return error.StackOverflow;
        const word = try string_value_from_owned(self, str);
        self.stack[self.stack_pointer] = word;
        self.stack_pointer += 1;
    }

    fn string_value_from_owned(self: *VM, str: []u8) VMTrap!Word {
        const string_value = try self.allocator.create(StringValue);
        string_value.* = .{
            .len = str.len,
            .bytes = str,
        };
        return pack_pointer(string_value, ValueType.string, 0);
    }

    fn alloc_string(self: *VM, str: []const u8) VMTrap!Word {
        const string_value = try self.allocator.create(StringValue);
        string_value.* = .{
            .len = str.len,
            .bytes = try self.allocator.alloc(u8, str.len),
        };
        @memcpy(string_value.bytes, str);
        return pack_pointer(string_value, ValueType.string, 0);
    }

    fn alloc_int(self: *VM, value: u64) VMTrap!Word {
        const bytes = try self.alloc(@sizeOf(u64));
        const aligned_ptr = @as([*]align(8) u8, @alignCast(bytes.ptr));
        const ptr = @as([*]u64, @ptrCast(aligned_ptr));
        ptr[0] = value;
        return pack_pointer(bytes.ptr, ValueType.integer, 0);
    }

    fn alloc(self: *VM, n: usize) VMTrap![]u8 {
        return try self.allocator.alignedAlloc(u8, 8, n);
    }

    fn free(self: *VM, ptr: *anyopaque, ty: ValueType) void {
        if (ty == ValueType.string) {
            const aligned_ptr = @as(*align(8) anyopaque, @alignCast(ptr));
            const string_value = @as(*StringValue, @ptrCast(aligned_ptr));
            self.allocator.free(string_value.bytes);
            self.allocator.destroy(string_value);
        } else {
            const aligned_ptr = @as(*align(8) anyopaque, @alignCast(ptr));
            const ptr_slice = @as([*]align(8) u8, @ptrCast(aligned_ptr))[0..@sizeOf(u64)];
            self.allocator.free(ptr_slice);
        }
    }
};

// Helper functions for pointer packing
fn is_pointer(word: Word) bool {
    return (word & TYPE_MASK) != 0 and (word & IMMEDIATE_BIT) == 0;
}

fn is_immediate(word: Word) bool {
    return (word & IMMEDIATE_BIT) != 0;
}

fn pack_pointer(ptr: *anyopaque, ty: ValueType, tag: u3) Word {
    const ptr_value = @intFromPtr(ptr);
    return type_mask(ty) | (ptr_value & POINTER_MASK) | tag;
}

fn pack_immediate(value: u64, ty: ValueType) Word {
    const shifted_value = value << TAG_SIZE;
    return type_mask(ty) | (shifted_value & POINTER_MASK) | IMMEDIATE_BIT;
}

fn unpack_pointer(word: Word) *anyopaque {
    return @ptrFromInt(word & POINTER_MASK);
}

fn unpack_immediate(word: Word) u64 {
    return (word & POINTER_MASK) >> TAG_SIZE;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var vm = VM.init(gpa.allocator());
    defer vm.deinit();

    // Test push and add
    try vm.exec(.{ .push_int = 1 });
    try vm.exec(.{ .push_int = 2 });
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var vm = VM.init(gpa.allocator());
    defer vm.deinit();

    // Test push_int
    try vm.exec(.{ .push_int = 42 });
    try std.testing.expectEqual(@as(usize, 1), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), try vm.pop_int());

    // Test dup
    try vm.exec(.{ .push_int = 42 });
    try vm.exec(.dup);
    try std.testing.expectEqual(@as(usize, 2), vm.stack_pointer);
    const val1 = try vm.pop_int();
    const val2 = try vm.pop_int();
    try std.testing.expectEqual(@as(Word, 42), val1);
    try std.testing.expectEqual(@as(Word, 42), val2);

    // Test drop
    try vm.exec(.{ .push_int = 42 });
    try vm.exec(.drop);
    try std.testing.expectEqual(@as(usize, 0), vm.stack_pointer);

    // Test multiple push operations
    try vm.exec(.{ .push_int = 10 });
    try vm.exec(.{ .push_int = 20 });
    try vm.exec(.{ .push_int = 30 });
    try std.testing.expectEqual(@as(usize, 3), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 30), try vm.pop_int());
    try std.testing.expectEqual(@as(Word, 20), try vm.pop_int());
    try std.testing.expectEqual(@as(Word, 10), try vm.pop_int());

    // Test multiple drops
    try vm.exec(.{ .push_int = 42 });
    try vm.exec(.{ .push_int = 10 });
    try vm.exec(.drop);
    try std.testing.expectEqual(@as(usize, 1), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 42), try vm.pop_int());

    // Test dup with multiple items on stack
    try vm.exec(.{ .push_int = 10 });
    try vm.exec(.dup);
    try std.testing.expectEqual(@as(usize, 2), vm.stack_pointer);
    try std.testing.expectEqual(@as(Word, 10), try vm.pop_int());
    try std.testing.expectEqual(@as(Word, 10), try vm.pop_int());
}

test "VM integer overflow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var vm = VM.init(gpa.allocator());
    defer vm.deinit();

    // Test addition overflow
    try vm.exec(.{ .push_int = std.math.maxInt(Word) });
    try vm.exec(.{ .push_int = 1 });
    try std.testing.expectError(error.IntegerOverflow, vm.exec(.add));

    // Reset stack
    vm.stack_pointer = 0;

    // Test subtraction overflow (underflow)
    try vm.exec(.{ .push_int = 0 });
    try vm.exec(.{ .push_int = 1 });
    try std.testing.expectError(error.IntegerOverflow, vm.exec(.sub));

    // Reset stack
    vm.stack_pointer = 0;

    // Test multiplication overflow
    try vm.exec(.{ .push_int = std.math.maxInt(Word) });
    try vm.exec(.{ .push_int = 2 });
    try std.testing.expectError(error.IntegerOverflow, vm.exec(.mul));

    // Reset stack
    vm.stack_pointer = 0;

    // Test large multiplication overflow
    try vm.exec(.{ .push_int = std.math.maxInt(Word) / 2 + 1 });
    try vm.exec(.{ .push_int = 2 });
    try std.testing.expectError(error.IntegerOverflow, vm.exec(.mul));
}

test "VM stack underflow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var vm = VM.init(gpa.allocator());
    defer vm.deinit();

    // Test underflow on empty stack
    try std.testing.expectError(error.StackUnderflow, vm.exec(.add));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.sub));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.mul));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.div));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.drop));

    // Test underflow with only one item on stack
    try vm.exec(.{ .push_int = 5 });
    try std.testing.expectError(error.StackUnderflow, vm.exec(.add));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.sub));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.mul));
    try std.testing.expectError(error.StackUnderflow, vm.exec(.div));
}

test "VM stack overflow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var vm = VM.init(gpa.allocator());
    defer vm.deinit();

    // Fill the stack to capacity
    var i: usize = 0;
    while (i < MAX_STACK_SIZE) : (i += 1) {
        try vm.exec(.{ .push_int = @intCast(i) });
    }

    // Next push should overflow
    try std.testing.expectError(error.StackOverflow, vm.exec(.{ .push_int = 100 }));
    try std.testing.expectError(error.StackOverflow, vm.exec(.dup));
}

test "VM division by zero" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var vm = VM.init(gpa.allocator());
    defer vm.deinit();

    try vm.exec(.{ .push_int = 10 });
    try vm.exec(.{ .push_int = 0 });
    try std.testing.expectError(error.DivByZero, vm.exec(.div));
}

test "VM arithmetic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var vm = VM.init(gpa.allocator());
    defer vm.deinit();

    // Test push and add
    try vm.exec(.{ .push_int = 1 });
    try vm.exec(.{ .push_int = 2 });
    try vm.exec(.add);
    try std.testing.expectEqual(@as(Word, 3), try vm.pop_int());

    // Test multiplication
    try vm.exec(.{ .push_int = 3 });
    try vm.exec(.{ .push_int = 4 });
    try vm.exec(.mul);
    try std.testing.expectEqual(@as(Word, 12), try vm.pop_int());

    // Test subtraction and division
    try vm.exec(.{ .push_int = 12 });
    try vm.exec(.{ .push_int = 2 });
    try vm.exec(.sub);
    try std.testing.expectEqual(@as(Word, 10), try vm.pop_int());

    try vm.exec(.{ .push_int = 10 });
    try vm.exec(.{ .push_int = 2 });
    try vm.exec(.div);
    try std.testing.expectEqual(@as(Word, 5), try vm.pop_int());

    // Test stack underflow
    try std.testing.expectError(error.StackUnderflow, vm.exec(.add));
}

test "VM arithmetic operations with non-immediate values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var vm = VM.init(gpa.allocator());
    defer vm.deinit();

    // Create a value that will be non-immediate (larger than MAX_IMMEDIATE_INT)
    const large_value = MAX_IMMEDIATE_INT + 1;

    // Test addition with non-immediate values
    try vm.exec(.{ .push_int = large_value });
    try vm.exec(.{ .push_int = large_value });
    try vm.exec(.add);
    try std.testing.expectEqual(@as(Word, large_value * 2), try vm.pop_int());

    // Test multiplication with non-immediate values
    try vm.exec(.{ .push_int = large_value });
    try vm.exec(.{ .push_int = 2 });
    try vm.exec(.mul);
    try std.testing.expectEqual(@as(Word, large_value * 2), try vm.pop_int());

    // Test subtraction with non-immediate values
    try vm.exec(.{ .push_int = large_value * 2 });
    try vm.exec(.{ .push_int = large_value });
    try vm.exec(.sub);
    try std.testing.expectEqual(@as(Word, large_value), try vm.pop_int());

    // Test division with non-immediate values
    try vm.exec(.{ .push_int = large_value * 2 });
    try vm.exec(.{ .push_int = 2 });
    try vm.exec(.div);
    try std.testing.expectEqual(@as(Word, large_value), try vm.pop_int());

    // Test mixed immediate and non-immediate operations
    try vm.exec(.{ .push_int = large_value });
    try vm.exec(.{ .push_int = 1 }); // This will be immediate
    try vm.exec(.add);
    try std.testing.expectEqual(@as(Word, large_value + 1), try vm.pop_int());
}

test "VM string operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var vm = VM.init(gpa.allocator());
    defer vm.deinit();

    // Test pushing a string to the stack
    const test_string = "Hello, World!";
    try vm.exec(.{ .push_string = test_string });

    // Verify we can retrieve the string
    const retrieved = try vm.pop_string();
    defer vm.allocator.free(retrieved);
    try std.testing.expectEqualStrings(test_string, retrieved);

    // Test empty string
    try vm.exec(.{ .push_string = "" });
    const empty = try vm.pop_string();
    defer vm.allocator.free(empty);
    try std.testing.expectEqualStrings("", empty);

    // Test multiple strings
    try vm.exec(.{ .push_string = "First" });
    try vm.exec(.{ .push_string = "Second" });
    const second = try vm.pop_string();
    defer vm.allocator.free(second);
    const first = try vm.pop_string();
    defer vm.allocator.free(first);
    try std.testing.expectEqualStrings("Second", second);
    try std.testing.expectEqualStrings("First", first);

    // Test string concatenation
    try vm.exec(.{ .push_string = "Hello, " });
    try vm.exec(.{ .push_string = "World!" });
    try vm.exec(.concat);
    const concatenated = try vm.pop_string();
    defer vm.allocator.free(concatenated);
    try std.testing.expectEqualStrings("Hello, World!", concatenated);

    // Test stack underflow
    try std.testing.expectError(error.StackUnderflow, vm.pop_string());
}
test "VM boolean operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var vm = VM.init(gpa.allocator());
    defer vm.deinit();

    // Test pushing true boolean value
    try vm.exec(.{ .push_boolean = true });
    try std.testing.expectEqual(true, try vm.pop_boolean());

    // Test pushing false boolean value
    try vm.exec(.{ .push_boolean = false });
    try std.testing.expectEqual(false, try vm.pop_boolean());

    // Test multiple boolean values
    try vm.exec(.{ .push_boolean = true });
    try vm.exec(.{ .push_boolean = false });
    try vm.exec(.{ .push_boolean = true });

    try std.testing.expectEqual(true, try vm.pop_boolean());
    try std.testing.expectEqual(false, try vm.pop_boolean());
    try std.testing.expectEqual(true, try vm.pop_boolean());

    // Test stack underflow
    try std.testing.expectError(error.StackUnderflow, vm.pop_boolean());
}
