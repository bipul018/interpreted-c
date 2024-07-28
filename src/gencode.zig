const std = @import("std");
const vm = @import("engine.zig");



//Model of generation of code:

//Each statement independent 'unit', st each statement cleans up every intermediate
// pushes to the stack
//Each declaration of variable only can make persistent pushes to stack
//For each declaration of variable, increase one value to the offset and go on
// Soo, considering only expressions, arrays and declarations, do a code generation
//
//
//

pub const Expr = struct{
    left: Node,
    right: Node,
    opr: enum{
        //arrget refers to a read of array element, first operand should be variable
        add, sub, mul, div, arrget
    },
};

pub const Node = union(enum){
    expr: *const Expr,
    cval: f64,
    vval: u64,
};

pub fn print_expr(expr: *const Expr, writer: anytype) !void{
    if(expr.opr != .arrget)
        try writer.print("( ", .{});
    try switch(expr.left){
        .cval => writer.print("{d}",.{expr.left.cval}),
        .vval => writer.print(":{}", .{expr.left.vval}),
        .expr => print_expr(expr.left.expr, writer),
    };
    try writer.print(" {s} ", .{switch(expr.opr){
        .add => "+", .sub => "-", .mul => "*", .div => "/",
        .arrget => "[",
    }});
    
    try switch(expr.right){
        .cval => writer.print("{d}",.{expr.right.cval}),
        .vval => writer.print(":{}", .{expr.right.vval}),
        .expr => print_expr(expr.right.expr, writer),
    };
    if(expr.opr != .arrget){
        try writer.print(" )", .{});
    }
    else{
        try writer.print(" ]", .{});
    }
}

test "print single expr"{
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    const expr = Expr{
        .opr = .add,
        .left = .{.cval=1},
        .right= .{.cval=2}
    };

    try print_expr(&expr, arr.writer().any());
    try std.testing.expectEqualSlices(u8, "( 1 + 2 )",
                                      arr.items);
}

test "print one dir expr"{
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    const expr = Expr{
        .opr = .add,
        .left = .{.expr = &.{.opr = .mul,
                             .left = .{.cval=3},
                             .right = .{.cval=-1}
                             }},
        .right= .{.cval=2}
    };

    try print_expr(&expr, arr.writer().any());
    try std.testing.expectEqualSlices(u8, "( ( 3 * -1 ) + 2 )",
                                      arr.items);
}

test "print array get expr"{
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();
    
    const expr = Expr{
        .left = .{.expr = &.{
            .left = .{.vval=1},
            .opr = .arrget,
            .right = .{.vval=0}
        }},
        .opr = .sub,
        .right = .{.expr = &.{
            .left = .{.vval=1},
            .opr = .arrget,
            .right = .{.expr = &.{
                .left = .{.cval=3},
                .opr = .mul,
                .right = .{.vval=0}
    }}}}};

    try print_expr(&expr, arr.writer().any());
    try std.testing.expectEqualSlices(u8, "( :1 [ :0 ] - :1 [ ( 3 * :0 ) ] )",
                                      arr.items);
}

//Build expressions

//Use a hash map to map variables to indexes ?
pub const Variables = std.StringHashMap(u64);

fn is_numtype(thing: type) bool{
    const tinfo = @typeInfo(thing);
    return (tinfo == .ComptimeFloat) or (tinfo == .ComptimeInt) or
        (tinfo == .Int) or (tinfo == .Float);
}

fn is_inttype(thing: type) bool{
    const tinfo = @typeInfo(thing);
    return (tinfo == .ComptimeInt) or
        (tinfo == .Int);
}

fn is_floattype(thing: type) bool{
    const tinfo = @typeInfo(thing);
    return (tinfo == .ComptimeFloat) or
        (tinfo == .Float);
}

