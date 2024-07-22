const std = @import("std");
const vm = @import("engine.zig");

//Code generator fxns

//Context struct

//add variable fxn

//add array fxn

//Build an expression binary(or nary) tree structure incrementally fxn 

//add an expression fxn

//Generate conditional ron/rop from given expression trees fxn

//Fork into while loop fxn

//Fork into if block fxn

pub const Expr = struct{
    left: Node,
    right: Node,
    opr: enum{
        add, sub, mul, div
    },
};

const Node = union(enum){
    expr: *const Expr,
    cval: f64,
    vval: u64,
};

pub fn print_expr(expr: *const Expr, writer: anytype) !void{
    try writer.print("( {s} ", .{switch(expr.opr){
        .add => "+", .sub => "-", .mul => "*", .div => "/"
    }});
    try switch(expr.left){
        .cval => writer.print("{d}",.{expr.left.cval}),
        .vval => writer.print(":{}", .{expr.left.vval}),
        .expr => print_expr(expr.left.expr, writer),
    };
    try writer.print(" ", .{});
    try switch(expr.right){
        .cval => writer.print("{d}",.{expr.right.cval}),
        .vval => writer.print(":{}", .{expr.right.vval}),
        .expr => print_expr(expr.right.expr, writer),
    };
    try writer.print(" )", .{});
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
    try std.testing.expectEqualSlices(u8, "( + 1 2 )",
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
    try std.testing.expectEqualSlices(u8, arr.items,
                                      "( + ( * 3 -1 ) 2 )");
}


test "print two dir expr"{
    var arr = std.ArrayList(u8).init(std.testing.allocator);
    defer arr.deinit();

    const expr = Expr{
        .opr = .sub,
        .left = .{.expr = &.{.opr = .div,
                             .left = .{.cval=3.3},
                             .right = .{.vval=1}
                             }},
        .right = .{.expr = &.{.opr = .mul,
                             .left = .{.vval=3},
                             .right = .{.cval=-1}
                             }},
    };

    try print_expr(&expr, arr.writer().any());
    try std.testing.expectEqualSlices(u8, arr.items,
                                      "( - ( / 3.3 :1 ) ( * :3 -1 ) )");
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
                                          "( + 1.2 3 )");
    }
    {
        
        var arr = std.ArrayList(u8).init(std.testing.allocator);
        defer arr.deinit();

        var vars = Variables.init(std.testing.allocator);
        defer vars.deinit();
        const expr = try make_expr(arena.allocator(), &vars, 1.2, .add, @as(f64,3));
        
        try print_expr(&expr, arr.writer().any());
        try std.testing.expectEqualSlices(u8, arr.items,
                                          "( + 1.2 3 )");
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
                                      "( / :1 ( - :0 34 ) )");
    arr.clearRetainingCapacity();
    const expr3 = try make_expr(allocr, &vars, "y", .mul, "x");

    try print_expr(&expr3, arr.writer().any());
    try std.testing.expectEqualSlices(u8, arr.items,
                                      "( * :1 :0 )");
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
    try std.testing.expectEqualSlices(u8, arr.items,
                                      "( / ( + :1 ( * :0 4 ) ) ( - -23.1 ( / :1 3 ) ) )");
}

//Generates (pushes) a code for vm based on an expression tree
//The vval value in expressions is the number as got from the variables list
//var_off is the offset from the base of stack where the variable actually resides
pub fn gen_code(ops: * std.ArrayList(vm.Operation), var_off: usize, expr: *const Expr) !void{
    //var_off is the offset to be added to variables for access

    //get left argument recursively, add 1 to var_off
    //get right argument recursively, add 1 to var_off
    //apply operation
    switch(expr.left){
        .cval => {try ops.append(.{.push = expr.left.cval});},
        .vval => {
            try ops.appendSlice(&[_]vm.Operation{
                .{.push = @floatFromInt(expr.left.vval+var_off+1)},
                .{.dup={}},
                .{.get={}}});
        },
        .expr => {try gen_code(ops, var_off, expr.left.expr);}
    }
    switch(expr.right){
        .cval => {try ops.append(.{.push = expr.right.cval});},
        .vval => {
            try ops.appendSlice(&[_]vm.Operation{
                .{.push = @floatFromInt(expr.right.vval+var_off+2)},
                .{.dup={}},
                .{.get={}}});
        },
        .expr => {try gen_code(ops, var_off+1, expr.right.expr);}
    }
    try ops.append(switch(expr.opr){.add => .{.add={}},
                                    .sub => .{.sub={}},
                                    .mul => .{.mul={}},
                                    .div => .{.div={}}});
}

test "gen code simple"{
    var vars = Variables.init(std.testing.allocator);
    defer vars.deinit();

    var b = ExprBuilder.init(&vars, std.testing.allocator);
    defer b.deinit();
    
    const expr = try b.make("x",.add,1);

    var arr = std.ArrayList(vm.Operation).init(std.testing.allocator);
    defer arr.deinit();

    try gen_code(&arr, 0, &expr);
    try std.testing.expectEqualSlices(vm.Operation, arr.items, &[_]vm.Operation{
        .{.push=1}, .{.dup={}}, .{.get={}},
        .{.push=1},
        .{.add={}}
    });
    
    vars.clearRetainingCapacity();
    arr.clearRetainingCapacity();

    const exp2 = try b.make(b.make("a", .add, "b"),
                            .mul,
                            b.make("b", .sub, "c"));
    try gen_code(&arr, 1, &exp2);
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
}
        
