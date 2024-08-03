const std = @import("std");
const vm = @import("engine.zig");

//TODO :: need to make local vars work


//Model of generation of code:

//Each statement independent 'unit', st each statement cleans up every intermediate
// pushes to the stack
//Each declaration of variable only can make persistent pushes to stack
//For each declaration of variable, increase one value to the offset and go on
// Soo, considering only expressions, arrays and declarations, do a code generation
//
//
//

const Expr = @This();
//pub const Expr = struct{
left: Node,
right: Node,
opr: enum{
    //arrget refers to a read of array element, first operand should be variable
    add, sub, mul, div, arrget
},
//};

pub const Node = union(enum){
    expr: *const Expr,
    cval: f64,
    vval: i64,
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
pub const Variables = std.StringHashMap(i64);

//Fxn to get or put variable while handling special variables
fn count_special_var(name: [] const u8) u64{
    var n:u64 = 0;
    for(name)|ch|{
        if(ch == '^') { n += 1; }
        else break;
    }
    return n;
}

fn get_or_add_var(vars: * Variables, name: [] const u8) !i64{
    if(vars.get(name))|v|{ return v; }

    var n:i64 = @intCast(count_special_var(name));
    if(n > 0) return -n;

    n = @intCast(vars.count());
    try vars.put(name, n);
    return n;
}

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
        //return Node{.vval = (try vars.getOrPutValue(node_val, vars.count())).value_ptr.*};
        return Node{.vval = try get_or_add_var(vars, node_val)};
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

pub const Builder = struct{
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
    pub fn node(self: *Self, node_val: anytype) !Node{
        const tn = blk:{
            if(@typeInfo(@TypeOf(node_val)) == .ErrorUnion){
                break :blk (node_val catch |err| {return err;});
            }
            else{
                break :blk node_val;
            }
        };
        return make_node(self.arena.?.allocator(), self.vars.?, tn);
    }
};

test "gen expr by builder"{
    var vars = Variables.init(std.testing.allocator);
    defer vars.deinit();

    var b = Builder.init(&vars, std.testing.allocator);
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


//Some variables are 'special',
// if variable names begin with and consist only of carat signs ^
// the number of carats signifies the number of stack item from
// end of stack to use as value and the identity is in negative
//Map from 'Variables' to index in memory
pub const VarHolder = struct{
    vars: Variables,
    //assert that output of vars is +ve before using in locs
    //assert that output of locs is +ve after adding offsets and vars size
    //maybe not let outside interface access this at all ??
    locs: std.AutoHashMap(u64, i64),
    param_size: u64 = 0,
    vars_size: u64 = 0,
    global_off: i64 = 0, 
    pub fn init(allocr: std.mem.Allocator) @This(){
        return @This(){
            .vars = Variables.init(allocr),
            .locs = std.AutoHashMap(u64, i64).init(allocr),
        };
    }
    pub fn deinit(self: * @This()) void{
        self.vars.deinit();
        self.locs.deinit();
        self.param_size = 0;
        self.vars_size = 0;
        self.global_off = 0;
    }

    pub fn dump_contents(self: * const @This()) void{
        std.debug.print("Param size : {} Vars size : {} Global off : {}\n",
                        .{self.param_size, self.vars_size, self.global_off});
        std.debug.print("Variable => Id => location in hashmap => get_loc\n", .{});
        var iter = self.vars.keyIterator();
        while(iter.next())|v|{
            const id = self.vars.get(v.*).?;
            const loc = self.locs.get(@intCast(id)) orelse -99;
            const gloc = self.get_loc(id) catch 9999999;
            std.debug.print("{s} => {} => {} => {} \n", .{v.*, id, loc, gloc});
        }
    }

    pub fn get_loc(self: * const @This(), var_id: anytype) !u64{

        const var_no = if(comptime is_inttype(@TypeOf(var_id))) blk:{
            break :blk if (var_id >= 0) @as(u64,@intCast(var_id)) else
                return @as(u64,@intCast(-var_id-1));
        }
        else blk:{
            if(self.vars.get(var_id))|v|{ break :blk v;}
            const n = count_special_var(var_id);
            if(n > 0) return n-1;
            return error.VariableNotFound;
        };
        const var_loc = self.locs.get(@intCast(var_no)) orelse return error.VariableNotAllocated;
        var loc = var_loc + self.global_off;
        loc += @intCast(self.vars_size);
        return @as(u64, @intCast(loc));
    }


    //Establish an allocator based on variables and intmap
    pub fn add_local_var(self: * @This(), var_name: [] const u8, var_len: u64) !void{
        const var_no = (try self.vars.getOrPutValue(var_name, self.vars.count())).value_ptr.*;
        const new_loc = -@as(i64, @intCast(self.vars_size+var_len));
        const var_loc = (try self.locs.getOrPutValue(@intCast(var_no), @intCast(new_loc))).value_ptr.*;
        if(new_loc == var_loc){
            self.vars_size += var_len;
        }
    }


    pub fn add_param(self: *@This(), param_name: [] const u8, param_len: u64) !void{
        const var_no = (try self.vars.getOrPutValue(param_name, self.vars.count())).value_ptr.*;
        const var_loc = (try self.locs.getOrPutValue(@intCast(var_no), @intCast(self.param_size))).value_ptr.*;
        if(self.param_size == var_loc){
            self.param_size += param_len;
        }
    }
    
    test "test get param/variable location" {
        var vh = @This().init(std.testing.allocator);
        defer vh.deinit();
        const teq = std.testing.expectEqual;
        
        try vh.add_local_var("a", 2);
        try vh.add_param("x", 1);
        try vh.add_param("y", 2);
        try vh.add_local_var("z", 5);

        const psize = 3;
        const vsize = 7;

        try teq(psize, vh.param_size);
        try teq(vsize, vh.vars_size);

        try teq(vsize, try vh.get_loc("x"));
        try teq(vsize+1, try vh.get_loc("y"));
        try teq(0, try vh.get_loc("z"));
        try teq(5, try vh.get_loc("a"));

        vh.global_off = 3;

        try teq(vsize+3, try vh.get_loc("x"));
        try teq(vsize+1+3, try vh.get_loc("y"));
        try teq(0+3, try vh.get_loc("z"));
        try teq(5+3, try vh.get_loc("a"));
        
    }
    
    //Is not memory safe, just writes the data on and on no bounds checking
    //Before writing, need to push space just for param, ie, self.param_size but not for local variables
    pub fn write_param(self: *@This(), stk: *vm.Stack, param_name: [] const u8, da_val: anytype) !void{
        if((@as(i64,@intCast(stk.items.len)) - self.global_off) < self.param_size) return error.NotEnoughMemory;

        const var_no = self.vars.get(param_name) orelse return error.VariableNotFound;
        const var_loc = self.locs.get(@intCast(var_no)) orelse return error.VariableNotAllocated;

        //std.debug.print("{s} => {} {} ", .{var_name, var_no, var_loc});
        const ntype = @TypeOf(da_val);
        if(comptime is_numtype(ntype)){
            const val:f64 = if(comptime is_inttype(ntype)) @floatFromInt(da_val)
            else @floatCast(da_val);
            var inx:i64 = self.global_off - 1 - var_loc;
            inx += @intCast(stk.items.len);
            stk.items[@intCast(inx)] = val;
            //std.debug.print("{d}\n", .{val});
            return;
        }
        if(std.meta.Elem(ntype) == f64){
            const inx = var_loc + self.global_off;
            for(@intCast(inx).., da_val)|loc,v|{
                stk.items[stk.items.len-loc-1] = v;
            }
            //std.debug.print("{any}\n", .{da_val});
            return;
        }
        @compileError("Unsupported array/slice type");
    }

    pub fn read_param(self: *@This(), stk: *const vm.Stack, var_name: [] const u8, inx: u64) !f64{
        if((@as(i64,@intCast(stk.items.len)) - self.global_off) < self.param_size) return error.NotEnoughMemory;
        const var_no = self.vars.get(var_name) orelse return error.VariableNotFound;
        const var_loc = self.locs.get(@intCast(var_no)) orelse return error.VariableNotAllocated;
        var v:i64 = @intCast(stk.items.len-1-inx);
        v -= var_loc + self.global_off;
        return stk.items[@intCast(v)];
    }

};

test "varholder add test"{
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();

    try vars.add_param("aloha", 1);
    try vars.add_param("hula", 1);
    try vars.add_param("aloha", 1);
    try vars.add_param("hula", 10);
    try vars.add_param("x", 2);
    try vars.add_param("y", 1);

    try std.testing.expectEqual(0, try vars.get_loc("aloha"));
    try std.testing.expectEqual(1, try vars.get_loc("hula"));
    try std.testing.expectEqual(2, try vars.get_loc("x"));
    try std.testing.expectEqual(4, try vars.get_loc("y"));

    try std.testing.expectEqual(0, try vars.get_loc("^"));
    try std.testing.expectEqual(2, try vars.get_loc("^^^"));
}

test "varholder write test"{
    const expecteq = std.testing.expectEqual;
    var stk = vm.Stack.init(std.testing.allocator);
    defer stk.deinit();
    try stk.resize(20);
    
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();

    try vars.add_param("x", 1);
    try vars.add_param("y", 1);
    try vars.add_param("z", 1);

    try vars.write_param(&stk, "z", 23);
    try vars.write_param(&stk, "x", -129);
    try vars.write_param(&stk, "y", 12);

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

    try vars.add_param("a", 1);
    try vars.add_param("b", 4);
    try vars.add_param("c", 1);

    try vars.write_param(&stk, "a", 12);
    try vars.write_param(&stk, "c", 102);
    try vars.write_param(&stk, "b", &[_]f64{-1,-2,-3,-4});

    try std.testing.expectEqualSlices(f64,
                                      &[_]f64{102, -4, -3, -2, -1, 12},
                                      stk.items[(stk.items.len - 6)..]);
    
}


//Generates (pushes) a code for vm based on an expression tree
//The vval value in expressions is the number as got from the variables list
//var_off is the offset from the base of stack where the variable actually resides
//  but after the offset of the local vars' size
pub fn gen_code(ops: * std.ArrayList(vm.Operation), vars: * const VarHolder, var_off: i64, da_expr: Expr) !void{
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
                .{.push = @floatFromInt(@as(i64, @intCast(try vars.get_loc(expr.left.vval))) + var_off + 1)},
                .{.dup=1},
                .{.get={}}});
        },
        .expr => {try gen_code(ops, vars, var_off, expr.left.expr.*);}
    }
    if(expr.opr != .arrget){
        switch(expr.right){
            .cval => {try ops.append(.{.push = expr.right.cval});},
            .vval => {
                try ops.appendSlice(&[_]vm.Operation{
                    .{.push = @floatFromInt(@as(i64, @intCast(try vars.get_loc(expr.right.vval))) + var_off + 2)},
                    .{.dup=1},
                    .{.get={}}});
            },
            .expr => {try gen_code(ops, vars, var_off+1, expr.right.expr.*);}
        }
    } else {
        try ops.appendSlice(&[_]vm.Operation{
            .{.push = @floatFromInt(var_off + 1 + @as(i64, @intCast(try vars.get_loc(expr.right.vval))))},
            .{.add = {}},
            .{.dup=1},
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

    var b = Builder.init(&vars.vars, std.testing.allocator);
    defer b.deinit();
    
    const expr = try b.make("x",.add,1);
    try vars.add_param("x",1);
    
    var arr = std.ArrayList(vm.Operation).init(std.testing.allocator);
    defer arr.deinit();

    try gen_code(&arr, &vars, 0, expr);
    try std.testing.expectEqualSlices(vm.Operation, arr.items, &[_]vm.Operation{
        .{.push=1}, .{.dup=1}, .{.get={}},
        .{.push=1},
        .{.add={}}
    });
    
    vars.deinit();
    vars = VarHolder.init(std.testing.allocator);
    
    arr.clearRetainingCapacity();

    const exp2 = try b.make(b.make("a", .add, "b"),
                            .mul,
                            b.make("b", .sub, "c"));
    try vars.add_param("a",1);
    try vars.add_param("b",1);
    try vars.add_param("c",1);
    try gen_code(&arr, &vars, 1, exp2);
    try std.testing.expectEqualSlices(vm.Operation, arr.items, &[_]vm.Operation{
        
        //sub expr 1
        .{.push=2}, .{.dup=1}, .{.get={}}, //a is at 0, off = 1
        .{.push=4}, .{.dup=1}, .{.get={}}, //b is at 1, off = 1 + 1 cuz right arg
        .{.add={}},
        //sub expr 2
        .{.push=4}, .{.dup=1}, .{.get={}}, //b is at 1, off = 1+1 cuz second expr left
        .{.push=6}, .{.dup=1}, .{.get={}}, //c is at 2, off = 1+1+1 cuz right arg
        .{.sub={}},
        .{.mul={}}
    });

    vars.deinit();
    vars = VarHolder.init(std.testing.allocator);
    
    arr.clearRetainingCapacity();

    const exp3 = try b.make("arr",
                            .arrget,
                            8);
    try vars.add_param("arr",10);
    try gen_code(&arr, &vars, 1, exp3);
    try std.testing.expectEqualSlices(vm.Operation, &[_]vm.Operation{
        // a9 a8 a7 a6 a5 a4 a3 a2 a1 a0 *
        .{.push=8},
        // a9 a8 a7 a6 a5 a4 a3 a2 a1 a0 * 8
        .{.push=2}, // 2=arr(1) + 1 (left argument)
        // a9 a8 a7 a6 a5 a4 a3 a2 a1 a0 * 8 2
        .{.add={}},
        // a9 a8 a7 a6 a5 a4 a3 a2 a1 a0 * 10
        .{.dup=1},
        // a9 a8 a7 a6 a5 a4 a3 a2 a1 a0 * 10 10
        // 11 10  9  8  7  6  5  4  3  2  1  0
        .{.get={}},
        }, arr.items);
}

test "run gen expr code"{
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();

    var bld = Builder.init(&vars.vars, std.testing.allocator);
    defer bld.deinit();
    
    var arr = std.ArrayList(vm.Operation).init(std.testing.allocator);
    defer arr.deinit();

    const expr = try bld.make(bld.make("a", .add, "b"),
                              .mul,
                              bld.make("b", .sub, "c"));
    try vars.add_param("a", 1);
    try vars.add_param("b", 1);
    try vars.add_param("c", 1);
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
    try vars.write_param(&stk, "a", a);
    try vars.write_param(&stk, "b", b);
    try vars.write_param(&stk, "c", c);
    
    //Test for the result
    try vm.exec_ops(fxns, arr.items, &stk, .nodebug);

    try std.testing.expectEqualSlices(f64, &[_]f64{c,b,a,(a+b)*(b-c)},
                                      stk.items);
}


test "run gen expr code with array"{
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();

    var bld = Builder.init(&vars.vars, std.testing.allocator);
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
        if(std.mem.eql(u8,"x",v)){ try vars.add_param(v, 1); }
        else if(std.mem.eql(u8,"y",v)) { try vars.add_param(v, 1); }
        else if(std.mem.eql(u8,"i",v)) { try vars.add_param(v, 1); }
        else if(std.mem.eql(u8,"arr",v)) { try vars.add_param(v, arr.len); }
    }

    try vars.write_param(&stk, "x", x);
    try vars.write_param(&stk, "y", y);
    try vars.write_param(&stk, "i", i);
    try vars.write_param(&stk, "arr", arr);
    
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

test "run gen code with param and vars"{
    var vars = VarHolder.init(std.testing.allocator);
    defer vars.deinit();

    var bld = Builder.init(&vars.vars, std.testing.allocator);
    defer bld.deinit();
    
    var arr = std.ArrayList(vm.Operation).init(std.testing.allocator);
    defer arr.deinit();

    const expr = try bld.make(bld.make("a", .add, "b"),
                              .mul,
                              bld.make("b", .sub, "c"));
    try vars.add_param("a", 1);
    try vars.add_param("b", 1);
    try vars.add_local_var("c", 1);
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

    try stk.resize(2);
    try vars.write_param(&stk, "a", a);
    try vars.write_param(&stk, "b", b);
    try stk.append(c);
    //try vars.write_param(&stk, "c", c);
    
    //Test for the result
    //std.debug.print(" \na={d} b={d} c={d}\n", .{a,b,c});
    //vars.dump_contents();
    try vm.exec_ops(fxns, arr.items, &stk, .nodebug);
    
    try std.testing.expectEqualSlices(f64, &[_]f64{b,a,c, (a+b)*(b-c)},
                                      stk.items);
}

//TODO:: later make the expression creator return error when
//       using variable not registered