//Fxn that creates a single node
fn make_node(node_allocr: std.mem.Allocator, vars: *Variables, node_val: anytype) !Node{
    const ntype = @TypeOf(node_val);

    if(ntype == Expr){
        const expr = try node_allocr.create(Expr);
        expr.* = node_val;
        return Node{.expr = expr};
    }
    if(comptime is_numtype(ntype)){
        if(comptime is_inttype(ntype)){
            return Node{.cval = @floatFromInt(node_val)};
        }
        else{
            return Node{.cval = @floatCast(node_val)};
        }
    }
    if(std.meta.Elem(ntype) == u8){
        return Node{.vval = (try vars.getOrPutValue(node_val, vars.count())).value_ptr.*};
    }
    @compileError("Shouldn't reach here");
}

fn make_expr(node_allocr: std.mem.Allocator, vars: *Variables, left_node: anytype,
             oper: anytype, right_node:anytype) !Expr{

    const lnode = try make_node(node_allocr, vars, left_node);
    // const lnode = switch(@TypeOf(left_node)){
    //     f64 => Node{.cval = left_node},
    //     u64 => Node{.vval = left_node},
    //     *const Expr => Node{.expr = left_node},
    //     else => @compileError("Improper node type found")
    // };
    const rnode = try make_node(node_allocr, vars, right_node);
    // const rnode = switch(@TypeOf(right_node)){
    //     f64 => Node{.cval = right_node},
    //     u64 => Node{.vval = right_node},
    //     *const Expr => Node{.expr = right_node},
    //     else => @compileError("Improper node type found")
    // };
    
    //TODO Check if oper is aray access, if so then left must be a variable
    if((oper == .arrget) and (lnode != .vval)) return error.InvalidOperands;
    return Expr{.left = lnode, .opr = oper, .right = rnode};
}

test "gen expr simple expr" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
        
    {
        var arr = std.ArrayList(u8).init(std.testing.allocator);
        defer arr.deinit();


        var vars = Variables.init(std.testing.allocator);
        defer vars.deinit();
        const expr = try make_expr(arena.allocator(), &vars, 1.2, .add, 3);
        
        try print_expr(&expr, arr.writer().any());
        try std.testing.expectEqualSlices(u8, arr.items,
                                          "( 1.2 + 3 )");
    }
    {
        
        var arr = std.ArrayList(u8).init(std.testing.allocator);
        defer arr.deinit();

        var vars = Variables.init(std.testing.allocator);
        defer vars.deinit();
        const expr = try make_expr(arena.allocator(), &vars, 1.2, .add, @as(f64,3));
        
        try print_expr(&expr, arr.writer().any());
        try std.testing.expectEqualSlices(u8, arr.items,
                                          "( 1.2 + 3 )");
    }
}
test "gen expr nested expr"{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();
    var vars = Variables.init(std.testing.allocator);
    defer vars.deinit();
    const allocr = arena.allocator();

    const expr1 = try make_expr(allocr, &vars, "x", .sub, 34);
    const expr2 = try make_expr(allocr, &vars, "y", .div, expr1);

    try print_expr(&expr2, arr.writer().any());
    try std.testing.expectEqualSlices(u8, arr.items,
                                      "( :1 / ( :0 - 34 ) )");
    arr.clearRetainingCapacity();
    const expr3 = try make_expr(allocr, &vars, "y", .mul, "x");

    try print_expr(&expr3, arr.writer().any());
    try std.testing.expectEqualSlices(u8, arr.items,
                                      "( :1 * :0 )");
}
test "gen arrget expr"{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();
    var vars = Variables.init(std.testing.allocator);
    defer vars.deinit();
    const allocr = arena.allocator();

    const expr1 = try make_expr(allocr, &vars, "x", .arrget, 34);
    const expr2 = make_expr(allocr, &vars, 12, .arrget, "x");
    try std.testing.expectError(error.InvalidOperands, expr2);
    const expr3 = make_expr(allocr, &vars, expr1, .arrget, 1);
    try std.testing.expectError(error.InvalidOperands, expr3);

    
    try print_expr(&expr1, arr.writer().any());
    try std.testing.expectEqualSlices(u8, arr.items,
                                      ":0 [ 34 ]");
}

