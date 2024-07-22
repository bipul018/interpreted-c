const std = @import("std");


//Generate the stack based machine code
pub const Operation = union(enum){
    push:f64,
    pop:void,
    add:void, 
    sub:void, //push a, push b, sub => a - b
    mul:void,
    div:void,
    call:[*:0] const u8, //Runs function with whatever on stack,
    //might corrupt stack, make better later
    ret:void,//Unconditional return
    dup:void,//Duplicates the top of stack
    dup2:void,//Duplicates the top of stack twice
    xch:void,//Exchanges top two items of stack
    xch2:void,//Exchanges top and third top items of stack
    get:void,//Uses top argument to lerp get from that index and replace the top of stack
    set:void,//Uses top argument as index and distributes the top of stack to the cells
    //So get and set on argument 0 should be nop
    ron:void,//Pops value, if negative returns else keeps value intact
    rop:void,//Pops value, if positive returns else keeps value intact
    nop:void,
    brk:void,//Breaks the program at the point and prints stack if not nodebug
};
pub const FxnList = std.StringHashMap([] const Operation);
pub const Stack = std.ArrayList(f64);
pub fn exec_ops(fxns: FxnList, ops: [] const Operation, stk: *Stack,
            in_debug_level: enum{nodebug, fxncalls, alldebug}) !void{
    var debug_level = in_debug_level;
    if(debug_level == .fxncalls){
        std.debug.print("Stack : \n", .{});
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});
    }
    for(ops)|op|{
        //Debug mode, dump stack each time
        
        if((debug_level == .alldebug) or ((debug_level == .fxncalls) and (op == .call))){
            std.debug.print("{s}", .{@tagName(op)});
            switch(op){
                .push => std.debug.print(",{d} : ", .{op.push}),
                .call => std.debug.print(",{s}\n", .{op.call}),
                else => std.debug.print(" : ", .{})
            }
        }
        defer if(debug_level == .alldebug){
            switch(op){
                .call => {},
                else => {
                    for(stk.items)|it|{
                        std.debug.print("{d} ", .{it});
                    }
                    std.debug.print("\n", .{});
                }
            }
        };
        
        switch(op){
            .nop => {},
            .brk => {
                if(debug_level == .nodebug)
                    continue;
                if(debug_level != .alldebug){
                    std.debug.print("Debugbreak:",.{});
                    for(stk.items)|it|{
                        std.debug.print("{d} ", .{it});
                    }
                    std.debug.print("\n", .{});
                }
                
                while(blk:{
                    const c = try std.io.getStdIn().reader().readByte();
                    if(c == '\n') break :blk null;
                    break :blk c;
                })|ch|{
                    if(ch == 'v'){
                        debug_level = .alldebug;
                    }
                    if(ch == 'f'){
                        debug_level = .fxncalls;
                    }
                    if(ch == 'n'){
                        debug_level = .nodebug;
                    }
                }
            },
            .ret => {
                return;
            },
            .ron => {
                const x = stk.popOrNull() orelse return error.OutOfStack;
                if(x < 0)
                    return;
                try stk.append(x);
            },
            .rop => {
                const x = stk.popOrNull() orelse return error.OutOfStack;
                if(x > 0)
                    return;
                try stk.append(x);
            },
            .call => |fname|{
                const str = std.mem.span(fname);
                const fxn = fxns.get(str) orelse return error.InvalidFxnName;
                try exec_ops(fxns, fxn, stk, debug_level);
            },
            .dup =>{
                if(0 >= stk.items.len)
                    return error.OutOfStack;
                const x = stk.items[stk.items.len - 1];
                try stk.append(x);
            },
            .dup2 =>{
                if(0 >= stk.items.len)
                    return error.OutOfStack;
                const x = stk.items[stk.items.len - 1];
                try stk.append(x);
                try stk.append(x);
            },
            .xch =>{
                if(stk.items.len <= 1)
                    return error.OutOfStack;
                std.mem.swap(f64,
                             &stk.items[stk.items.len-1],
                             &stk.items[stk.items.len-2]);
            },
            .xch2 =>{
                if(stk.items.len <= 2)
                    return error.OutOfStack;
                std.mem.swap(f64,
                             &stk.items[stk.items.len-1],
                             &stk.items[stk.items.len-3]);
            },
            .push => |num|{
                try stk.append(num);
            },
            .pop => {
                _=stk.popOrNull() orelse return error.OutOfStack;
            },
            .add => {
                const b = stk.popOrNull() orelse return error.OutOfStack;
                const a = stk.popOrNull() orelse return error.OutOfStack;
                try stk.append(a + b);
            },
            .sub => {
                const b = stk.popOrNull() orelse return error.OutOfStack;
                const a = stk.popOrNull() orelse return error.OutOfStack;
                try stk.append(a - b);
            },
            .mul => {
                const b = stk.popOrNull() orelse return error.OutOfStack;
                const a = stk.popOrNull() orelse return error.OutOfStack;
                try stk.append(a * b);
            },
            .div => {
                const b = stk.popOrNull() orelse return error.OutOfStack;
                const a = stk.popOrNull() orelse return error.OutOfStack;
                try stk.append(a / b);
            },
            .get => {
                const inx = stk.popOrNull() orelse return error.OutOfStack;
                if(stk.items.len <= 0)
                    return error.OutOfStack;
                const epsilon = 0.0001;
                //Check boundaries
                if((inx < -epsilon) or ((inx - epsilon) >= @as(f64,@floatFromInt(stk.items.len-1))))
                    return error.OutOfStack;

                const low:usize = @intFromFloat(@floor(inx));
                const high:usize = low + 1;

                //Fraction that says how much of high is taken
                const fhigh = inx - @as(f64, @floatFromInt(low));
                //... low is taken
                const flow = 1 - fhigh;

                //Original values of low and high
                const lowv = stk.items[stk.items.len-1-low];
                const highv =
                    if(high == stk.items.len) 0
                else stk.items[stk.items.len-1-high];

                //Mixed value from low and high
                const ntop = lowv * flow + highv * fhigh;
                
                //Set values
                stk.items[stk.items.len-1] = ntop;
            },
            .set => {
                const inx = stk.popOrNull() orelse return error.OutOfStack;
                if(stk.items.len <= 0)
                    return error.OutOfStack;
                const epsilon = 0.0001;
                //Check boundaries
                if((inx < -epsilon) or ((inx - epsilon) >= @as(f64,@floatFromInt(stk.items.len-1))))
                    return error.OutOfStack;

                const low:usize = @intFromFloat(@floor(inx));
                const high:usize = low + 1;

                //Fraction that says how much of high is taken
                const fhigh = inx - @as(f64, @floatFromInt(low));
                //... low is taken
                const flow = 1 - fhigh;

                //Original values of low and high
                const lowv = stk.items[stk.items.len-1-low];
                const highv =
                    if(high == stk.items.len) 0
                else stk.items[stk.items.len-1-high];

                //Top of stack
                const top = stk.items[stk.items.len-1];

                //Mixed value from low and high
                const nlow = lowv * (1-flow) + flow * top;
                const nhigh = highv * (1-fhigh) + fhigh * top;

                //Set values
                stk.items[stk.items.len-1-low] = nlow;
                if(high != stk.items.len)
                    stk.items[stk.items.len-1-high] = nhigh;
            },
        }
    }
}
