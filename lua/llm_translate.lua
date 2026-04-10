local M = {}

M.config = {
  base_url = "https://ark.cn-beijing.volces.com/api/v3",
  api_key = "9eb8ec90-e514-4147-a04e-e1e856dcd53c",
  model = "ep-20260325091209-jj9hm",
  prompt_template = "请将下面内容翻译成中文，可适当整理格式，但不需要加入额外的内容：\n\n%s",
  stream = true,
  float_filetype = "markdown",
  float_position = "cursor",
  float_offset = { row = 1, col = 0 },
  float_width = { min = 40, max = 120, ratio = 0.85, padding = 6 },
}

function M.setup(opts)
  if type(opts) == "table" then M.config = vim.tbl_deep_extend("force", M.config, opts) end
end

M._float = { win_by_buf = {}, meta_by_buf = {} }

local function get_visual_selection()
  local mode = vim.fn.mode()
  local s
  local e

  if mode == "v" or mode == "V" or mode == "\22" then
    s = vim.fn.getpos("v")
    e = vim.fn.getpos(".")
  else
    s = vim.fn.getpos("'<")
    e = vim.fn.getpos("'>")
  end

  local ls, cs = s[2], s[3]
  local le, ce = e[2], e[3]
  if ls == 0 or le == 0 then return "" end
  if ls > le or (ls == le and cs > ce) then
    ls, le = le, ls
    cs, ce = ce, cs
  end

  if mode == "V" then
    local lines = vim.api.nvim_buf_get_lines(0, ls - 1, le, false)
    return table.concat(lines, "\n")
  end

  if mode == "\22" then
    local saved = vim.fn.getreginfo("z")
    vim.cmd([[silent! noautocmd normal! "zy]])
    local text = vim.fn.getreg("z")
    vim.fn.setreg("z", saved)
    return text or ""
  end

  local lines = vim.api.nvim_buf_get_lines(0, ls - 1, le, false)
  if #lines == 0 then return "" end
  if #lines == 1 then
    lines[1] = string.sub(lines[1], cs, ce)
  else
    lines[1] = string.sub(lines[1], cs)
    lines[#lines] = string.sub(lines[#lines], 1, ce)
  end
  return table.concat(lines, "\n")
end

local function clamp(value, min_value, max_value)
  return math.max(min_value, math.min(value, max_value))
end

local function max_display_width(lines)
  local maxw = 0
  for _, line in ipairs(lines or {}) do
    if type(line) == "string" then
      local w = vim.fn.strdisplaywidth(line)
      if w > maxw then maxw = w end
    end
  end
  return maxw
end

local function float_dims(lines)
  local columns = vim.o.columns
  local lines_total = vim.o.lines
  local width_cfg = M.config.float_width or {}
  local ratio = tonumber(width_cfg.ratio) or 0.85
  local max_width = tonumber(width_cfg.max) or 120
  local min_width = tonumber(width_cfg.min) or 40
  local padding = tonumber(width_cfg.padding) or 6

  local max_allowed = math.max(20, columns - 4)
  max_width = math.min(max_width, math.floor(columns * ratio), max_allowed)
  min_width = math.min(min_width, max_width)

  local content_w = max_display_width(lines) + padding
  local width = clamp(content_w, min_width, max_width)

  local max_height = math.floor((lines_total - 4) * 0.85)
  if max_height < 6 then max_height = 6 end
  local height = math.min(math.max(#(lines or {}) + 2, 6), max_height)
  return width, height
end

local function float_place(width, height, meta)
  local columns = vim.o.columns
  local lines_total = vim.o.lines
  local max_row = math.max(0, lines_total - height - 2)
  local max_col = math.max(0, columns - width)

  local pos = (meta and meta.position) or M.config.float_position or "cursor"
  local off = (meta and meta.offset) or M.config.float_offset or {}
  local off_row = tonumber(off.row) or 0
  local off_col = tonumber(off.col) or 0

  if pos == "center" then
    local row = math.max(0, math.floor((lines_total - height) / 2))
    local col = math.max(0, math.floor((columns - width) / 2))
    return math.min(row, max_row), math.min(col, max_col)
  end

  local anchor = (meta and meta.anchor) or {}
  local arow = tonumber(anchor.row) or (vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col(".")).row - 1)
  local acol = tonumber(anchor.col) or (vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col(".")).col - 1)

  local row_below = arow + off_row
  local row_above = arow - height - 1
  local row = row_below
  if row_below > max_row and row_above >= 0 then row = row_above end
  row = math.max(0, math.min(row, max_row))

  local col = acol + off_col
  col = math.max(0, math.min(col, max_col))

  return row, col
end

local function close_float(buf)
  local win = M._float.win_by_buf[buf]
  if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  M._float.win_by_buf[buf] = nil
  M._float.meta_by_buf[buf] = nil
end

local function resize_float(buf, lines)
  local win = M._float.win_by_buf[buf]
  if not (win and vim.api.nvim_win_is_valid(win)) then return end
  local meta = M._float.meta_by_buf[buf] or {}
  local width, height = float_dims(lines)
  local row, col = float_place(width, height, meta)
  vim.api.nvim_win_set_config(win, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = meta.border or "rounded",
    title = meta.title,
    title_pos = meta.title_pos or "center",
  })
end

local function open_float(title, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or {})
  vim.bo[buf].modifiable = false
  if type(M.config.float_filetype) == "string" and M.config.float_filetype ~= "" then
    vim.bo[buf].filetype = M.config.float_filetype
  end

  local sp = vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col("."))
  local meta = {
    title = title,
    title_pos = "center",
    border = "rounded",
    position = M.config.float_position,
    offset = M.config.float_offset,
    anchor = { row = (sp.row or 1) - 1, col = (sp.col or 1) - 1 },
  }

  local width, height = float_dims(lines or {})
  local row, col = float_place(width, height, meta)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })

  M._float.win_by_buf[buf] = win
  M._float.meta_by_buf[buf] = meta

  vim.keymap.set("n", "q", function()
    close_float(buf)
  end, { buffer = buf, nowait = true, silent = true })

  vim.keymap.set({ "n", "i" }, "<Esc>", function()
    close_float(buf)
  end, { buffer = buf, nowait = true, silent = true })

  vim.keymap.set({ "n", "i" }, "<A-`>", function()
    close_float(buf)
  end, { buffer = buf, nowait = true, silent = true })

  return buf, win
