const std = @import("std");
const ts = struct{
    // const tsa = @cImport({
    //     @cInclude("tree_sitter/api.h");
    //     @cInclude("stdlib.h");
    // });
    const tsa = @import("ts_imported.zig");
    usingnamespace tsa;
    pub extern fn tree_sitter_json() ?*tsa.Language;
    pub extern fn tree_sitter_c() ?*tsa.Language;
};

fn print_tree(root_node: ts.Node, source_code: [] const u8) void{
    var cur = ts.tree_cursor_new(root_node);
    defer ts.tree_cursor_delete(&cur);


    //Get and print current node
    var i:i32 = 0;
    outer: while(true){
        //const node = ts.tree_cursor_current_node(&cur);
        //const fname = ts.tree_cursor_current_field_name(&cur);
        const node = ts.tree_cursor_current_node(&cur);
        std.debug.print("\n", .{});
        for(0..@intCast(i))|_|{
            std.debug.print("    ", .{});
        }
        std.debug.print("( ", .{});
        //if(ts.node_is_named(node)){
        //std.debug.print("{s} ", .{ts.node_grammar_type(node)});
        //}

        if(0 != ts.node_child_count(node)){
            std.debug.print("{s} ", .{ts.node_type(node)});
        }
        else{
            if(std.mem.span(ts.node_type(node)).len != 1){
                std.debug.print("{s} ", .{ts.node_type(node)});
            }
            const sp = ts.node_start_byte(node);
            const ep = ts.node_end_byte(node);

            std.debug.print("\"{s}\" ", .{source_code[sp..ep]});
        }
        
        if(!ts.tree_cursor_goto_first_child(&cur)){
            std.debug.print(") ", .{});
            while(!ts.tree_cursor_goto_next_sibling(&cur)){
                std.debug.print(") ", .{});
                if(!ts.tree_cursor_goto_parent(&cur)){
                    break :outer;
                }
                i -= 1;
            }
        }
        else{
            i += 1;
        }
    }
}

//Evaluates any 'binary expression'

//Generate the stack based machine code
const Operation = union(enum){
    push:f64,
    pop:f64,
    add:void, 
    sub:void, //push a, push b, sub => a - b
    mul:void,
    div:void
};
//const Operations = std.ArrayList(Operation);
const Stack = std.ArrayList(f64);
fn exec_ops(ops: [] const Operation, stk: *Stack) !void{
    for(ops)|op|{
        switch(op){
            .push => |num|{
                try stk.append(num);
            },
            .pop => |num|{
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
            }
        }
    }
}



// Find a node of type that is of name given
fn find_first_tree(root_node: ts.Node, node_type: [] const u8) ?ts.Node{
    var cur = ts.tree_cursor_new(root_node);
    defer ts.tree_cursor_delete(&cur);

    var i:i32 = 0;
    outer: while(true){
        const node = ts.tree_cursor_current_node(&cur);

        if(0 != ts.node_child_count(node)){
            if(std.mem.eql(u8, node_type, std.mem.span(ts.node_type(node)))){
                //std.debug.print("{s} ", .{std.mem.span(ts.node_type(node)}));
                return node;
            }
        }
        else{
            if(std.mem.eql(u8, node_type, std.mem.span(ts.node_type(node)))){
                //std.debug.print("{s} ", .{std.mem.span(ts.node_type(node)}));
                return node;
            }
            // const sp = ts.node_start_byte(node);
            // const ep = ts.node_end_byte(node);
            // //std.debug.print("\"{s}\" ", .{source_code[sp..ep]});
        }
        
        if(!ts.tree_cursor_goto_first_child(&cur)){
            //std.debug.print(") ", .{});
            while(!ts.tree_cursor_goto_next_sibling(&cur)){
                //std.debug.print(") ", .{});
                if(!ts.tree_cursor_goto_parent(&cur)){
                    break :outer;
                }
                i -= 1;
            }
        }
        else{
            i += 1;
        }
    }
    return null;
}

pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _=gpa.deinit();

    const allocr = gpa.allocator();
    _=allocr;

    //Create a parser.
    
    const parser: *ts.Parser = ts.parser_new() orelse return;
    defer ts.parser_delete(parser);
    
    // Set the parser's language (JSON in this case).
    _=ts.parser_set_language(parser, ts.tree_sitter_c());

    // Build a syntax tree based on source code stored in a string.
    // const main_source_code =
    //     \\int funca(int y, int k){
    //     \\    int a = y * k, b = y + k;
    //     \\    int x = 5 * a - b / 3 ;
    //     \\    return x % 13;
    //     \\}
    // ;
    const main_source_code =
        \\(1 + 2) / 13 + 2 * 2 - 12;
    ;
    var source_code:[]const u8 = main_source_code;
    source_code = source_code[0..(source_code.len)];
    const tree: *ts.Tree  = ts.parser_parse_string(
        parser,
        null,
        @ptrCast(source_code),
        @intCast(source_code.len),
    ) orelse return;
    defer ts.tree_delete(tree);

    // Get the root node of the syntax tree.
    const root_node = ts.tree_root_node(tree);
    if(find_first_tree(root_node, "binary_expression"))|node|{
        print_tree(node, source_code);
    }
    else{
        std.debug.print("Not found the node type\n", .{});
    }
    
}
