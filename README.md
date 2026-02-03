# stem.nvim

A lightweight pseudo-workspace plugin for Neovim. It builds a temporary root
under `/tmp/stem/<name>` and mounts multiple directories into it, letting you
work across multiple repositories with a single working directory.

## Requirements

- `bindfs` (FUSE) is required and runs without root.
- Stem will error on startup if `bindfs` or FUSE are unavailable.

## Why FUSE?

Stem aims to emulate Cursor-style multi-repo workspaces inside Neovim. Cursor can
present multiple roots as a single workspace by aggregating them in the UI and
indexer, but Neovim and most tools are path-centric and expect a real directory.
FUSE (via `bindfs`) is the most practical way to provide a true, namespaced
workspace path without root access.

## Storage

Each workspace is stored as a Lua file in `stdpath("data")/stem/workspaces/`.
Lua is used because it is Neovim-native, commentable, and easy to hand-edit.

## Commands

- `:StemNew [name]` - start a new workspace (unnamed if omitted)
- `:StemOpen <name>` - open a saved workspace
- `:StemSave [name]` - save the current workspace
- `:StemClose` - close the current workspace
- `:StemAdd [dir]` - add a directory (defaults to current context)
- `:StemRemove <dir>` - remove a directory from the workspace
- `:StemRename <new>` - rename the current workspace
- `:StemRename <old> <new>` - rename a saved workspace
- `:StemList` - list saved workspaces
- `:StemStatus` - show current workspace status
- `:StemUntitledList` - list untitled workspaces

## Session behavior

On `:StemClose`, a session is saved for the current workspace (if named) to
`stdpath("data")/stem/sessions/<name>.vim`. When opening a workspace with
`:StemOpen` or `:StemNew <name>`, a matching session is automatically loaded.

## Options

```lua
require("stem").setup({
  workspace = {
    auto_add_cwd = true,
    confirm_close = true,
    temp_root = "/tmp/stem/named",
    temp_untitled_root = "/tmp/stem/temporary",
    bindfs_args = { "--no-allow-other" },
  },
  session = {
    enabled = true,
    auto_load = true,
  },
  oil = {
    follow = true,
  },
})
```
