local M = {}

-- Filesystem roots for workspace storage and temp mounts.
M.paths = {
  workspace_dir = "stem/workspaces",
  session_dir = "stem/sessions",
  default_temp_root = "/tmp/stem.nvim/saved",
  default_temp_untitled_root = "/tmp/stem.nvim/temp",
}

-- External executables invoked by stem.
M.commands = {
  bindfs = "bindfs",
  mount = "mount",
  fusermount = "fusermount",
  umount = "umount",
  kill = "kill",
}

-- Bindfs mount parsing and metadata strings.
M.mount = {
  fuse_type = "fuse.bindfs",
  mount_type_pattern = " type fuse%.bindfs",
  disambiguation_fmt = "%s__%d",
}

-- File extensions and glob patterns used on disk.
M.files = {
  workspace_ext = ".lua",
  session_ext = ".vim",
  temp_ext = ".tmp",
  glob_all = "*",
}

-- Fixed names for synthetic workspaces and lock dirs.
M.names = {
  untitled = "untitled",
  locks_dir = ".locks",
  undefined = "undefined",
}

-- Regex patterns used to detect stem naming.
M.patterns = {
  untitled_name = "^untitled%d*$",
}

-- UI formatting fragments for list/status output.
M.ui = {
  notify_title = "stem",
  workspace_name_prompt = "Workspace name: ",
  roots_header = "Roots:",
  empty_roots_item = " - (none)",
  list_item_prefix = " - ",
  list_current_marker = " *",
}

-- Event channel names emitted by lifecycle.
M.events = {
  mounts_changed = "mounts_changed",
  workspace_unmounted = "workspace_unmounted",
  buffer_mapped = "buffer_mapped",
  buffer_unmapped = "buffer_unmapped",
}

-- Vim command prefixes used with vim.cmd.
M.vim = {
  source_cmd = "silent! source ",
  mksession_cmd = "silent! mksession! ",
  edit_cmd = "edit ",
  cd_cmd = "cd ",
  tcd_cmd = "tcd ",
}

-- User-facing notification and error messages.
M.messages = {
  bindfs_missing = "bindfs not found; cannot mount workspace",
  failed_bindfs = "Failed to bindfs %s: %s",
  invalid_workspace_name = "Invalid workspace name: %s",
  failed_write_workspace = "Failed to write workspace: %s",
  failed_save_workspace = "Failed to save workspace: %s",
  failed_load_workspace = "Failed to load workspace %s: %s",
  missing_temp_root = "missing temp_root",
  unsafe_path = "unsafe path",
  invalid_path = "invalid path",
  not_a_directory = "not a directory",
  workspace_name_required = "Workspace name required",
  workspace_not_found = "Workspace not found: %s",
  save_cancelled = "Save cancelled",
  directory_required = "Directory required",
  directory_not_found = "Directory not found: %s",
  already_added = "Already added: %s",
  added = "Added: %s",
  removed = "Removed: %s",
  open_workspace = "Opened workspace: %s",
  open_unnamed = "Opened unnamed workspace",
  saved_workspace = "Saved workspace: %s",
  workspace_closed = "Workspace closed",
  renamed_workspace = "Renamed workspace: %s -> %s",
  renamed_workspace_to = "Renamed workspace to: %s",
  workspace_exists = "Workspace already exists: %s",
  no_workspaces = "No workspaces",
  list_header = "Workspaces:",
  status_header = "Workspace:",
  no_workspace_open = "No workspace open",
  new_name_required = "New name required",
  close_unnamed_confirm = "Close unnamed workspace without saving?",
  close_unsaved_confirm = "Close workspace with unsaved changes?",
  missing_roots = "Workspace has missing roots:",
  gc_unmount_errors_header = "Garbage collector unmount errors:",
  bootstrap_bindfs = "stem.nvim requires bindfs to be installed",
  bootstrap_fuse = "stem.nvim requires FUSE (/dev/fuse) to be available",
}

-- Environment variable names used for configuration.
M.env = {
  skip_bootstrap = "STEM_SKIP_BOOTSTRAP",
  tmp_root = "STEM_TMP_ROOT",
  tmp_untitled_root = "STEM_TMP_UNTITLED_ROOT",
}

-- Default bindfs arguments and related knobs.
M.bindfs = {
  default_args = { "--no-allow-other" },
}

-- Oil integration metadata.
M.oil = {
  filetype = "oil",
  uri_pattern = "^oil%-%w+://",
}

-- Autocmd event groups used in setup.
M.autocmds = {
  buf_enter = { "BufEnter" },
  buf_leave = { "BufWinLeave", "BufDelete" },
  vim_leave_pre = "VimLeavePre",
}

-- User command names and option shorthands.
M.user_commands = {
  new = "StemNew",
  open = "StemOpen",
  save = "StemSave",
  close = "StemClose",
  add = "StemAdd",
  remove = "StemRemove",
  rename = "StemRename",
  list = "StemList",
  status = "StemStatus",
  info = "StemInfo",
  cleanup = "StemCleanup",
}

M.command_opts = {
  nargs_optional = "?",
  nargs_required = 1,
  nargs_none = 0,
  nargs_plus = "+",
  complete_dir = "dir",
}

-- Process probing helpers.
M.process = {
  kill_check_args = { "-0" },
}

-- Time formats for lock metadata.
M.time = {
  lock_timestamp_fmt = "!%Y-%m-%dT%H:%M:%SZ",
}

return M
