---@type LazySpec
return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = function(_, opts)
    opts = opts or {}
    opts.filesystem = opts.filesystem or {}
    opts.filesystem.filtered_items = vim.tbl_deep_extend("force", opts.filesystem.filtered_items or {}, {
      hide_dotfiles = false,
      hide_hidden = false,
    })
    return opts
  end,
}
