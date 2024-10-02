const Expr = @import("expressions.zig");
const std = @import("std");
const vm = @import("engine.zig");

//General code generation context that generates full statement code
//const GenCodeCxt = struct{

//will need an init fxn after all
//  allocator for the names for sub functions
//  list of hashmaps of fxns ?? or just a string/operation arraylist pair??
//  a single varholder
//  an var_off tracker
//  an initialization function for local variables??
//  or translate it into a bunch of push instructions
//  use the varholder directly, or wrap it's fxns in another fxn ??
//
//Will need a begin/end pair for for and while stuff
//So will need a stack, each of pair of name and arraylist of operation
//escaping a scope means we register that into fxn list
//So we prob need an arena allocator for freeing all of such stuff at once
const NameFxn = struct{ name: [*:0] const u8, code: std.ArrayList(vm.Operation)};
allocr: std.heap.ArenaAllocator,

// main_name:[] const u8,
// main_fxn: std.ArrayList(vm.Operation),
fxn_stk: std.ArrayList(NameFxn),
//sub_fxns: vm.FxnList,
//active_name: [] const u8,
vars: Expr.VarHolder,
//var_off: usize,

pub fn init(allocr: std.mem.Allocator) @This(){
    return @This(){
        .allocr = std.heap.ArenaAllocator.init(allocr),
        .fxn_stk = std.ArrayList(NameFxn).init(allocr),
        .vars = Expr.VarHolder.init(allocr),
        //.var_off = 0,
    };
}
pub fn deinit(self: *@This()) void{
    self.vars.deinit();
    self.fxn_stk.deinit();
    self.allocr.deinit();
}

//Begin scope, end scope, later used to emulate if / while blocks
//if name.len == 0, appends a random string to the parent scope as per need
pub fn begin_scope(self: *@This(), da_name: [] const u8) !void{
    var name:[:0]u8 = undefined;
    if(da_name.len == 0){
        name = try self.allocr.allocator().allocSentinel(u8, 31, 0);
        var prng = std.rand.DefaultPrng.init(std.crypto.random.uintAtMost(u64, (1<<64)-1));
        const rand = prng.random();
        name[0] = rand.uintAtMost(u8, 'z'-'a') + 'a'; 
        for(name[1..])|*c|{
            var ch = rand.uintAtMost(u8, 127);
            //while(!std.ascii.isPrint(ch) or std.ascii.isWhitespace(ch)){
            while(!std.ascii.isAlphanumeric(ch)){
                ch = rand.uintAtMost(u8, (1<<7)-1);
            }
            c.* = ch;
        }
        //return error.TODO_NotImplementedThisYet;
    }
    else{
        //We allocate this stuff from arena, so don't free manually ever, because will be used
        //Allocate name also as we need to ensure it is null terminated
        name = try self.allocr.allocator().allocSentinel(u8, da_name.len, 0);
        @memcpy(name, da_name);
    }

    try self.fxn_stk.append(.{.name = name.ptr,
                              .code = std.ArrayList(vm.Operation).init(self.allocr.allocator())});
}
pub fn end_scope(self: *@This(), fxn_list: *vm.FxnList) ![*:0] const u8{

    const v = self.fxn_stk.popOrNull() orelse {return error.OutOfScopes;};
    //TODO:: If the scope is already registered, issue another error
    if(fxn_list.get(std.mem.span(v.name)))|_|{ return error.FunctionAlreadyRegistered; }
    fxn_list.put(std.mem.span(v.name), v.code.items) catch {return error.AllocError;};
    return v.name;
}

//allocate vars by using push instructions, useful when a fxn starts up
//but you need to have something representing the parameters too
//They have to be registered as 'variables', but not 'pushed'
//Also is there sense in making 'parameters' or 'variables' at the local scope level,
// and if there is , is there any sensible way of implementing withoug making variable holder
// for each scope ??
//Perhaps better idea would be to add another 1/2 field to this struct,
//that stores the list of parameter variables and non parameter variables separately
//Then merges somehow later ??
//Anyway, seems like there has to be special system for handling parameters and return values

