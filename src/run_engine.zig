const std = @import("std");
const vm = @import("engine.zig");
const gen = @import("gencode.zig");

test {
    _=@import("engine.zig");
    _=@import("gencode.zig");

    //Test one run of generate code from expression here

    
    
}

pub fn run_sample() !void{
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _=gpa.deinit();

    const allocr = gpa.allocator();
    //_=allocr;

    std.debug.print("Size of Operation is : {}\n", .{@sizeOf(vm.Operation)});
    
    var fxns = vm.FxnList.init(allocr);
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
    //var fibo:[] const vm.Operation = undefined;
    const fibo_code = [_]vm.Operation{
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
    // const inx_5_code = [_]vm.Operation{
    //     .{.dup = 5}, .{.push = 1}, .{.xch = {}}, .{.push = 1}, .{.sub = {}},
    //     .{.ron = {}}, .{.call = "inx_5"}, .{.push = 1}, .{.xch = {}}, .{.pop = {}},
    // };
    //try fxns.put("inx_5", &inx_5_code);

    //pop n items
    const pop_n_code = [_]vm.Operation{
        .{.push = -1}, .{.add = {}}, .{.ron = {}},
        .{.xch = {}}, .{.pop = {}}, .{.call = "pop_n"},
    };
    try fxns.put("pop_n", &pop_n_code);

    //Sum of n items
    const sum_n_code = [_]vm.Operation{
        .{.push=2}, .{.sub={}}, .{.ron={}}, .{.push=1}, .{.add={}},
        .{.xch2={}}, .{.add={}},
        .{.xch={}}, .{.call="sum_n"}
    };
    try fxns.put("sum_n", &sum_n_code);

    //A fxn that gets
    const get_code = [_]vm.Operation{
        .{.dup={}}, .{.get={}},
    };
    try fxns.put("get", &get_code);

    //Bubble sort
    const if_case_code = [_]vm.Operation{
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

    const inner_loop_code = [_]vm.Operation{
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

    const outer_loop_code = [_]vm.Operation{
        .{.dup={}},.{.push=2},.{.get={}},
        .{.push=1},.{.sub={}},.{.ron={}},.{.pop={}},

        .{.push=0},.{.push=1},.{.set={}},.{.pop={}},

        .{.call="inner_loop"},

        .{.dup={}},.{.push=2},.{.get={}},.{.push=1},.{.sub={}},
        .{.push=2},.{.set={}},.{.pop={}},

        .{.call="outer_loop"},
    };
    try fxns.put("outer_loop", &outer_loop_code);

    const bubble_sort_code=[_]vm.Operation{
        .{.push=1},.{.call="outer_loop"},.{.pop={}}
    };
    try fxns.put("bubble_sort", &bubble_sort_code);

    {
        std.debug.print("Trying out sorting...\n", .{});
        var stk = vm.Stack.init(allocr);
        defer stk.deinit();
        
        try stk.appendSlice(&[5] f64{3,4,5,6,1});
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});

        const ops=[_]vm.Operation{.{.push=@floatFromInt(stk.items.len)},
                               //.{.push=2},
                               .{.call="bubble_sort"},
                               //.{.pop={}},
                               .{.pop={}}};
        try vm.exec_ops(fxns, &ops, &stk, .nodebug);
        std.debug.print("After sorting ...\n", .{});
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});
    }
                  
        
    {
        var stk = vm.Stack.init(allocr);
        defer stk.deinit();
        
        try stk.appendSlice(&[5] f64{3,4,5,6,1});
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});
        
        for(0..stk.items.len*2-1)|i|{
            std.debug.print("Finding index {}/2 item... \n", .{i});

            const ops=[_]vm.Operation{.{.push=@as(f64,@floatFromInt(i))*0.5},
                                   .{.call="get"}};
            try vm.exec_ops(fxns, &ops, &stk, .nodebug);

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
            const ops=[_]vm.Operation{.{.push=@floatFromInt(stk.items.len/2)},
                                   .{.call="pop_n"}};
            try vm.exec_ops(fxns, &ops, &stk, .nodebug);
        }
        
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});

        std.debug.print("Calculating sum of items...\n", .{});
        {
            const ops=[_]vm.Operation{.{.push=@floatFromInt(stk.items.len)},
                                   .{.call="sum_n"}};
            try vm.exec_ops(fxns, &ops, &stk, .nodebug);
        }
        
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});
    }

    
    
    for(0..10)|i|{
        var stk = vm.Stack.init(allocr);
        defer stk.deinit();
        if(fxns.get("fibonacci"))|fxn|{
            try stk.append(@floatFromInt(i));
            try vm.exec_ops(fxns, fxn, &stk, .nodebug);
        }
        std.debug.print("i = {}, Ans = ",
                        .{i});
        for(stk.items)|it|{
            std.debug.print("{d} ", .{it});
        }
        std.debug.print("\n", .{});
    }
    
    
}