pub const ExprBuilder = struct{
    const Self = @This();
    vars:?*Variables,
    arena: ?std.heap.ArenaAllocator,
    pub fn init(vartable: *Variables, expr_allocr: std.mem.Allocator) Self{
        return Self{
            .vars = vartable,
            .arena = std.heap.ArenaAllocator.init(expr_allocr),
        };
    }
    pub fn deinit(self: *Self) void{
        self.arena.?.deinit();
        self.vars = null;
        self.arena = null;
    }
    pub fn make(self: *Self, left_node: anytype, oper: anytype, right_node:anytype) !Expr{
        const ln = blk:{
            if(@typeInfo(@TypeOf(left_node)) == .ErrorUnion){
                break :blk (left_node catch |err| {return err;});
            }
            else{
                break :blk left_node;
            }
        };
        const rn = blk:{
            if(@typeInfo(@TypeOf(right_node)) == .ErrorUnion){
                break :blk (right_node catch |err| {return err;});
            }
            else{
                break :blk right_node;
            }
        };
        return make_expr(self.arena.?.allocator(), self.vars.?, ln, oper, rn);
    }
};

test "gen expr by builder"{
    var vars = Variables.init(std.testing.allocator);
    defer vars.deinit();

    var b = ExprBuilder.init(&vars, std.testing.allocator);
    defer b.deinit();
    
    const expr = try b.make(b.make("x",
                                   .add,
                                   b.make("y",
                                          .mul,
                                          4)),
                            .div,
                            b.make(-23.1,
                                   .sub,
                                   b.make("x",
                                          .div,
                                          3)));
        
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    try print_expr(&expr, arr.writer().any());
    try std.
        testing.expectEqualSlices(u8,"( ( :1 + ( :0 * 4 ) ) / ( -23.1 - ( :1 / 3 ) ) )",
                                  arr.items);
                                      
}


//Map from 'Variables' to index in memory
pub const VarHolder = struct{
    vars: Variables,
    locs: std.AutoHashMap(u64, u64),
    used_count: u64 = 0,
    global_off:u64 = 0,
    pub fn init(allocr: std.mem.Allocator) @This(){
        return @This(){
            .vars = Variables.init(allocr),
            .locs = std.AutoHashMap(u64, u64).init(allocr),
            .used_count = 0,
            .global_off = 0,
        };
    }
    pub fn deinit(self: * @This()) void{
        self.vars.deinit();
        self.locs.deinit();
        self.used_count = 0;
    }

    pub fn get_loc(self: * const @This(), var_id: anytype) !u64{
        const var_no = if(comptime is_inttype(@TypeOf(var_id))) var_id
        else self.vars.get(var_id) orelse return error.VariableNotFound;
        const var_loc = self.locs.get(var_no) orelse return error.VariableNotAllocated;
        return var_loc;
    }

    //Establish an allocator based on variables and intmap
    pub fn add_var(self: * @This(), var_name: [] const u8, var_len: u64) !void{
        const var_no = (try self.vars.getOrPutValue(var_name, self.vars.count())).value_ptr.*;
        const var_loc = (try self.locs.getOrPutValue(var_no, self.used_count)).value_ptr.*;
        if(self.used_count == var_loc){
            self.used_count += var_len;
        }
    }

    //Is not memory safe, just writes the data on and on no bounds checking
    pub fn write_var(self: * @This(), stk: *vm.Stack, var_name: [] const u8, da_val: anytype) !void{
        if((stk.items.len - self.global_off) < self.used_count) return error.NotEnoughMemory;

        const var_no = self.vars.get(var_name) orelse return error.VariableNotFound;
        const var_loc = self.locs.get(var_no) orelse return error.VariableNotAllocated;

        //std.debug.print("{s} => {} {} ", .{var_name, var_no, var_loc});
        const ntype = @TypeOf(da_val);
        if(comptime is_numtype(ntype)){
            const val:f64 = if(comptime is_inttype(ntype)) @floatFromInt(da_val)
            else @floatCast(da_val);
            stk.items[stk.items.len-1-var_loc-self.global_off] = val;
            //std.debug.print("{d}\n", .{val});
            return;
        }
        if(std.meta.Elem(ntype) == f64){
            for(var_loc.., da_val)|loc,v|{
                stk.items[stk.items.len-1-loc-self.global_off] = v;
            }
            //std.debug.print("{any}\n", .{da_val});
            return;
        }
        @compileError("Unsupported array/slice type");
    }

    pub fn read_var(self: *@This(), stk: *const vm.Stack, var_name: [] const u8, inx: u64) !f64{
        if((stk.items.len - self.global_off) < self.used_count) return error.NotEnoughMemory;

        const var_no = self.vars.get(var_name) orelse return error.VariableNotFound;
        const var_loc = self.locs.get(var_no) orelse return error.VariableNotAllocated;
        return stk.items[stk.items.len-inx-1-var_loc-self.global_off];
    }

};