//Generate assignment code
pub fn assign_stmt(self: *const @This(), var_name: [] const u8, var_inx: Expr.Node, da_expr: Expr) !void{
    //Doesnot validate if fxn_stk has items, just assumes it has
    const curr_ops = &self.fxn_stk.items[self.fxn_stk.items.len-1].code;
    try Expr.gen_code(curr_ops, &self.vars, 0, da_expr);
    
    var loc:f64 = @floatFromInt(try self.vars.get_loc(var_name) + 1);
    //var loc:f64 = @floatFromInt(try self.vars.get_loc(var_name) + self.var_off+1);
    if(var_inx == .cval){ loc += var_inx.cval; }
    try curr_ops.append(.{.push=loc});
    if(var_inx == .vval){
        //+3 because first place for rhs evaluation, second for array base
        //third because we will be getting the value , so for dup
        const vloc:f64 = @floatFromInt(try self.vars.get_loc(var_inx.vval)
                                           + 3);
        try curr_ops.appendSlice(&[_]vm.Operation{.{.push=vloc},.{.dup=1},
                                                  .{.get={}},.{.add={}}});
    }
    if(var_inx == .expr){
        //+2 because, first place is for the rhs evaluation
        //second place for the base address of array
        //so index expression starts from 2
        try Expr.gen_code(curr_ops, &self.vars, 2, var_inx.expr.*);
        try curr_ops.append(.{.add={}});
    }
    try curr_ops.appendSlice(&[_]vm.Operation{.{.set={}}, .{.pop=1}});
}

test "assign stmt test"{
    for(0..4)|_|{
        // var vars = Expr.VarHolder.init(std.testing.allocator);
        // defer vars.deinit();
        // var ops = std.ArrayList(vm.Operation).init(std.testing.allocator);
        // defer ops.deinit();

        var fxn = @This().init(std.testing.allocator);
        defer fxn.deinit();

        // * Build the expressions
        var bld = Expr.Builder.init(&fxn.vars.vars, std.testing.allocator);
        defer bld.deinit();
        
        // * Test expressions, y = 2*y; y = expr1
        //arr[i] = x; arr[i] = expr2
        //arr[2*i+3]=arr[i]; arr[expr4] = expr3

        const expr1 = try bld.make(2, .mul, "y");
        const expr2 = try bld.make(0, .add, "x");
        const expr3 = try bld.make("arr", .arrget, "i");
        const expr4 = try bld.make(bld.make(2,.mul,"i"),
                                   .add,
                                   3);

        // * The memory of machine
        var stk = vm.Stack.init(std.testing.allocator);
        defer stk.deinit();

        // * Building the variables/arguments for the function 
        //Decide upon an random order
        var prng = std.rand.DefaultPrng.init(std.crypto.random.uintAtMost(u64, (1<<64)-1));
        const rand = prng.random();
        const arr = try std.testing.allocator.alloc(f64,4 + 0 * rand.uintAtMost(u64, 30) + 5);
        defer std.testing.allocator.free(arr);
        for(arr)|*v|{
            v.* = rand.float(f64) * 512 - 256;
        }
        // for(arr,3..)|*v,i|{
        //     v.* = @floatFromInt(i);
        // }
        
        const x = rand.float(f64) * 512 - 256;
        var y = rand.float(f64) * 512 - 256;
        const i:f64 = @floatFromInt(rand.uintAtMost(u64, arr.len-4)/2);
        //y = -1;

        //
        try stk.resize(arr.len + 3);
        
        var var_names = [_] [] const u8{"arr", "x", "y", "i"};
        rand.shuffle([] const u8, &var_names);

        // * Adding and writing up the values of variables in an order
        for(var_names)|v|{
            if(std.mem.eql(u8,"x",v)){ try fxn.vars.add_param(v, 1); }
            else if(std.mem.eql(u8,"y",v)) { try fxn.vars.add_param(v, 1); }
            else if(std.mem.eql(u8,"i",v)) { try fxn.vars.add_param(v, 1); }
            else if(std.mem.eql(u8,"arr",v)) { try fxn.vars.add_param(v, arr.len); }
        }

        try fxn.vars.write_param(&stk, "x", x);
        try fxn.vars.write_param(&stk, "y", y);
        try fxn.vars.write_param(&stk, "i", i);
        try fxn.vars.write_param(&stk, "arr", arr);

        // * Creating a clone of the stack and writing the expected results in it to compare
        //Test for the result
        var clone_stk = try stk.clone();
        defer clone_stk.deinit();

        y = 2*y;
        arr[@intFromFloat(i)]=x;
        arr[@intFromFloat(2*i+3)]=arr[@intFromFloat(i)];
        
        try fxn.vars.write_param(&clone_stk, "x", x);
        try fxn.vars.write_param(&clone_stk, "y", y);
        try fxn.vars.write_param(&clone_stk, "i", i);
        try fxn.vars.write_param(&clone_stk, "arr", arr);
        

        // * Start recording the statements in the function
        try fxn.begin_scope("da_fxn");
        
        //Test expressions, y = 2*y; y = expr1
        //arr[i] = x; arr[i] = expr2
        //arr[2*i+3]=arr[i]; arr[expr4] = expr3

        try fxn.assign_stmt("y", .{.cval=0}, expr1);
        try fxn.assign_stmt("arr", .{.vval=fxn.vars.vars.get("i").?}, expr2);
        try fxn.assign_stmt("arr", .{.expr=&expr4}, expr3);

        // * Mechanism for running the machine
        var fxns = vm.FxnList.init(std.testing.allocator);
        defer fxns.deinit();

        
        const ops = [_]vm.Operation{.{.call = try fxn.end_scope(&fxns)}};
        
        try vm.exec_ops(fxns, &ops, &stk, .nodebug);
        
        try std.testing.expectEqualSlices(f64, clone_stk.items, stk.items);
    }
}

