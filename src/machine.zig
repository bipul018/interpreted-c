const std = @import("std");


//Generate the stack based machine code
const Operation = union(enum){
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
const FxnList = std.StringHashMap([] const Operation);
const Stack = std.ArrayList(f64);
fn exec_ops(fxns: FxnList, ops: [] const Operation, stk: *Stack,
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

pub fn main() !void{
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _=gpa.deinit();

    const allocr = gpa.allocator();
    //_=allocr;

    std.debug.print("Size of Operation is : {}\n", .{@sizeOf(Operation)});
    
    var fxns = FxnList.init(allocr);
    defer fxns.deinit();
    
    //Expects a value 'N' identifying the number of iterations
    // push 0, xch, subtract 1,  if negative return
    // xch, pop
    // push 1, xch, subtract 1, if negative return
    // xch pop
    // Now two base cases are implemented, and the stack has N-2
    // dup, call recursively
    // xch, add 1, call recursively
    // add, return
    //var fibo:[] const Operation = undefined;
    const fibo_code = [_]Operation{
        .{.push = 0}, .{.xch = {}},
        .{.push = 1}, .{.sub = {}}, .{.ron = {}},

        .{.xch = {}}, .{.pop = {}},

        .{.push = 1}, .{.xch = {}}, .{.push = 1}, .{.sub = {}}, .{.ron = {}},

        .{.xch = {}}, .{.pop = {}},

        .{.dup = {}}, .{.call = "fibonacci"},

        .{.xch = {}}, .{.push = 1}, .{.add = {}}, .{.call = "fibonacci"},

        .{.add = {}},
    };
    try fxns.put("fibonacci", &fibo_code);

    //indexes into an array of 5 elememts
    // const inx_5_code = [_]Operation{
    //     .{.dup = 5}, .{.push = 1}, .{.xch = {}}, .{.push = 1}, .{.sub = {}},
    //     .{.ron = {}}, .{.call = "inx_5"}, .{.push = 1}, .{.xch = {}}, .{.pop = {}},
    // };
    //try fxns.put("inx_5", &inx_5_code);

    //pop n items
    const pop_n_code = [_]Operation{
        .{.push = -1}, .{.add = {}}, .{.ron = {}},
        .{.xch = {}}, .{.pop = {}}, .{.call = "pop_n"},
    };
    try fxns.put("pop_n", &pop_n_code);

    //Sum of n items
    const sum_n_code = [_]Operation{
        .{.push=2}, .{.sub={}}, .{.ron={}}, .{.push=1}, .{.add={}},
        .{.xch2={}}, .{.add={}},
        .{.xch={}}, .{.call="sum_n"}
    };
    try fxns.put("sum_n", &sum_n_code);

    //A fxn that gets
    const get_code = [_]Operation{
        .{.dup={}}, .{.get={}},
    };
    try fxns.put("get", &get_code);

    //Bubble sort
    const if_case_code = [_]Operation{
        .{.push=1}, .{.dup={}}, .{.get={}},
        .{.dup={}},.{.push=3},.{.add={}},.{.get={}},
        .{.push=2},.{.dup={}},.{.get={}},.{.dup={}},
        .{.push=5},.{.add={}},.{.get={}},
        .{.sub={}},.{.ron={}},.{.pop={}},

        .{.push=1},.{.dup={}},.{.get={}},.{.dup={}},.{.push=3},.{.add={}},.{.get={}},
        .{.push=2},.{.dup={}},.{.get={}},.{.dup={}},.{.push=5},.{.add={}},.{.get={}},

        .{.push=3},.{.dup={}},.{.get={}},.{.push=4},.{.add={}},.{.set={}},.{.pop={}},
        .{.push=2},.{.dup={}},.{.get={}},.{.push=4},.{.add={}},.{.set={}},.{.pop={}},
    };
    try fxns.put("if_case", &if_case_code);

    const inner_loop_code = [_]Operation{
        .{.brk={}},
        .{.dup={}}, .{.push=1}, .{.get={}},
        .{.dup={}}, .{.push=3}, .{.get={}},
        .{.sub={}}, .{.push=2}, .{.add={}},
        .{.rop={}}, .{.pop={}},

        //.{.brk={}},
        .{.call="if_case"},
        //.{.brk={}},
        .{.dup={}}, .{.push=1}, .{.get={}},
        .{.push=1}, .{.add={}},
        .{.push=1}, .{.set={}}, .{.pop={}},
        //.{.brk={}},
        .{.call="inner_loop"}
    };
    try fxns.put("inner_loop", &inner_loop_code);

    const outer_loop_code = [_]Operation{
        .{.dup={}},.{.push=2},.{.get={}},
        .{.push=1},.{.sub={}},.{.ron={}},.{.pop={}},

        .{.push=0},.{.push=1},.{.set={}},.{.pop={}},

        .{.call="inner_loop"},

        .{.dup={}},.{.push=2},.{.get={}},.{.push=1},.{.sub={}},
        .{.push=2},.{.set={}},.{.pop={}},

        .{.call="outer_loop"},
    };
    try fxns.put("outer_loop", &outer_loop_code);

    const bubble_sort_code=[_]Operation{
        .{.push=1},.{.call="outer_loop"},.{.pop={}}
    };
    try fxns.put("bubble_sort", &bubble_sort_code);

    {
        std.debug.print("Trying out sorting...\n", .{});
        var stk = Stack.init(allocr);
        defer stk.deinit();
        
        try stk.appendSlice(&[5] f64{3,4,5,6,1});
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});

        const ops=[_]Operation{.{.push=@floatFromInt(stk.items.len)},
                               //.{.push=2},
                               .{.call="bubble_sort"},
                               //.{.pop={}},
                               .{.pop={}}};
        try exec_ops(fxns, &ops, &stk, .nodebug);
        std.debug.print("After sorting ...\n", .{});
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});
    }
                  
        
    {
        var stk = Stack.init(allocr);
        defer stk.deinit();
        
        try stk.appendSlice(&[5] f64{3,4,5,6,1});
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});
        
        for(0..stk.items.len*2-1)|i|{
            std.debug.print("Finding index {}/2 item... \n", .{i});

            const ops=[_]Operation{.{.push=@as(f64,@floatFromInt(i))*0.5},
                                   .{.call="get"}};
            try exec_ops(fxns, &ops, &stk, .nodebug);

            for(stk.items)|it|{
                std.debug.print("{d} ", .{it});
            }
            std.debug.print("\n", .{});
            _=stk.pop();
        }

        std.debug.print("The array : \n", .{});
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});
        std.debug.print("Now popping count/2 items...\n", .{});
        {
            const ops=[_]Operation{.{.push=@floatFromInt(stk.items.len/2)},
                                   .{.call="pop_n"}};
            try exec_ops(fxns, &ops, &stk, .nodebug);
        }
        
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});

        std.debug.print("Calculating sum of items...\n", .{});
        {
            const ops=[_]Operation{.{.push=@floatFromInt(stk.items.len)},
                                   .{.call="sum_n"}};
            try exec_ops(fxns, &ops, &stk, .nodebug);
        }
        
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});
    }

    
    
    for(0..10)|i|{
        var stk = Stack.init(allocr);
        defer stk.deinit();
        if(fxns.get("fibonacci"))|fxn|{
            try stk.append(@floatFromInt(i));
            try exec_ops(fxns, fxn, &stk, .nodebug);
        }
        std.debug.print("i = {}, Ans = ",
                        .{i});
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});
    }
    
    
}