test "varholder add test"{
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();


    try vars.add_var("aloha", 1);
    try vars.add_var("hula", 1);
    try vars.add_var("aloha", 1);
    try vars.add_var("hula", 10);
    try vars.add_var("x", 2);
    try vars.add_var("y", 1);

    try std.testing.expectEqual(0, try vars.get_loc("aloha"));
    try std.testing.expectEqual(1, try vars.get_loc("hula"));
    try std.testing.expectEqual(2, try vars.get_loc("x"));
    try std.testing.expectEqual(4, try vars.get_loc("y"));
}

test "varholder write test"{
    const expecteq = std.testing.expectEqual;
    var stk = vm.Stack.init(std.testing.allocator);
    defer stk.deinit();
    try stk.resize(20);
    
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();

    try vars.add_var("x", 1);
    try vars.add_var("y", 1);
    try vars.add_var("z", 1);

    try vars.write_var(&stk, "z", 23);
    try vars.write_var(&stk, "x", -129);
    try vars.write_var(&stk, "y", 12);

    //std.debug.print("{any}\n", .{stk.items});
    
    try expecteq(23, stk.items[stk.items.len-3]);
    try expecteq(12, stk.items[stk.items.len-2]);
    try expecteq(-129, stk.items[stk.items.len-1]);
}

test "varholder write with array"{
    
    var stk = vm.Stack.init(std.testing.allocator);
    defer stk.deinit();
    try stk.resize(20);
    
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();

    try vars.add_var("a", 1);
    try vars.add_var("b", 4);
    try vars.add_var("c", 1);

    try vars.write_var(&stk, "a", 12);
    try vars.write_var(&stk, "c", 102);
    try vars.write_var(&stk, "b", &[_]f64{-1,-2,-3,-4});

    try std.testing.expectEqualSlices(f64,
                                      &[_]f64{102, -4, -3, -2, -1, 12},
                                      stk.items[(stk.items.len - 6)..]);
    
}

test "varholder write/read with global offset"{
    
    var stk = vm.Stack.init(std.testing.allocator);
    defer stk.deinit();
    try stk.resize(20);
    
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();

    try vars.add_var("a", 1);
    try vars.add_var("b", 4);
    try vars.add_var("c", 1);
    vars.global_off=1;

    try vars.write_var(&stk, "a", 12);
    try vars.write_var(&stk, "c", 102);
    try vars.write_var(&stk, "b", &[_]f64{-1,-2,-3,-4});

    try std.testing.expectEqualSlices(f64,
                                      &[_]f64{102, -4, -3, -2, -1, 12},
                                      stk.items[(stk.items.len - 7)..(stk.items.len-1)]);

    var read_data: [6] f64 = undefined;
    read_data[0] = try vars.read_var(&stk, "a", 0);
    read_data[1] = try vars.read_var(&stk, "c", 0);
    for(0..4)|i|{
        read_data[2+i] = try vars.read_var(&stk, "b", i);
    }

    try std.testing.expectEqualSlices(f64,
                                      &[_]f64{12, 102, -1, -2, -3, -4},
                                      &read_data);

}