//for return if x > y ie, if x <= y block
pub fn begin_if_leq(self: *@This(), lnode: Expr.Node, rnode: Expr.Node) !void{
    try self.begin_scope("");
    //Eval lnode, rnode, sub, rop
    const curr_ops = &self.fxn_stk.items[self.fxn_stk.items.len-1].code;

    switch(lnode){
        .cval => { try curr_ops.append(.{.push=lnode.cval}); },
        .vval => {
            //+1 because we will be getting the value , so for dup
            const vloc:f64 = @floatFromInt(try self.vars.get_loc(lnode.vval)
                                               + 1);
            try curr_ops.appendSlice(&[_]vm.Operation{.{.push=vloc},.{.dup=1},
                                                      .{.get={}}});
        },
        .expr => {
            try Expr.gen_code(curr_ops, &self.vars, 0, lnode.expr.*);
        },
    }
    //All have extra +1 for being the rhs expression on offsets
    switch(rnode){
        .cval => { try curr_ops.append(.{.push=rnode.cval}); },
        .vval => {
            //+1 because we will be getting the value , so for dup
            const vloc:f64 = @floatFromInt(try self.vars.get_loc(rnode.vval)
                                               + 2);
                                               //+ self.var_off + 2);
                                               
            try curr_ops.appendSlice(&[_]vm.Operation{.{.push=vloc},.{.dup=1},
                                                      .{.get={}}});
        },
        .expr => {
            try Expr.gen_code(curr_ops, &self.vars, 1, rnode.expr.*);
        },
    }
    try curr_ops.append(.{.sub={}});
    try curr_ops.append(.{.rop={}});
    try curr_ops.append(.{.pop=1});
}


pub fn end_if_leq(self: *@This(), fxn_list: *vm.FxnList) ![*:0] const u8{
    //try popping
    //call by the popped name
    const n = try self.end_scope(fxn_list);
    const curr_ops = &self.fxn_stk.items[self.fxn_stk.items.len-1].code;
    try curr_ops.append(.{.call=n});
    return n;
}

