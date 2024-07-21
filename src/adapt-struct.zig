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


//A fxn that reads each member, if it's name begins with a string compared case insensetive,
//rename it with such prefix removed, unless it's name is only that prefix

//Take a comptime file name
//Import it
fn reformat_names(datype: type, import_str: [] const u8, writer: anytype, to_remove: []const [] const u8) !void{
    const thing = @typeInfo(datype).Struct;
    const pval = std.fmt.comptimePrint("count = {}\n", .{@typeInfo(datype)});
    std.debug.print("{s}\n", .{pval});
    @setEvalBranchQuota(10000);
    const module_name = "_c";
    try writer.print("pub const {s} = {s};\n", .{module_name, import_str});


    inline for(thing.decls)|fld|{
        //if begins with to_remove, remove to_remove, else same
        // What if conflicts ?? eh.. ignore it
        //std.debug.print("a", .{});
        for(to_remove)|pref|{
            //std.debug.print("{s}\n", .{std.fmt.comptimePrint("{}", .{fld})});
            if(std.ascii.startsWithIgnoreCase(fld.name, pref)){
                try writer.print("pub const {s} = {s}.{s};\n",
                                 .{fld.name[pref.len..], module_name, fld.name});
                break;
            }

            // else{
            //     try writer.print("pub const {s} = @import(\"" ++ "fil" ++ "\").{s};\n",
            //                      .{fld.name, fld.name});
            // }
        }
    }
}

pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _=gpa.deinit();

    const allocr = gpa.allocator();
    _=allocr;
    {
        const file = try std.fs.cwd().createFile(
            "ts_imported.zig",
            .{ .read = true },
        );
        defer file.close();

        try reformat_names(ts.tsa,
                           \\@cImport({
                           \\  @cInclude("tree_sitter/api.h");
                           \\  @cInclude("stdlib.h");
                           \\})
                           ,file.writer().any(), &[_][]const u8{"ts_","ts"});
        //Write to file ?
        //std.debug.print("The reformated one\n{s}\n", .{arr.items});
    }

}