//Generates (pushes) a code for vm based on an expression tree
//The vval value in expressions is the number as got from the variables list
//var_off is the offset from the base of stack where the variable actually resides
pub fn gen_code(ops: * std.ArrayList(vm.Operation), var_locs: * const VarHolder, var_off: usize, da_expr: Expr) !void{
    //var_off is the offset to be added to variables for access

    //get left argument recursively, add 1 to var_off
    //get right argument recursively, add 1 to var_off
    //apply operation
    if(da_expr.opr == .arrget){
        if(da_expr.left != .vval) return error.InvalidOperands;
    }
    const expr = if(da_expr.opr == .arrget) Expr{.opr = da_expr.opr,
                                                 .left = da_expr.right,
                                                 .right = da_expr.left}
    else da_expr;

    switch(expr.left){
        .cval => {try ops.append(.{.push = expr.left.cval});},
        .vval => {
            try ops.appendSlice(&[_]vm.Operation{
                .{.push = @floatFromInt(try var_locs.get_loc(expr.left.vval)+var_off+1)},
                .{.dup={}},
                .{.get={}}});
        },
        .expr => {try gen_code(ops, var_locs, var_off, expr.left.expr.*);}
    }
    if(expr.opr != .arrget){
        switch(expr.right){
            .cval => {try ops.append(.{.push = expr.right.cval});},
            .vval => {
                try ops.appendSlice(&[_]vm.Operation{
                    .{.push = @floatFromInt(try var_locs.get_loc(expr.right.vval)+var_off+2)},
                    .{.dup={}},
                    .{.get={}}});
            },
            .expr => {try gen_code(ops, var_locs, var_off+1, expr.right.expr.*);}
        }
    } else {
        try ops.appendSlice(&[_]vm.Operation{
            .{.push = @floatFromInt(try var_locs.get_loc(expr.right.vval)+var_off+1)},
            .{.add = {}},
            .{.dup={}},
            .{.get={}}});
    }
    
    
    try switch(expr.opr){.add => ops.append(.{.add={}}),
                         .sub => ops.append(.{.sub={}}),
                         .mul => ops.append(.{.mul={}}),
                         .div => ops.append(.{.div={}}),
                         .arrget => {}};
}



test "gen code simple manual push"{
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();

    var b = ExprBuilder.init(&vars.vars, std.testing.allocator);
    defer b.deinit();
    
    const expr = try b.make("x",.add,1);
    try vars.add_var("x",1);
    
    var arr = std.ArrayList(vm.Operation).init(std.testing.allocator);
    defer arr.deinit();

    try gen_code(&arr, &vars, 0, expr);
    try std.testing.expectEqualSlices(vm.Operation, arr.items, &[_]vm.Operation{
        .{.push=1}, .{.dup={}}, .{.get={}},
        .{.push=1},
        .{.add={}}
    });
    
    vars.deinit();
    vars = VarHolder.init(std.testing.allocator);
    
    arr.clearRetainingCapacity();

    const exp2 = try b.make(b.make("a", .add, "b"),
                            .mul,
                            b.make("b", .sub, "c"));
    try vars.add_var("a",1);
    try vars.add_var("b",1);
    try vars.add_var("c",1);
    try gen_code(&arr, &vars, 1, exp2);
    try std.testing.expectEqualSlices(vm.Operation, arr.items, &[_]vm.Operation{
        
        //sub expr 1
        .{.push=2}, .{.dup={}}, .{.get={}}, //a is at 0, off = 1
        .{.push=4}, .{.dup={}}, .{.get={}}, //b is at 1, off = 1 + 1 cuz right arg
        .{.add={}},
        //sub expr 2
        .{.push=4}, .{.dup={}}, .{.get={}}, //b is at 1, off = 1+1 cuz second expr left
        .{.push=6}, .{.dup={}}, .{.get={}}, //c is at 2, off = 1+1+1 cuz right arg
        .{.sub={}},
        .{.mul={}}
    });

    vars.deinit();
    vars = VarHolder.init(std.testing.allocator);
    
    arr.clearRetainingCapacity();

    const exp3 = try b.make("arr",
                            .arrget,
                            8);
    try vars.add_var("arr",10);
    try gen_code(&arr, &vars, 1, exp3);
    try std.testing.expectEqualSlices(vm.Operation, &[_]vm.Operation{
        // a9 a8 a7 a6 a5 a4 a3 a2 a1 a0 *
        .{.push=8},
        // a9 a8 a7 a6 a5 a4 a3 a2 a1 a0 * 8
        .{.push=2}, // 2=arr(1) + 1 (left argument)
        // a9 a8 a7 a6 a5 a4 a3 a2 a1 a0 * 8 2
        .{.add={}},
        // a9 a8 a7 a6 a5 a4 a3 a2 a1 a0 * 10
        .{.dup={}},
        // a9 a8 a7 a6 a5 a4 a3 a2 a1 a0 * 10 10
        // 11 10  9  8  7  6  5  4  3  2  1  0
        .{.get={}},
        }, arr.items);
}