test "if statement testing"{
    for(0..4)|_|{
        var fxn = @This().init(std.testing.allocator);
        defer fxn.deinit();

        var stk = vm.Stack.init(std.testing.allocator);
        defer stk.deinit();

        var prng = std.rand.DefaultPrng.init(std.crypto.random.uintAtMost(u64, (1<<64)-1));
        const rand = prng.random();

        const w = rand.float(f64) * 512 - 256;
        const x = rand.float(f64) * 512 - 256;
        var y:f64 = 0;
        var z:f64 = 0;

        try stk.resize(4);
        
        try fxn.vars.add_param("w", 1);
        try fxn.vars.add_param("x", 1);
        try fxn.vars.add_param("y", 1);
        try fxn.vars.add_param("z", 1);

        try fxn.vars.write_param(&stk, "w", w);
        try fxn.vars.write_param(&stk, "x", x);
        try fxn.vars.write_param(&stk, "y", y);
        try fxn.vars.write_param(&stk, "z", z);
        
        //Run if w < x then y = y+2; if x < w then z = z-3;
        //Need 2 expressions

        var bld = Expr.Builder.init(&fxn.vars.vars, std.testing.allocator);
        defer bld.deinit();
        const expr1 = try bld.make("y", .add, 2);
        const expr2 = try bld.make("z", .sub, 3);

        var clone_stk = try stk.clone();
        defer clone_stk.deinit();

        if(w<=x){ y=y+2; }
        if(x<=w){ z=z-3; }
        try fxn.vars.write_param(&clone_stk, "y", y);
        try fxn.vars.write_param(&clone_stk, "z", z);
        
        var fxns = vm.FxnList.init(std.testing.allocator);
        defer fxns.deinit();

        try fxn.begin_scope("da_fxn");
        try fxn.begin_if_leq(try bld.node("w"),
                             try bld.node("x"));
        try fxn.assign_stmt("y", .{.cval=0}, expr1);
        _=try fxn.end_if_leq(&fxns);

        try fxn.begin_if_leq(try bld.node("x"),
                             try bld.node("w"));
        try fxn.assign_stmt("z", .{.cval=0}, expr2);
        _=try fxn.end_if_leq(&fxns);

        const ops = [_]vm.Operation{.{.call = try fxn.end_scope(&fxns)}};
        try vm.exec_ops(fxns, &ops, &stk, .nodebug);
        
        try std.testing.expectEqualSlices(f64, clone_stk.items, stk.items);
    }
}        

//for return if x > y ie, while x <= y block
pub fn begin_while_leq(self: *@This(), lnode: Expr.Node, rnode: Expr.Node) !void{
    try self.begin_scope("");
    //Eval lnode, rnode, sub, rop
    const curr_ops = &self.fxn_stk.items[self.fxn_stk.items.len-1].code;

    switch(lnode){
        .cval => { try curr_ops.append(.{.push=lnode.cval}); },
        .vval => {
            //+1 because we will be getting the value , so for dup
            const vloc:f64 = @floatFromInt(try self.vars.get_loc(lnode.vval)
                                               + 1);
            try curr_ops.appendSlice(&[_]vm.Operation{.{.push=vloc},.{.dup=1},
                                                      .{.get={}}});
        },
        .expr => {
            try Expr.gen_code(curr_ops, &self.vars, 0, lnode.expr.*);
        },
    }
    //All have extra +1 for being the rhs expression on offsets
    switch(lnode){
        .cval => { try curr_ops.append(.{.push=rnode.cval}); },
        .vval => {
            //+1 because we will be getting the value , so for dup
            const vloc:f64 = @floatFromInt(try self.vars.get_loc(rnode.vval)
                                               //+ self.var_off + 2);
                                               + 2);
            try curr_ops.appendSlice(&[_]vm.Operation{.{.push=vloc},.{.dup=1},
                                                      .{.get={}}});
        },
        .expr => {
            try Expr.gen_code(curr_ops, &self.vars, 1, rnode.expr.*);
        },
    }
    try curr_ops.append(.{.sub={}});
    try curr_ops.append(.{.rop={}});
    try curr_ops.append(.{.pop=1});
}


pub fn end_while_leq(self: *@This(), fxn_list: *vm.FxnList) ![*:0] const u8{
    //try popping
    //call by the popped name
    const while_ops = &self.fxn_stk.items[self.fxn_stk.items.len-1];
    try while_ops.code.append(.{.call=while_ops.name});
    const n = try self.end_scope(fxn_list);
    const parent_ops = &self.fxn_stk.items[self.fxn_stk.items.len-1].code;

    try parent_ops.append(.{.call=n});
    return n;
}

