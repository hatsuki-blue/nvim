-- 画面下の「パネル」でターミナルを扱う (VSCode のターミナルに近い動き)
--   * F4 でパネルを開閉。閉じても中のプロセス (ssh / claude など) は動き続ける
--   * パネルはエディタの下に開く (サイドバーのツリーの下には潜り込まない)
--   * パネル右側にターミナル一覧。追加/分割は「今のターミナルと同じ種類」で開く
--     (SSH 中なら同じホストへの SSH、この PC ならシェル)
local M = {}
local api = vim.api

local SIDEBAR = { ["neo-tree"] = true, ["remote-tree"] = true, ["term-list"] = true }
local LIST_W = 26
local I = { pc = "\u{f489}", server = "\u{f233}", claude = "\u{f544}" }

-- この PC のシェル。Windows は PowerShell 7 (無ければ Windows PowerShell)、Linux / macOS は $SHELL
local is_windows = vim.fn.has("win32") == 1
if is_windows then
  M.shell_cmd = vim.fn.executable("pwsh") == 1 and { "pwsh", "-NoLogo" } or { "powershell", "-NoLogo" }
else
  M.shell_cmd = { vim.env.SHELL ~= nil and vim.env.SHELL ~= "" and vim.env.SHELL or "sh" }
end
M.shell_name = vim.fn.fnamemodify(M.shell_cmd[1], ":t:r")
M.last = nil -- 最後に使っていたターミナル
M.local_shell = nil
M.order = {} -- 一覧に並べる順 (開いた順)
M.hidden = {} -- F4 で隠したときに並んでいたターミナル

local function is_float(w)
  return api.nvim_win_get_config(w).relative ~= ""
end

local function is_term(b)
  return b and api.nvim_buf_is_valid(b) and vim.bo[b].buftype == "terminal"
end

-- 動いているターミナルか
-- ※jobwait() で調べると、停止処理中の ssh に対して nvim が落ちることがあるため
--   TermClose で立てる exited と、終了指示で立てる killed のフラグで判定する
local function alive(b)
  return is_term(b) and vim.b[b].terminal_job_id ~= nil and not vim.b[b].exited and not vim.b[b].killed
end
M.alive = alive

local function wins()
  return vim.tbl_filter(function(w) return not is_float(w) end, api.nvim_tabpage_list_wins(0))
end

local function is_sidebar(w)
  return SIDEBAR[vim.bo[api.nvim_win_get_buf(w)].filetype] == true
end

local function win_of(buf)
  for _, w in ipairs(wins()) do
    if api.nvim_win_get_buf(w) == buf then return w end
  end
end

function M.is_editor_win(w)
  return not is_float(w) and not is_term(api.nvim_win_get_buf(w)) and not is_sidebar(w)
end

function M.term_wins()
  return vim.tbl_filter(function(w) return is_term(api.nvim_win_get_buf(w)) end, wins())
end

-- ファイルを開くためのウィンドウ (無ければサイドバーの右に作る)
function M.editor_win()
  local cur = api.nvim_get_current_win()
  if M.is_editor_win(cur) then return cur end
  for _, w in ipairs(wins()) do
    if M.is_editor_win(w) then return w end
  end
  return api.nvim_open_win(api.nvim_create_buf(true, false), false, { split = "right", win = -1 })
end

-- ウィンドウを閉じる。サイドバー以外で最後の1枚なら、閉じずに空のバッファにする
-- (ツリーだけが画面いっぱいに広がるのを防ぐ)
local function close_win(w)
  if not api.nvim_win_is_valid(w) then return end
  for _, x in ipairs(wins()) do
    if x ~= w and not is_sidebar(x) then
      return pcall(api.nvim_win_close, w, true)
    end
  end
  api.nvim_win_set_buf(w, api.nvim_create_buf(true, false))
end

local function terms()
  M.order = vim.tbl_filter(alive, M.order)
  return M.order
end

-- ===== 右側のターミナル一覧 =====
local list = { buf = nil, rows = {} }
local ns = api.nvim_create_namespace("term_list")

local function list_win()
  return list.buf and api.nvim_buf_is_valid(list.buf) and win_of(list.buf) or nil
end

local function icon(b)
  if vim.b[b].is_claude then return I.claude end
  if vim.b[b].remote_host then return I.server end
  return I.pc
end

