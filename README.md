An attempt to make a stack based virtual machine that will host a c based interpreter.

Currently developing the stack based virtual machine.

Dependency:
- zig 0.13.0 version
- treesitter library
- treesitter parser for c and json (json probably won't matter)
- Assumes the treesitter library is based , from parent folder to treesitter/tree-sitter/zig-out/lib
- Assumes treesitter headers is based, from parent folder to treesitter/tree-sitter/lib/include
- Assumes treesitter c(or json) source code is based, from parent folder to treesitter/tree-sitter-c(or json)/src/parser.c

Compile just using zig build command, outputs in the zig-out directory
To run directly, do zig build run command
