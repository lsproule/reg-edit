# reg-edit

Edit Vim registers in a temporary buffer, then write them back with `:w`.

## Setup

```lua
require("reg-edit").setup({
  command_name = "RegEdit",
  keys = {
    open = "<leader>re",
    clear = "<leader>c",
  },
})
```

`keys.open` is global and opens the register editor.
`keys.clear` is buffer-local inside the RegEdit buffer and clears register contents on each register line.

## Usage

1. Open with `:RegEdit` or the open keymap.
2. Edit register contents in the `Content` column.
3. `:w` writes back all writable registers and closes the window.

Read-only special registers (`:`, `.`, `%`, `#`) are shown but not written.