local function render_list()
  local buf = list.buf
  if not (buf and api.nvim_buf_is_valid(buf)) then return end
  local lines, marks = { " ターミナル" }, {}
  list.rows = {}
  for _, b in ipairs(terms()) do
    local mark = b == M.last and "▶" or (win_of(b) and "●" or " ")
    lines[#lines + 1] = " " .. mark .. " " .. icon(b) .. " " .. (vim.b[b].term_label or "terminal")
    list.rows[#lines] = b
    marks[#lines] = b == M.last and "PmenuSel" or (win_of(b) and "Normal" or "Comment")
  end
  vim.list_extend(lines, { "", " Enter 切替  x 終了", " n 追加  v 分割" })
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  api.nvim_buf_set_extmark(buf, ns, 0, 0, { line_hl_group = "Title" })
  for row, hl in pairs(marks) do
    api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { line_hl_group = hl })
  end
  for row = #lines - 1, #lines do
    api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { line_hl_group = "Comment" })
  end
end

-- パネルが出ていれば一覧も出す / パネルが無ければ一覧も閉じる
function M.sync_list()
  local tw = M.term_wins()
  local lw = list_win()
  if #tw == 0 then
    if lw then pcall(api.nvim_win_close, lw, true) end
    return
  end
  if not lw then
    lw = api.nvim_open_win(list.buf, false, { split = "right", win = tw[#tw], width = LIST_W })
    for opt, val in pairs({
      number = false, relativenumber = false, signcolumn = "no", foldcolumn = "0",
      winfixwidth = true, cursorline = false, wrap = false, list = false,
    }) do
      api.nvim_set_option_value(opt, val, { scope = "local", win = lw })
    end
  end
  render_list()
end

local sync_pending = false
local function schedule_sync()
  if sync_pending then return end
  sync_pending = true
  vim.schedule(function()
    sync_pending = false
    M.sync_list()
  end)
end

-- ===== 表示と起動 =====
local function panel_win()
  local tw = M.term_wins()
  if #tw > 0 then return win_of(M.last) or tw[#tw] end
  local target = M.editor_win()
  local h = math.max(8, math.floor((vim.o.lines - 2) / 2))
  return api.nvim_open_win(api.nvim_win_get_buf(target), false, { split = "below", win = target, height = h })
end

-- ターミナルをパネルに表示して入力状態にする
--   split = true なら、パネルを左右に分割して隣に表示する
function M.show(buf, split)
  local tw = M.term_wins()
  local w = win_of(buf)
  if not w then
    if split and #tw > 0 then
      w = api.nvim_open_win(buf, false, { split = "right", win = tw[#tw] })
    else
      w = panel_win()
    end
    api.nvim_win_set_buf(w, buf)
  end
  for opt, val in pairs({ number = false, relativenumber = false, signcolumn = "no", winfixheight = true }) do
    api.nvim_set_option_value(opt, val, { scope = "local", win = w })
  end
  api.nvim_set_current_win(w)
  M.last = buf
  M.sync_list()
  vim.cmd("startinsert")
  return w
end

-- コマンドをパネルのターミナルで実行する
--   cmd: 文字列ならシェル (PowerShell) 経由、配列ならそのまま実行
--   opts.split: 左右に分割して開く / opts.esc = false: Esc Esc を割り当てない (Claude Code 用)
--   opts.vars: バッファ変数 (term_label, remote_host, autoclose など)
function M.run(cmd, opts)
  opts = opts or {}
  if type(cmd) == "string" then
    cmd = vim.list_extend(vim.deepcopy(M.shell_cmd), { is_windows and "-Command" or "-c", cmd })
  end
  local buf = api.nvim_create_buf(false, false) -- タブ一覧には出さない
  for k, v in pairs(opts.vars or {}) do vim.b[buf][k] = v end
  M.show(buf, opts.split)
  vim.fn.jobstart(cmd, { term = true, cwd = opts.cwd })
  vim.bo[buf].bufhidden = "hide"
  if opts.esc ~= false then
    vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { buffer = buf, desc = "ターミナル → 操作モード" })
  end
  -- ターミナルをクリックしたら入力状態に戻す
  -- (ホイールでスクロールしたり Esc Esc した後は操作モードのままになり、
  --  同じウィンドウをクリックしてもウィンドウ移動が起きないので自動では戻らない)
  -- ※全体に割り当てると nvim のダブルクリック判定が乱れ、neo-tree でファイルを
  --   ダブルクリックしたときに開いた先で文字選択が始まるので、このバッファだけにする
  vim.keymap.set("n", "<LeftRelease>", function()
    if alive(buf) then vim.cmd("startinsert") end
  end, { buffer = buf, desc = "クリックで入力状態に" })
  table.insert(M.order, buf)
  M.sync_list()
  vim.cmd("startinsert")
  return buf
end

-- この PC のシェル (1つを使い回す)
function M.shell()
  if alive(M.local_shell) then return M.show(M.local_shell) end
  M.local_shell = M.run(M.shell_cmd, { vars = { term_label = M.shell_name, autoclose = true } })
end

-- 追加 / 分割: 今のターミナルと同じ種類で開く
--   SSH (や接続先の Claude) を使っていたら、同じホストに SSH をもう1つ
--   それ以外は、この PC の pwsh
function M.new_like(split, src)
  local cur = api.nvim_get_current_buf()
  src = src or (is_term(cur) and cur) or M.last
  if is_term(src) and vim.b[src].remote_target then
    return require("user.remote").connect(vim.b[src].remote_target, { cwd = vim.b[src].remote_cwd, split = split })
  end
  return M.run(M.shell_cmd, { split = split, vars = { term_label = M.shell_name, autoclose = true } })
end

-- F4: パネルの開閉。隠したときに並んでいたターミナルを、そのまま並べて戻す
function M.toggle()
  local tw = M.term_wins()
  if #tw > 0 then
    local cur = api.nvim_get_current_buf()
    if is_term(cur) then M.last = cur end
    M.hidden = vim.tbl_map(api.nvim_win_get_buf, tw)
    vim.cmd("stopinsert")
    for _, w in ipairs(tw) do close_win(w) end
    M.sync_list()
    return
  end
  local bufs = vim.tbl_filter(alive, M.hidden)
  if #bufs == 0 then
    if alive(M.last) then return M.show(M.last) end
    return M.shell()
  end
  local last = M.last
  for i, b in ipairs(bufs) do M.show(b, i > 1) end
  if alive(last) and win_of(last) then M.show(last) end
end

-- 開いているターミナルを一覧から選ぶ
function M.pick()
  local items = terms()
  if #items == 0 then return vim.notify("開いているターミナルはありません") end
  vim.ui.select(items, {
    prompt = "ターミナルを選択",
    format_item = function(b) return vim.b[b].term_label or api.nvim_buf_get_name(b) end,
  }, function(b) if b then M.show(b) end end)
end

-- バッファを閉じる (ウィンドウ配置は崩さない)
function M.close_buf(buf)
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(w) and api.nvim_win_get_buf(w) == buf then close_win(w) end
  end
  pcall(api.nvim_buf_delete, buf, { force = true })
  schedule_sync()
end

-- 終了したターミナルの後片付け。表示中なら、隠れている別のターミナルに差し替える
local function cleanup(buf)
  if not api.nvim_buf_is_valid(buf) then return end
  local w = win_of(buf)
  if w then
    for _, b in ipairs(terms()) do
      if b ~= buf and not win_of(b) then
        api.nvim_win_set_buf(w, b)
        M.last = b
        break
      end
    end
  end
  M.close_buf(buf)
end

-- ターミナルを終了する (一覧の x / Alt-x)
-- ※動いているジョブのバッファを直接消すと nvim が落ちるので、止めるだけにして
--   後片付けは TermClose の後に行う
function M.kill(buf)
  if not is_term(buf) then return end
  if alive(buf) then
    vim.b[buf].killed = true
    schedule_sync()
    -- 表示し直した直後 (サイズ変更の処理中) に止めると nvim が落ちることがあるので少し待つ
    local job = vim.b[buf].terminal_job_id
    vim.defer_fn(function() pcall(vim.fn.jobstop, job) end, 300)
  else
    vim.schedule(function() cleanup(buf) end)
  end
end

-- 一覧のカーソル行のターミナルに切り替える
-- (クリック時は nvim 標準のクリックでカーソルを置いてから呼ぶ。位置ずれ防止)
function M.list_open_current()
  if vim.bo.filetype ~= "term-list" then return end
  local b = list.rows[api.nvim_win_get_cursor(0)[1]]
  if b then M.show(b) end
end

local function list_keymaps(buf)
  local function row_buf()
    return list.rows[api.nvim_win_get_cursor(0)[1]]
  end
  local function m(keys, fn, desc)
    for _, k in ipairs(type(keys) == "table" and keys or { keys }) do
      vim.keymap.set("n", k, fn, { buffer = buf, desc = desc, nowait = true })
    end
  end
  m({ "<CR>", "o" }, function()
    local b = row_buf()
    if b then M.show(b) end
  end, "このターミナルに切り替え")
  -- クリックは離した位置のターミナルに切り替える (位置ずれ防止。remote.lua のツリーと同じ方式)
  vim.keymap.set("n", "<LeftRelease>", "<LeftMouse><Cmd>lua require('user.terminal').list_open_current()<CR>",
    { buffer = buf, desc = "クリックで切り替え", nowait = true })
  -- ドラッグや v での範囲選択は使わない (選択モードになると which-key の一覧が出てしまう)
  for _, k in ipairs({ "<LeftMouse>", "<LeftDrag>", "<2-LeftMouse>", "<3-LeftMouse>", "<RightMouse>", "v", "V", "<C-v>", "gv" }) do
    vim.keymap.set("n", k, "<Nop>", { buffer = buf, nowait = true })
  end
  m({ "x", "d", "<Del>" }, function() M.kill(row_buf()) end, "このターミナルを終了")
  m("n", function() M.new_like(false, row_buf()) end, "同じ種類のターミナルを追加")
  m("v", function() M.new_like(true, row_buf()) end, "同じ種類のターミナルを分割して追加")
  m("q", M.toggle, "パネルを閉じる")
end

-- <Space>q: 今のファイルを閉じる (VSCode のタブを閉じる感覚。ウィンドウは残す)
function M.close_current()
  local buf = api.nvim_get_current_buf()
  if is_term(buf) then return M.toggle() end
  if SIDEBAR[vim.bo[buf].filetype] then return vim.cmd("close") end
  if vim.bo[buf].modified then
    local c = vim.fn.confirm("変更を保存しますか?", "&Yes\n&No\n&Cancel", 3)
    if c == 1 then vim.cmd("write") elseif c ~= 2 then return end
  end
  local alt = vim.fn.bufnr("#")
  if alt > 0 and alt ~= buf and vim.fn.buflisted(alt) == 1 then
    vim.cmd("buffer #")
  else
    local other
    for _, b in ipairs(api.nvim_list_bufs()) do
      if b ~= buf and vim.fn.buflisted(b) == 1 then other = b break end
    end
    if other then api.nvim_win_set_buf(0, other) else vim.cmd("enew") end
  end
  pcall(api.nvim_buf_delete, buf, { force = true })
end

function M.setup()
  list.buf = api.nvim_create_buf(false, true)
  vim.bo[list.buf].filetype = "term-list"
  vim.bo[list.buf].bufhidden = "hide"
  vim.bo[list.buf].modifiable = false
  list_keymaps(list.buf)

  local g = api.nvim_create_augroup("user_terminal", {})

  api.nvim_create_autocmd("TermOpen", {
    group = g,
    callback = function()
      vim.opt_local.number = false
      vim.opt_local.relativenumber = false
      vim.opt_local.signcolumn = "no"
    end,
  })

  -- ターミナルに入ったら自動で入力状態に (E21 エラー防止)
  api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = g,
    callback = function(ev)
      if not is_term(ev.buf) then return end
      M.last = ev.buf
      schedule_sync()
      vim.schedule(function()
        if api.nvim_get_current_buf() == ev.buf and alive(ev.buf) and api.nvim_get_mode().mode ~= "t" then
          vim.cmd("startinsert")
        end
      end)
    end,
  })

  -- 正常終了 (exit) したら、パネルのターミナルも閉じる
  api.nvim_create_autocmd("TermClose", {
    group = g,
    callback = function(ev)
      vim.b[ev.buf].exited = true
      if vim.b[ev.buf].killed or (vim.v.event.status == 0 and vim.b[ev.buf].autoclose) then
        -- 直後に消すと、表示し直し中のターミナル処理と競合して nvim が落ちることがあるので少し待つ
        vim.defer_fn(function() cleanup(ev.buf) end, 200)
      else
        schedule_sync()
      end
    end,
  })

  -- ウィンドウを閉じたら一覧を更新 (ターミナルが無くなれば一覧も閉じる)
  api.nvim_create_autocmd("WinClosed", { group = g, callback = schedule_sync })
end

return M