test "run gen expr code"{
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();

    var bld = ExprBuilder.init(&vars.vars, std.testing.allocator);
    defer bld.deinit();
    
    var arr = std.ArrayList(vm.Operation).init(std.testing.allocator);
    defer arr.deinit();

    const expr = try bld.make(bld.make("a", .add, "b"),
                              .mul,
                              bld.make("b", .sub, "c"));
    try vars.add_var("a", 1);
    try vars.add_var("b", 1);
    try vars.add_var("c", 1);
    try gen_code(&arr, &vars, 0, expr);
    //A fxn registrar TODO:: remove it later to allow it to be optional
    var fxns = vm.FxnList.init(std.testing.allocator);
    defer fxns.deinit();

    var stk = vm.Stack.init(std.testing.allocator);
    defer stk.deinit();

    //Store c b a in stack and perform expression
    var prng = std.rand.DefaultPrng.init(std.crypto.random.uintAtMost(u64, (1<<64)-1));
    const rand = prng.random();

    const a = rand.float(f64) * 512 - 256;
    const b = rand.float(f64) * 512 - 256;
    const c = rand.float(f64) * 512 - 256;

    try stk.resize(3);
    try vars.write_var(&stk, "a", a);
    try vars.write_var(&stk, "b", b);
    try vars.write_var(&stk, "c", c);
    
    //Test for the result
    try vm.exec_ops(fxns, arr.items, &stk, .nodebug);

    try std.testing.expectEqualSlices(f64, &[_]f64{c,b,a,(a+b)*(b-c)},
                                      stk.items);
}