test "while stmt testing"{
    for(0..4)|_|{
        var fxn = @This().init(std.testing.allocator);
        defer fxn.deinit();

        var stk = vm.Stack.init(std.testing.allocator);
        defer stk.deinit();

        var prng = std.rand.DefaultPrng.init(std.crypto.random.uintAtMost(u64, (1<<64)-1));
        const rand = prng.random();

        //const w = rand.float(f64) * 512 - 256;
        const w:f64 = 0;
        var x = rand.float(f64) * 512;
        x = 10;
        var i:f64 = 0;

        try stk.resize(3);
        
        try fxn.vars.add_param("w", 1);
        try fxn.vars.add_param("x", 1);
        try fxn.vars.add_param("i", 1);
        
        try fxn.vars.write_param(&stk, "w", w);
        try fxn.vars.write_param(&stk, "x", x);
        try fxn.vars.write_param(&stk, "i", i);
        
        //Run while(w <= x), x = x - 2 and i = i + 1

        var bld = Expr.Builder.init(&fxn.vars.vars, std.testing.allocator);
        defer bld.deinit();
        const expr1 = try bld.make("x", .sub, 2);
        const expr2 = try bld.make("i", .add, 1);

        var clone_stk = try stk.clone();
        defer clone_stk.deinit();

        //std.debug.print("\nw = {d} x = {d} i = {d}\n", .{w,x,i});
        while(w <= x){
            x = x-2;
            i = i+1;
        }
        //std.debug.print("\nw = {d} x = {d} i = {d}\n", .{w,x,i});
        
        try fxn.vars.write_param(&clone_stk, "x", x);
        try fxn.vars.write_param(&clone_stk, "i", i);
        
        var fxns = vm.FxnList.init(std.testing.allocator);
        defer fxns.deinit();

        try fxn.begin_scope("da_fxn");
        try fxn.begin_while_leq(try bld.node("w"),
                                try bld.node("x"));
        try fxn.assign_stmt("x", .{.cval=0}, expr1);
        try fxn.assign_stmt("i", .{.cval=0}, expr2);
        _=try fxn.end_while_leq(&fxns);

        const ops = [_]vm.Operation{.{.call = try fxn.end_scope(&fxns)}};
        try vm.exec_ops(fxns, &ops, &stk, .nodebug);

        
        try std.testing.expectEqualSlices(f64, clone_stk.items, stk.items);
    }
}        

//function entry and exit things
// entry works only when the fxn_stk is empty
// and exit works only when the fxn_stk has single entry
//OR,
// make a 'special' scope mechahism where you do all this ??
// where you can set parameters, local variables and return values
// would work for 'scope returning values' kind of construct
//  But how to manage it with already existing VarHolder struct

//The fxn scope mechanism must handle writing (pushing) local variables
// and it should ensure that the parameters are the last variables to be set up there
//On closing of scope, it will set return variables to the bottom most stack values and pop everything else

const begin_fxn = begin_scope;
pub fn end_fxn(self: *@This(), fxn_list: *vm.FxnList, return_val: [] const u8, var_size: usize) ![*:0] const u8{
    // assert single top level scope
    if(self.fxn_stk.items.len != 1) return error.NotTopLevelScope;
    const ops = &self.fxn_stk.items[self.fxn_stk.items.len-1].code;
    const src_loc = try self.vars.get_loc(return_val);
    //pop all items upto src_loc
    try ops.append(.{.pop=@intCast(src_loc)});
    self.vars.global_off -= @intCast(src_loc);
    //Top most location is always at global_off + vars_size + param_size
    const dst_loc = @as(i64, @intCast(self.vars.param_size
                                          + self.vars.vars_size - var_size))
        + self.vars.global_off;
    //TODO :: Assert that this is not out of range

    //start setting items from top of stack to dst_loc
    for(0..@intCast(dst_loc))|_|{
        try ops.append(.{.push=@floatFromInt(var_size)});
        try ops.append(.{.set={}});
        try ops.append(.{.pop=1});
        try ops.append(.{.ret={}});
    }

    return try self.end_scope(fxn_list);
    
}

