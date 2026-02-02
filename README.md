# stem.nvim

A lightweight pseudo-workspace plugin for Neovim. It builds a temporary root
under `/tmp/stem/<name>` and symlinks multiple directories into it, letting you
work across multiple repositories with a single working directory.

## Storage

Each workspace is stored as a Lua file in `stdpath("data")/stem/workspaces/`.
Lua is used because it is Neovim-native, commentable, and easy to hand-edit.

## Commands

- `:StemNew [name]` - start a new workspace (unnamed if omitted)
- `:StemOpen <name>` - open a saved workspace
- `:StemSave [name]` - save the current workspace
- `:StemClose` - close the current workspace
- `:StemAdd <dir>` - add a directory to the workspace
- `:StemRemove <dir>` - remove a directory from the workspace
- `:StemRename <new>` - rename the current workspace
- `:StemRename <old> <new>` - rename a saved workspace
- `:StemList` - list saved workspaces
- `:StemStatus` - show current workspace status