test "run gen expr code with array"{
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();

    var bld = ExprBuilder.init(&vars.vars, std.testing.allocator);
    defer bld.deinit();
    
    var ops = std.ArrayList(vm.Operation).init(std.testing.allocator);
    defer ops.deinit();

    //Run expression (arr[2]+(arr[i]-x)) + (arr[2*i]/y)
    const expr = try bld.make(bld.make(bld.make("arr",
                                                .arrget,
                                                2),
                                       .add,
                                       bld.make(bld.make("arr",
                                                         .arrget,
                                                         "i"),
                                                .sub,
                                                "x")),
                              .add,
                              bld.make(bld.make("arr",
                                                .arrget,
                                                bld.make(2,
                                                         .mul,
                                                         "i")),
                                       .div,
                                       "y"));
        

    
    var stk = vm.Stack.init(std.testing.allocator);
    defer stk.deinit();    
    //Decide upon an random order
    var prng = std.rand.DefaultPrng.init(std.crypto.random.uintAtMost(u64, (1<<64)-1));
    const rand = prng.random();

    const arr = try std.testing.allocator.alloc(f64, rand.uintAtMost(u64, 30) + 5);
    defer std.testing.allocator.free(arr);
    for(arr)|*v|{
        v.* = rand.float(f64) * 512 - 256;
    }
    const x = rand.float(f64) * 512 - 256;
    const y = rand.float(f64) * 512 - 256;
    const i:f64 = @floatFromInt(rand.uintAtMost(u64, arr.len-1)/2);


    try stk.resize(arr.len + 3);
    
    var var_names = [_] [] const u8{"arr", "x", "y", "i"};
    rand.shuffle([] const u8, &var_names);

    for(var_names)|v|{
        if(std.mem.eql(u8,"x",v)){ try vars.add_var(v, 1); }
        else if(std.mem.eql(u8,"y",v)) { try vars.add_var(v, 1); }
        else if(std.mem.eql(u8,"i",v)) { try vars.add_var(v, 1); }
        else if(std.mem.eql(u8,"arr",v)) { try vars.add_var(v, arr.len); }
    }

    try vars.write_var(&stk, "x", x);
    try vars.write_var(&stk, "y", y);
    try vars.write_var(&stk, "i", i);
    try vars.write_var(&stk, "arr", arr);
    
    try gen_code(&ops, &vars, 0, expr);

    const clone_stk = try stk.clone();
    defer clone_stk.deinit();
    
    //A fxn registrar TODO:: remove it later to allow it to be optional
    var fxns = vm.FxnList.init(std.testing.allocator);
    defer fxns.deinit();

    //Run expression (arr[2]+(arr[i]-x)) + (arr[2*i]/y)
    
    //Test for the result
    try vm.exec_ops(fxns, ops.items, &stk, .nodebug);


    try std.testing.expectEqual(clone_stk.items.len+1, stk.items.len);
    try std.testing.expectEqual((arr[2]+(arr[@intFromFloat(i)]-x)) +
                                    (arr[@intFromFloat(2*i)]/y),
                                stk.items[stk.items.len-1]);

    _=stk.pop();
    try std.testing.expectEqualSlices(f64, clone_stk.items, stk.items);
}


//TODO:: later make the expression creator return error when
//       using variable not registered


