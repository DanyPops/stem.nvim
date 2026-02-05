# stem.nvim

Create a single workspace root so AI/tools can work across multiple repositories.

Stem builds a temporary root under `/tmp/stem.nvim/<name>` and mounts multiple
directories into it, letting you work across repositories with one working
directory.

## Requirements

- `bindfs` (FUSE) is required and runs without root.
- Stem will error on startup if `bindfs` or FUSE are unavailable.

Check requirements:

```bash
command -v bindfs
test -r /dev/fuse
```

## Install (lazy.nvim)

```lua
{
  "DanyPops/stem.nvim",
  config = function()
    require("stem").setup()
  end,
}
```

## Quickstart

```
:StemNew my-workspace
:StemAdd ~/code/repo-a
:StemAdd ~/code/repo-b
:StemSave my-workspace
:StemClose
:StemOpen my-workspace
```

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
- `:StemInfo [name]` - show workspace roots
- `:StemCleanup` - cleanup orphaned mounts

## Session behavior

On `:StemClose`, a session is saved for the current workspace (if named) to
`stdpath("data")/stem/sessions/<name>.vim`. When opening a workspace with
`:StemOpen` or `:StemNew <name>`, a matching session is automatically loaded.

## Storage

Each workspace is stored as a Lua file in `stdpath("data")/stem/workspaces/`.
Lua is used because it is Neovim-native, commentable, and easy to hand-edit.

## Why FUSE?

Stem aims to emulate Cursor-style multi-repo workspaces inside Neovim. Cursor can
present multiple roots as a single workspace by aggregating them in the UI and
indexer, but Neovim and most tools are path-centric and expect a real directory.
FUSE (via `bindfs`) is the most practical way to provide a true, namespaced
workspace path without root access.

## Options

```lua
require("stem").setup({
  workspace = {
    auto_add_cwd = true,
    confirm_close = true,
    temp_root = "/tmp/stem.nvim/saved",
    temp_untitled_root = "/tmp/stem.nvim/temp",
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

## Development

- Tests: `make test`
- Requires `bindfs` and `/dev/fuse` for the suite to run