end

local function set_float_lines(buf, new_lines)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
  vim.bo[buf].modifiable = false
  resize_float(buf, new_lines or {})
end

local function extract_text(resp)
  if type(resp) ~= "table" then return nil end
  if type(resp.output_text) == "string" and resp.output_text ~= "" then return resp.output_text end
  if type(resp.text) == "string" and resp.text ~= "" then return resp.text end

  local function read_output(output)
    if type(output) ~= "table" then return nil end
    local chunks = {}
    for _, item in ipairs(output) do
      if type(item) == "table" and type(item.content) == "table" then
        for _, c in ipairs(item.content) do
          if type(c) == "table" then
            if type(c.text) == "string" and c.text ~= "" then table.insert(chunks, c.text) end
            if type(c.output_text) == "string" and c.output_text ~= "" then table.insert(chunks, c.output_text) end
          end
        end
      end
    end
    if #chunks > 0 then return table.concat(chunks, "\n") end
    return nil
  end

  local out = read_output(resp.output)
  if out then return out end

  if type(resp.choices) == "table" and type(resp.choices[1]) == "table" then
    local msg = resp.choices[1].message
    if type(msg) == "table" and type(msg.content) == "string" then return msg.content end
  end

  return nil
end

local function parse_stream_update(evt)
  if type(evt) ~= "table" then return nil end
  if type(evt.delta) == "string" and evt.delta ~= "" then return { kind = "append", text = evt.delta } end
  if type(evt.output_text) == "string" and evt.output_text ~= "" then
    local t = tostring(evt.type or "")
    if t:find("done", 1, true) then return { kind = "done", text = evt.output_text } end
    return { kind = "replace", text = evt.output_text }
  end
  if type(evt.text) == "string" and evt.text ~= "" then return { kind = "replace", text = evt.text } end
  return nil
end

local function translate_via_curl_nonstream(text, cb)
  local api_key = M.config.api_key
  if not api_key or api_key == "" then
    cb(nil, "未配置 api_key")
    return
  end

  local url = ("%s/responses"):format(M.config.base_url)
  local payload = vim.json.encode({
    model = M.config.model,
    input = (M.config.prompt_template):format(text),
    thinking = { type = "disabled" },
  })

  local args = {
    "curl",
    "-sS",
    "-X",
    "POST",
    url,
    "-H",
    "Content-Type: application/json",
    "-H",
    "Authorization: Bearer " .. api_key,
    "-d",
    payload,
  }

  if vim.system then
    vim.system(args, { text = true }, function(res)
      if res.code ~= 0 then
        cb(nil, (res.stderr and res.stderr ~= "" and res.stderr) or ("curl 退出码: %s"):format(res.code))
        return
      end
      local ok, decoded = pcall(vim.json.decode, res.stdout or "")
      if not ok then
        cb(nil, "API 返回非 JSON")
        return
      end
      local out = extract_text(decoded)
      cb(out or vim.inspect(decoded), nil)
    end)
    return
  end

  local raw = vim.fn.system(args)
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok then
    cb(nil, "API 返回非 JSON")
    return
  end
  local out = extract_text(decoded)
  cb(out or vim.inspect(decoded), nil)