//General code generation context that generates full statement code
const GenCodeCxt = struct{

    //will need an init fxn after all
    //  
    
    fxn_name:[] const u8
    ops: * std.ArrayList(vm.Operation),
    var_locs: * const VarHolder,
    var_off: usize,
    
    //Generate assignment code
    pub fn assign_stmt(self: *const @This(), var_name: [] const u8, var_inx: Node, da_expr: Expr) !void{
        try gen_code(self.ops, self.var_locs, self.var_off, da_expr);
        
        var loc:f64 = @floatFromInt(try self.var_locs.get_loc(var_name)+self.var_off+1);
        if(var_inx == .cval){ loc += var_inx.cval; }
        try self.ops.append(.{.push=loc});
        if(var_inx == .vval){
            //+3 because first place for rhs evaluation, second for array base
            //third because we will be getting the value , so for dup
            const vloc:f64 = @floatFromInt(try self.var_locs.get_loc(var_inx.vval)
                                             + self.var_off + 3);
            try self.ops.appendSlice(&[_]vm.Operation{.{.push=vloc},.{.dup={}},
                                                   .{.get={}},.{.add={}}});
        }
        if(var_inx == .expr){
            //+2 because, first place is for the rhs evaluation
            //second place for the base address of array
            //so index expression starts from 2
            try gen_code(self.ops, self.var_locs, self.var_off+2, var_inx.expr.*);
            try self.ops.append(.{.add={}});
        }
        try self.ops.appendSlice(&[_]vm.Operation{.{.set={}}, .{.pop={}}});
        //try self.ops.append(.{.set={}});
    }

    test "assign stmt test"{
        var vars = VarHolder.init(std.testing.allocator);
        defer vars.deinit();

        var bld = ExprBuilder.init(&vars.vars, std.testing.allocator);
        defer bld.deinit();
        
        var ops = std.ArrayList(vm.Operation).init(std.testing.allocator);
        defer ops.deinit();

        //Test expressions, y = 2*y; y = expr1
        //arr[i] = x; arr[i] = expr2
        //arr[2*i+3]=arr[i]; arr[expr4] = expr3

        const expr1 = try bld.make(2, .mul, "y");
        const expr2 = try bld.make(0, .add, "x");
        const expr3 = try bld.make("arr", .arrget, "i");
        const expr4 = try bld.make(bld.make(2,.mul,"i"),
                                   .add,
                                   3);
        
        var stk = vm.Stack.init(std.testing.allocator);
        defer stk.deinit();    
        //Decide upon an random order
        var prng = std.rand.DefaultPrng.init(std.crypto.random.uintAtMost(u64, (1<<64)-1));
        const rand = prng.random();


        const arr = try std.testing.allocator.alloc(f64,4 + 0 * rand.uintAtMost(u64, 30) + 5);
        defer std.testing.allocator.free(arr);
        for(arr)|*v|{
            v.* = rand.float(f64) * 512 - 256;
        }
        for(arr,3..)|*v,i|{
            v.* = @floatFromInt(i);
        }
        
        const x = rand.float(f64) * 512 - 256;
        var y = rand.float(f64) * 512 - 256;
        const i:f64 = @floatFromInt(rand.uintAtMost(u64, arr.len-4)/2);

        y = -1;
        
        
        try stk.resize(arr.len + 3);
        
        var var_names = [_] [] const u8{"arr", "x", "y", "i"};
        rand.shuffle([] const u8, &var_names);

        for(var_names)|v|{
            if(std.mem.eql(u8,"x",v)){ try vars.add_var(v, 1); }
            else if(std.mem.eql(u8,"y",v)) { try vars.add_var(v, 1); }
            else if(std.mem.eql(u8,"i",v)) { try vars.add_var(v, 1); }
            else if(std.mem.eql(u8,"arr",v)) { try vars.add_var(v, arr.len); }
        }

        try vars.write_var(&stk, "x", x);
        try vars.write_var(&stk, "y", y);
        try vars.write_var(&stk, "i", i);
        try vars.write_var(&stk, "arr", arr);
        
        //A fxn registrar TODO:: remove it later to allow it to be optional
        var fxns = vm.FxnList.init(std.testing.allocator);
        defer fxns.deinit();

        //Test expressions, y = 2*y; y = expr1
        //arr[i] = x; arr[i] = expr2
        //arr[2*i+3]=arr[i]; arr[expr4] = expr3

        const cxt = @This(){ .ops = &ops, .var_locs = &vars, .var_off = 0};

        try cxt.assign_stmt("y", .{.cval=0}, expr1);
        try cxt.assign_stmt("arr", .{.vval=vars.vars.get("i").?}, expr2);
        try cxt.assign_stmt("arr", .{.expr=&expr4}, expr3);

        //Test for the result
        var clone_stk = try stk.clone();
        defer clone_stk.deinit();

        y = 2*y;
        arr[@intFromFloat(i)]=x;
        arr[@intFromFloat(2*i+3)]=arr[@intFromFloat(i)];
        
        try vars.write_var(&clone_stk, "x", x);
        try vars.write_var(&clone_stk, "y", y);
        try vars.write_var(&clone_stk, "i", i);
        try vars.write_var(&clone_stk, "arr", arr);

        try vm.exec_ops(fxns, ops.items, &stk, .nodebug);
        
        try std.testing.expectEqualSlices(f64, clone_stk.items, stk.items);
    }

    // TODO :: Now need to make a concept of local variables??
    // Currently all have been a 'global context'
    // or maybe just maybe, this works at a local level if needed ??
    // when evaluating expressions, the variables have to be global
    // when evaluating fxns, the variables are treated as is
    // so..., for every non if/while fxn groups, there has to be
    // a separate variable holder object

    //So this 'gen code cxt' should act as more like a fxn object objet
    
    
    
    // //Following two add the comparision and rop/n codes
    // fn leq_stmt(self: *const @This(), var_name: [] const u8, var_inx: Node, da_expr: Expr) !void{

    // }
    // //This wraps leq/geq stmt into a new function block and returns that after pushing
    // //call instruction
    // pub fn if_leq_stmt(self: *const @This(), left_val: Node, right_val: Node) !@This(){
        
    // }
};

test{
    _=GenCodeCxt;
}

//Generate comparision code
        
