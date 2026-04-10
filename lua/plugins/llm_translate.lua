return {
  "AstroNvim/astrocore",
  opts = function(_, opts)
    require("llm_translate").setup({ api_key = vim.g.ark_api_key })
    opts.mappings = opts.mappings or {}
    opts.mappings.n = vim.tbl_extend("force", opts.mappings.n or {}, {
      ["<Leader>at"] = { function() require("llm_translate").translate_current_line() end, desc = "Translate line" },
    })
    opts.mappings.v = vim.tbl_extend("force", opts.mappings.v or {}, {
      ["<Leader>at"] = { function() require("llm_translate").translate_visual() end, desc = "Translate selection" },
    })
  end,
}