//Asserts that the fxn is just single scope
pub fn add_local_var(self: *@This(), name:[] const u8, var_size: usize) !void{
    // check if in top level scope
    if(self.fxn_stk.items.len != 1) return error.NotTopLevelScope;
    // call add local var
    try self.vars.add_local_var(name, var_size);
    // add instructions to push
    const ops = &self.fxn_stk.items[self.fxn_stk.items.len-1].code;
    //TODO:: This needs to be fixed, can fail easily if param count < local var count
    try ops.append(.{.dup=@intCast(var_size)});
    
}

//These two fxns are to be removed later in preference of a more 'platform independent'
// code generation interface
pub fn add_op(self: *@This(), op: vm.Operation) !void{
    const ops = &self.fxn_stk.items[self.fxn_stk.items.len-1].code;
    try ops.append(op);
}

pub fn add_expr(self: *@This(), expr: Expr) !void{
    const ops = &self.fxn_stk.items[self.fxn_stk.items.len-1].code;
    try Expr.gen_code(ops, &self.vars, 0, expr);
}

pub fn pop_temp_var(self: *@This(), n: u32) !void{
    self.vars.global_off -= n;
    try self.add_op(.{.pop=n});
}

test "fxn call testing"{
    var fxn = @This().init(std.testing.allocator);
    defer fxn.deinit();
    var b = Expr.Builder.init(&fxn.vars.vars, std.testing.allocator);
    defer b.deinit();
    var fxns = vm.FxnList.init(std.testing.allocator);
    defer fxns.deinit();

    try fxn.vars.add_param("n", 1);

    
    try fxn.begin_fxn("fibonacci");
    try fxn.add_local_var("o", 1);

    try fxn.assign_stmt("o", try b.node(0), try b.make(1, .add, 0));
    try fxn.begin_if_leq(try b.node(2), try b.node("n"));

    //Need to 'push' arguments to stack before calling function
    //TODO:: need to separate this later into it's own expression code gen
    //i.e, need to remove all direct code generation / opcode insertion
    try fxn.add_expr(try b.make("n", .sub, 1));
    try fxn.add_op(.{.call="fibonacci"});
    fxn.vars.global_off += 1; //counter that an argument is pushed to stack

    
    try fxn.add_expr(try b.make("n", .sub, 2));
    try fxn.add_op(.{.call="fibonacci"});
    fxn.vars.global_off += 1;


    try fxn.assign_stmt("o", try b.node(0), try b.make("^", .add, "^^"));
    try fxn.pop_temp_var(2);
    _=try fxn.end_if_leq(&fxns);
    
    //std.debug.print(" \n", .{});
    //fxn.vars.dump_contents();
    
    const ops = [_]vm.Operation{.{.call = try fxn.end_fxn(&fxns, "o", 1)}};
    var stk = vm.Stack.init(std.testing.allocator);
    defer stk.deinit();

    const fibo = struct{
        fn dafunc(n: f64) f64{
            if(n <= 1) return 1;
            return dafunc(n-1) + dafunc(n-2);
        }
    }.dafunc;

    for(0..7)|n|{
        //std.debug.print("\n\nFibo of {}\n", .{n});
        try stk.append(@floatFromInt(n));
        try vm.exec_ops(fxns, &ops, &stk, .nodebug);
        try std.testing.expectEqualSlices(f64, &[_]f64{fibo(@floatFromInt(n))},
                                          stk.items);
        _=stk.pop();
    }
}

    

//some mechanism for multiple functions



    // TODO :: Now need to make a concept of local variables??
    // Currently all have been a 'global context'
    // or maybe just maybe, this works at a local level if needed ??
    // when evaluating expressions, the variables have to be global
    // when evaluating fxns, the variables are treated as is
    // so..., for every non if/while fxn groups, there has to be
    // a separate variable holder object

    //So this 'gen code cxt' should act as more like a fxn object objet



    // //Following two add the comparision and rop/n codes
    // fn leq_stmt(self: *const @This(), var_name: [] const u8, var_inx: Expr.Node, da_expr: Expr) !void{

    // }
    // //This wraps leq/geq stmt into a new function block and returns that after pushing
    // //call instruction
    // pub fn if_leq_stmt(self: *const @This(), left_val: Expr.Node, right_val: Expr.Node) !@This(){

    // }

test{
    _=@import("expressions.zig");
}

//Generate comparision code