end

local function translate_via_curl_stream(text, handlers)
  local api_key = M.config.api_key
  if not api_key or api_key == "" then
    handlers.on_error("未配置 api_key")
    return
  end

  local url = ("%s/responses"):format(M.config.base_url)
  local payload = vim.json.encode({
    model = M.config.model,
    input = (M.config.prompt_template):format(text),
    thinking = { type = "disabled" },
    stream = true,
  })

  local args = {
    "curl",
    "-sS",
    "-N",
    "-X",
    "POST",
    url,
    "-H",
    "Content-Type: application/json",
    "-H",
    "Authorization: Bearer " .. api_key,
    "-d",
    payload,
  }

  local saw_any = false
  local stderr_chunks = {}

  local function on_error(err)
    if type(err) == "string" and err ~= "" then handlers.on_error(err) end
  end

  local jobid = vim.fn.jobstart(args, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      if type(data) ~= "table" then return end
      for _, line in ipairs(data) do
        if type(line) == "string" and line ~= "" then
          line = line:gsub("\r", "")
          local data_payload = line:match("^data:%s*(.*)$")
          if data_payload then
            saw_any = true
            if data_payload == "[DONE]" then
              handlers.on_done()
              return
            end
            local ok, decoded = pcall(vim.json.decode, data_payload)
            if ok then
              local upd = parse_stream_update(decoded)
              if upd and upd.text then
                if upd.kind == "append" and handlers.on_append then handlers.on_append(upd.text) end
                if upd.kind == "replace" and handlers.on_replace then handlers.on_replace(upd.text) end
                if upd.kind == "done" then handlers.on_done(upd.text) end
              end
            end
          elseif line:sub(1, 1) == "{" then
            saw_any = true
            local ok, decoded = pcall(vim.json.decode, line)
            if ok then
              local out = extract_text(decoded)
              if out and out ~= "" then handlers.on_done(out) end
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if type(data) ~= "table" then return end
      for _, line in ipairs(data) do
        if type(line) == "string" and line ~= "" then table.insert(stderr_chunks, line) end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        local msg = (#stderr_chunks > 0) and table.concat(stderr_chunks, "\n") or ("curl 退出码: %s"):format(code)
        on_error(msg)
        return
      end
      if not saw_any then handlers.on_error("未收到流式输出") end
    end,
  })

  if jobid <= 0 then
    handlers.on_error("启动 curl 失败")
  end
end

function M.translate_text(text)
  text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    open_float("翻译", { "没有可翻译的文本" })
    return
  end

  local buf = open_float("翻译", { "正在翻译中..." })
  if M.config.stream then
    local acc = ""
    local pending = false

    local function render_now()
      local out_lines = vim.split(acc, "\n", { plain = true })
      if #out_lines == 0 then out_lines = { "" } end
      set_float_lines(buf, out_lines)
    end

    local function schedule_render()
      if pending then return end
      pending = true
      vim.defer_fn(function()
        pending = false
        if vim.api.nvim_buf_is_valid(buf) then render_now() end
      end, 50)
    end

    translate_via_curl_stream(text, {
      on_append = function(chunk)
        acc = acc .. chunk
        vim.schedule(schedule_render)
      end,
      on_replace = function(full)
        acc = full
        vim.schedule(schedule_render)
      end,
      on_done = function(final_text)
        if type(final_text) == "string" and final_text ~= "" then
          acc = final_text
        end
        vim.schedule(render_now)
      end,
      on_error = function(err)
        vim.schedule(function() set_float_lines(buf, { "翻译失败", "", err }) end)
      end,
    })
    return
  end

  translate_via_curl_nonstream(text, function(result, err)
    vim.schedule(function()
      if err then
        set_float_lines(buf, { "翻译失败", "", err })
        return
      end
      local out_lines = vim.split(result or "", "\n", { plain = true })
      if #out_lines == 0 then out_lines = { "" } end
      set_float_lines(buf, out_lines)
    end)
  end)
end

function M.translate_visual()
  local text = get_visual_selection()
  M.translate_text(text)
end

function M.translate_current_line()
  local line = vim.api.nvim_get_current_line()
  M.translate_text(line)
end

return M
