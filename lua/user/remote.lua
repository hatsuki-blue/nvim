-- SSH 接続先のファイルツリーと、接続先ファイルの編集
--   * ツリーは `ssh ホスト ls` の結果を表示するだけのシンプルな作り (鍵認証が前提)
--   * ファイルを開くと手元のキャッシュにダウンロードし、:w で接続先へ書き戻す
--   * SSH のターミナルで cd すると、ツリーも自動で追従する (OSC 7)
local M = {}
local api = vim.api

local I = {
  server = "\u{f233}",
  folder = "\u{f07b}",
  file = "\u{f15b}",
  up = "\u{f062}",
}
local HEADER = 2 -- 1行目: ホスト:パス / 2行目: ..

M.state = {
  target = nil, -- ssh に渡す引数 (例 { "myserver" } や { "-p", "2222", "user@host" })
  host = nil, -- 表示用のホスト名 (target の最後)
  cwd = nil, -- ツリーに表示中のディレクトリ (接続先の絶対パス)
  entries = {},
  hidden = false,
  buf = nil,
  req = 0,
  neotree_was_open = nil,
}
local state = M.state
local ns = api.nvim_create_namespace("remote_tree")

-- ===== ユーティリティ =====
local function shq(s)
  return "'" .. (s:gsub("'", [['\'']])) .. "'"
end

local function join(dir, name)
  return (dir == "/" and "" or dir) .. "/" .. name
end

local function parent(dir)
  if not dir or dir == "/" then return "/" end
  local p = dir:gsub("/+$", ""):match("^(.*)/[^/]*$")
  return (p == nil or p == "") and "/" or p
end

local function notify_err(msg, r)
  local detail = r and vim.trim(r.stderr or "") or ""
  vim.notify(msg .. (detail ~= "" and ("\n" .. detail) or ""), vim.log.levels.ERROR)
end

-- 接続先でコマンドを1つ実行する (パスワード入力が必要なホストでは使えない)
local function ssh(target, cmd, opts, cb)
  opts = opts or {}
  local argv = { "ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10" }
  vim.list_extend(argv, target)
  table.insert(argv, cmd)
  vim.system(argv, { text = opts.text ~= false, stdin = opts.stdin }, function(r)
    vim.schedule(function() cb(r) end)
  end)
end

-- ~/.ssh/config に登録された Host 一覧 (ワイルドカードは除く)
function M.hosts()
  local hosts = {}
  local f = io.open(vim.fn.expand("~/.ssh/config"), "r")
  if not f then return hosts end
  for line in f:lines() do
    local names = line:match("^%s*[Hh]ost%s+(.+)$")
    if names then
      for name in names:gmatch("%S+") do
        if not name:find("[*?!]") then table.insert(hosts, name) end
      end
    end
  end
  f:close()
  return hosts
end

function M.complete(lead)
  return vim.tbl_filter(function(h)
    return vim.startswith(h:lower(), lead:lower())
  end, M.hosts())
end

-- 生きている SSH ターミナルのバッファ一覧 (host 指定でそのホストのみ)
local function sessions(host)
  local list = {}
  local alive = require("user.terminal").alive
  for _, b in ipairs(api.nvim_list_bufs()) do
    if alive(b) and vim.b[b].remote_host and (not host or vim.b[b].remote_host == host) then
      table.insert(list, b)
    end
  end
  return list
end

-- ===== ツリーの描画 =====
local function tree_win()
  if not (state.buf and api.nvim_buf_is_valid(state.buf)) then return nil end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_buf(w) == state.buf then return w end
  end
end

local function icon_for(e)
  if e.dir then return I.folder, "Directory" end
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if ok then
    local ic, hl = devicons.get_icon(e.name, e.name:match("%.([^.]+)$"), { default = true })
    if ic then return ic, hl end
  end
  return I.file, nil
end

local function render(focus_name)
  local buf = state.buf
  if not (buf and api.nvim_buf_is_valid(buf)) then return end
  local lines = {
    " " .. I.server .. " " .. (state.host or "?") .. ":" .. (state.cwd or "…"),
    "  " .. I.up .. " ..  (上の階層へ)",
  }
  local marks = {}
  for i, e in ipairs(state.entries) do
    local ic, hl = icon_for(e)
    local prefix = "  " .. ic .. " "
    lines[#lines + 1] = prefix .. e.name .. (e.dir and "/" or "")
    marks[#marks + 1] = { HEADER + i - 1, hl, #prefix, e.dir }
  end
  if #state.entries == 0 and state.cwd then lines[#lines + 1] = "  (空のフォルダ)" end

  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = #lines[1], hl_group = "Title" })
  api.nvim_buf_set_extmark(buf, ns, 1, 0, { end_col = #lines[2], hl_group = "Comment" })
  for _, m in ipairs(marks) do
    local row, hl, icon_end, is_dir = m[1], m[2], m[3], m[4]
    if hl then api.nvim_buf_set_extmark(buf, ns, row, 0, { end_col = icon_end, hl_group = hl }) end
    if is_dir then
      api.nvim_buf_set_extmark(buf, ns, row, icon_end, { end_col = #lines[row + 1], hl_group = "Directory" })
    end
  end

  local win = tree_win()
  if win then
    local row = #state.entries > 0 and HEADER + 1 or HEADER
    for i, e in ipairs(state.entries) do
      if e.name == focus_name then row = HEADER + i end
    end
    pcall(api.nvim_win_set_cursor, win, { row, 0 })
  end
end

local function cursor_entry_name()
  local win = tree_win()
  if not win then return nil end
  local e = state.entries[api.nvim_win_get_cursor(win)[1] - HEADER]
  return e and e.name
end

local function same_entries(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i].name ~= b[i].name or a[i].dir ~= b[i].dir then return false end
  end
  return true
end

-- 接続先のディレクトリを読み込んでツリーに表示する (dir が nil ならホーム)
--   opts.silent: 自動更新用。「読み込み中」を出さず、中身が同じなら描き直さない。
--                カーソルは同じ項目の上に残す
function M.open_dir(dir, focus_name, opts)
  if not state.target then return end
  opts = opts or {}
  if opts.silent and state.loading then return end -- 移動中は自動更新しない
  state.req = state.req + 1
  local req = state.req
  if not opts.silent then
    state.loading = true
    if state.buf and api.nvim_buf_is_valid(state.buf) then
      vim.bo[state.buf].modifiable = true
      api.nvim_buf_set_lines(state.buf, 0, 1, false, { " " .. I.server .. " " .. state.host .. ":  読み込み中…" })
      vim.bo[state.buf].modifiable = false
    end
  end
  local flags = state.hidden and "-1ApL" or "-1pL"
  local cmd = "cd -- " .. (dir and shq(dir) or "~") .. " && pwd && { LC_ALL=C ls " .. flags .. " 2>/dev/null; true; }"
  ssh(state.target, cmd, nil, function(r)
    if req ~= state.req then return end -- もっと新しい移動が来ている
    state.loading = false
    if r.code ~= 0 then
      if opts.silent then return end -- 自動更新の失敗 (フォルダが消えた等) は黙って無視
      render()
      return notify_err("接続先のフォルダを開けませんでした: " .. (dir or "~"), r)
    end
    local lines = vim.split(r.stdout or "", "\n", { trimempty = true })
    state.cwd = table.remove(lines, 1)
    local entries = {}
    for _, l in ipairs(lines) do
      local is_dir = l:sub(-1) == "/"
      table.insert(entries, { name = is_dir and l:sub(1, -2) or l, dir = is_dir })
    end
    table.sort(entries, function(a, b)
      if a.dir ~= b.dir then return a.dir end
      return a.name:lower() < b.name:lower()
    end)
    local win, prev_row = tree_win(), nil
    if opts.silent then
      if same_entries(entries, state.entries) then return end
      focus_name = cursor_entry_name()
      prev_row = win and api.nvim_win_get_cursor(win)[1]
    end
    state.entries = entries
    render(focus_name)
    -- カーソルが ".." などの上にあった場合は、同じ行に残す
    if prev_row and not focus_name and win and api.nvim_win_is_valid(win) then
      pcall(api.nvim_win_set_cursor, win, { math.min(prev_row, api.nvim_buf_line_count(state.buf)), 0 })
    end
  end)
end

-- 今のフォルダを読み直す (追加/削除されたファイルを反映)
function M.refresh()
  if state.target and state.cwd and tree_win() then M.open_dir(state.cwd, nil, { silent = true }) end
end

-- ===== 接続先ファイルの編集 =====
local function cache_path(host, path)
  local safe = path:gsub('[:*?"<>|]', "_")
  return vim.fs.normalize(vim.fn.stdpath("cache") .. "/remote/" .. host:gsub("[^%w%-_.]", "_") .. safe)
end

function M.edit(path)
  local target, host = state.target, state.host
  ssh(target, "cat -- " .. shq(path), { text = false }, function(r)
    if r.code ~= 0 then return notify_err("ファイルを開けませんでした: " .. host .. ":" .. path, r) end
    local lp = cache_path(host, path)
    local existing = -1
    for _, b in ipairs(api.nvim_list_bufs()) do
      if vim.fs.normalize(api.nvim_buf_get_name(b)):lower() == lp:lower() then existing = b end
    end
    if existing ~= -1 and api.nvim_buf_is_loaded(existing) and vim.bo[existing].modified then
      vim.notify("未保存の変更があるので、手元の編集中の内容を表示します", vim.log.levels.WARN)
    else
      vim.fn.mkdir(vim.fs.dirname(lp), "p")
      local f = assert(io.open(lp, "wb"))
      f:write(r.stdout or "")
      f:close()
    end
    api.nvim_set_current_win(require("user.terminal").editor_win())
    vim.cmd("edit " .. vim.fn.fnameescape(lp))
    local buf = api.nvim_get_current_buf()
    if existing == buf and not vim.bo[buf].modified then vim.cmd("silent edit!") end -- 最新の内容に更新
    vim.b[buf].remote_file = { target = target, host = host, path = path }
    -- 開いたら編集できる状態 (入力モード) にする
    if _G.UserEnterEdit then vim.schedule(_G.UserEnterEdit) end
  end)
end

-- :w したら接続先へ書き戻す
function M.upload(buf)
  local rf = vim.b[buf].remote_file
  if not rf then return end
  local f = io.open(api.nvim_buf_get_name(buf), "rb")
  if not f then return end
  local data = f:read("*a")
  f:close()
  ssh(rf.target, "cat > " .. shq(rf.path), { stdin = data, text = false }, function(r)
    if r.code ~= 0 then return notify_err("接続先への保存に失敗しました: " .. rf.host .. ":" .. rf.path, r) end
    vim.notify("接続先に保存しました: " .. rf.host .. ":" .. rf.path)
    if state.host == rf.host and state.cwd == parent(rf.path) then M.open_dir(state.cwd) end
  end)
end

-- ===== ツリーのキー操作 =====
local function current_entry()
  local row = api.nvim_win_get_cursor(0)[1]
  if row == HEADER then return "parent" end
  return state.entries[row - HEADER]
end

local function remote_exec(cmd, msg)
  ssh(state.target, cmd, nil, function(r)
    if r.code ~= 0 then return notify_err("失敗しました", r) end
    if msg then vim.notify(msg) end
    M.open_dir(state.cwd)
  end)
end

local function go_up()
  if not state.cwd then return end
  local from = state.cwd:match("([^/]+)/*$")
  M.open_dir(parent(state.cwd), from)
end

local actions = {}

function actions.open()
  local e = current_entry()
  if e == "parent" then return go_up() end
  if type(e) ~= "table" or not state.cwd then return end
  local path = join(state.cwd, e.name)
  if e.dir then M.open_dir(path) else M.edit(path) end
end

function actions.create()
  vim.ui.input({ prompt = "新規作成 (フォルダは末尾に / ): " }, function(name)
    if not name or vim.trim(name) == "" then return end
    local is_dir = name:sub(-1) == "/"
    local path = name:sub(1, 1) == "/" and name or join(state.cwd, name)
    path = path:gsub("/+$", "")
    local cmd = is_dir and ("mkdir -p -- " .. shq(path))
      or ("mkdir -p -- " .. shq(parent(path)) .. " && touch -- " .. shq(path))
    remote_exec(cmd, "作成しました: " .. path)
  end)
end

function actions.delete()
  local e = current_entry()
  if type(e) ~= "table" then return end
  local path = join(state.cwd, e.name)
  local msg = (e.dir and "フォルダごと削除しますか?\n" or "削除しますか?\n") .. state.host .. ":" .. path
  if vim.fn.confirm(msg, "&Yes\n&No", 2) ~= 1 then return end
  remote_exec((e.dir and "rm -rf -- " or "rm -f -- ") .. shq(path), "削除しました: " .. path)
end

function actions.rename()
  local e = current_entry()
  if type(e) ~= "table" then return end
  vim.ui.input({ prompt = "新しい名前: ", default = e.name }, function(new)
    if not new or vim.trim(new) == "" or new == e.name then return end
    local dst = new:sub(1, 1) == "/" and new or join(state.cwd, new)
    remote_exec("mv -- " .. shq(join(state.cwd, e.name)) .. " " .. shq(dst), "名前を変更しました: " .. dst)
  end)
end

function actions.copy_path()
  local e = current_entry()
  local path = type(e) == "table" and join(state.cwd, e.name) or state.cwd
  vim.fn.setreg("+", path)
  vim.notify("パスをコピーしました: " .. path)
end

-- このフォルダでターミナルを開く (既存の SSH ターミナルがあれば cd する)
function actions.terminal_here()
  if not state.cwd then return end
  local term = require("user.terminal")
  for _, b in ipairs(sessions(state.host)) do
    if not vim.b[b].is_claude then
      vim.fn.chansend(vim.b[b].terminal_job_id, "cd -- " .. shq(state.cwd) .. "\r")
      return term.show(b)
    end
  end
  M.connect(state.target, { cwd = state.cwd })
end

function actions.claude_here()
  if state.cwd then M.connect(state.target, { cwd = state.cwd, claude = true }) end
end

function actions.toggle_hidden()
  state.hidden = not state.hidden
  vim.notify(state.hidden and "隠しファイルを表示します" or "隠しファイルを隠します")
  M.open_dir(state.cwd)
end

local help = {
  " Enter / l / ダブルクリック  開く",
  " BS / h / u / -   上の階層へ",
  " ~                ホームへ",
  " a                新規作成 (末尾 / でフォルダ)",
  " d                削除",
  " r                名前変更",
  " y                パスをコピー",
  " t                このフォルダでターミナル",
  " c                このフォルダで Claude Code",
  " H                隠しファイル 表示/非表示",
  " R                再読み込み",
  " q                ツリーを閉じる",
}

function actions.help()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, help)
  vim.bo[buf].modifiable = false
  local w, h = 44, #help
  local win = api.nvim_open_win(buf, true, {
    relative = "editor", width = w, height = h, style = "minimal", border = "rounded",
    row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
    title = " 接続先ツリーの操作 ", title_pos = "center",
  })
  for _, k in ipairs({ "q", "<Esc>", "?" }) do
    vim.keymap.set("n", k, function() api.nvim_win_close(win, true) end, { buffer = buf })
  end
end

-- カーソル行の項目を開く
function M.open_current()
  if vim.bo.filetype == "remote-tree" then actions.open() end
end
-- クリックは「ボタンを離した位置」の項目を開く (VSCode のツリーと同じ)
-- ※nvim はマウス位置を「最後に届いた操作」で覚えるため、押した瞬間に開くと、
--   少しドラッグしただけで下の行が開くことがある。離した時点の位置なら画面と一致する
local RELEASE_OPEN = "<LeftMouse><Cmd>lua require('user.remote').open_current()<CR>"

local function set_keymaps(buf)
  local function m(keys, fn, desc)
    for _, k in ipairs(type(keys) == "table" and keys or { keys }) do
      vim.keymap.set("n", k, fn, { buffer = buf, desc = desc, nowait = true })
    end
  end
  -- 単クリックで開く (VSCode のツリーと同じ)。ドラッグや v での範囲選択は使わないので無効にする
  -- (選択モードになると which-key のキー一覧が出てしまうため)
  vim.keymap.set("n", "<LeftRelease>", RELEASE_OPEN, { buffer = buf, desc = "クリックで開く", nowait = true })
  for _, k in ipairs({ "<LeftMouse>", "<LeftDrag>", "<2-LeftMouse>", "<3-LeftMouse>", "<RightMouse>", "v", "V", "<C-v>", "gv" }) do
    vim.keymap.set("n", k, "<Nop>", { buffer = buf, nowait = true })
  end
  m({ "<CR>", "l", "o" }, actions.open, "開く")
  m({ "<BS>", "h", "u", "-" }, go_up, "上の階層へ")
  m("~", function() M.open_dir(nil) end, "ホームへ")
  m("R", function() M.open_dir(state.cwd) end, "再読み込み")
  m("H", actions.toggle_hidden, "隠しファイル 表示/非表示")
  m("a", actions.create, "新規作成")
  m("d", actions.delete, "削除")
  m("r", actions.rename, "名前変更")
  m("y", actions.copy_path, "パスをコピー")
  m("t", actions.terminal_here, "このフォルダでターミナル")
  m("c", actions.claude_here, "このフォルダで Claude Code")
  m("q", function() M.hide() end, "閉じる")
  m({ "?", "g?" }, actions.help, "操作一覧")
end

-- ===== ツリーの表示/非表示 =====
local function ensure_buf()
  if state.buf and api.nvim_buf_is_valid(state.buf) then return state.buf end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "remote-tree"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = false
  set_keymaps(buf)
  state.buf = buf
  return buf
end

function M.show()
  local win = tree_win()
  if win then return win end
  win = api.nvim_open_win(ensure_buf(), false, { split = "left", win = -1, width = 36 })
  for opt, val in pairs({
    number = false, relativenumber = false, signcolumn = "no", foldcolumn = "0",
    winfixwidth = true, cursorline = true, wrap = false, spell = false, list = false,
  }) do
    api.nvim_set_option_value(opt, val, { scope = "local", win = win })
  end
  render()
  return win
end

function M.hide()
  local win = tree_win()
  if not win then return end
  local others = 0
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if w ~= win and api.nvim_win_get_config(w).relative == "" then others = others + 1 end
  end
  if others > 0 then api.nvim_win_close(win, true) end
end

local function neotree_open()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(w)].filetype == "neo-tree" then return true end
  end
  return false
end

-- ツリーを接続先に切り替える
function M.attach(target, cwd)
  local host = target[#target]
  if state.neotree_was_open == nil then state.neotree_was_open = neotree_open() end
  pcall(vim.cmd, "Neotree close")
  local same = state.host == host
  state.target, state.host = target, host
  if not same then state.cwd, state.entries = nil, {} end
  M.show()
  M.open_dir(cwd or state.cwd)
end

-- 接続を全部閉じたら、手元のツリーに戻す
function M.detach()
  M.hide()
  state.target, state.host, state.cwd, state.entries = nil, nil, nil, {}
  if state.neotree_was_open then pcall(vim.cmd, "Neotree show") end
  state.neotree_was_open = nil
end

-- <Space>e : 接続中なら接続先ツリー、そうでなければ手元のツリーを開閉
function M.toggle_tree()
  if tree_win() then return M.hide() end
  if state.target then
    M.show()
    if not state.cwd then M.open_dir(nil) end
    return
  end
  vim.cmd("Neotree toggle")
end

-- ===== SSH 接続 =====
-- 接続先で実行するシェル。cd のたびに OSC 7 で現在地を nvim に知らせる
local function session_command(cwd)
  local rc = table.concat({
    "[ -f /etc/profile ] && . /etc/profile",
    "[ -f ~/.bashrc ] && . ~/.bashrc",
    'export PATH="$HOME/.local/bin:$PATH"',
    [[__nvim_osc7() { printf '\033]7;file://%s%s\033\\' "${HOSTNAME:-}" "$PWD"; }]],
    'PROMPT_COMMAND="__nvim_osc7${PROMPT_COMMAND:+; $PROMPT_COMMAND}"',
    cwd and ("cd -- " .. shq(cwd) .. " 2>/dev/null") or "cd ~",
    'rm -f -- "$__NVIM_RC"',
  }, "\n") .. "\n"
  return "if command -v bash >/dev/null 2>&1; then export __NVIM_RC=$(mktemp) && echo "
    .. vim.base64.encode(rc)
    .. ' | base64 -d > "$__NVIM_RC" && exec bash --rcfile "$__NVIM_RC" -i; else exec "$SHELL" -l; fi'
end

local function claude_command(cwd)
  return 'export PATH="$HOME/.local/bin:$PATH"; '
    .. (cwd and ("cd -- " .. shq(cwd) .. " 2>/dev/null; ") or "")
    .. "exec claude"
end

-- target: "host" / { "host" } / { "-p", "2222", "user@host" }
function M.connect(target, opts)
  opts = opts or {}
  if type(target) == "string" then target = vim.split(target, "%s+", { trimempty = true }) end
  local host = target[#target]
  M.attach(target, opts.cwd)
  local argv = { "ssh", "-t" }
  vim.list_extend(argv, target)
  table.insert(argv, opts.claude and claude_command(opts.cwd) or session_command(opts.cwd))
  require("user.terminal").run(argv, {
    split = opts.split,
    esc = not opts.claude, -- Claude Code では Esc をそのまま渡す
    vars = {
      remote_host = host,
      remote_target = target,
      is_claude = opts.claude or nil,
      term_label = (opts.claude and "Claude Code @ " or "SSH ") .. host,
      autoclose = true,
    },
  })
end

-- ホストを選んで接続 (引数があればそのまま)
function M.pick_and_connect(fargs, opts)
  if fargs and #fargs > 0 then return M.connect(fargs, opts) end
  vim.ui.select(M.hosts(), { prompt = opts and opts.claude and "Claude Code を起動するホスト" or "接続するホスト" },
    function(h) if h then M.connect({ h }, opts) end end)
end

function M.setup()
  local g = api.nvim_create_augroup("user_remote", {})

  -- どのモードからクリックしても、ツリーとターミナル一覧では同じ動きにする
  --   ターミナルで入力中 / ファイルを編集中 / 文字を選択中 にツリーをクリックすると、
  --   そのままでは「カーソルが動くだけ」で開かず、ドラッグすると文字の選択になってしまう
  -- 押したとき: ツリー/一覧の上なら、今のモードを抜けてそのウィンドウへ移るだけ
  --   (カーソルは動かさない。その後の ドラッグ/離す はツリー側の割り当てで処理され、
  --    離した位置の項目が開く)。ツリー以外は普段どおり。
  --   ※ドラッグ自体は横取りしない (エディタでの文字選択が効かなくなるため)
  --   ※通常モード (n) では割り当てない。nvim のダブルクリック判定が乱れて、
  --     neo-tree でファイルをダブルクリックすると開いた先で文字選択が始まってしまう。
  --     通常モードは標準のクリックでツリーへ移り、離したときにツリー側の割り当てで開く
  vim.keymap.set({ "t", "i", "x", "s" }, "<LeftMouse>", function()
    local pos = vim.fn.getmousepos()
    local buf = pos.winid > 0 and api.nvim_win_get_buf(pos.winid)
    local ft = buf and vim.bo[buf].filetype
    if (ft ~= "remote-tree" and ft ~= "term-list") or pos.winid == api.nvim_get_current_win() then
      return "<LeftMouse>"
    end
    local mode = api.nvim_get_mode().mode
    local leave = mode == "t" and [[<C-\><C-n>]] or (mode == "n" and "" or "<Esc>")
    return leave .. "<Cmd>lua vim.api.nvim_set_current_win(" .. pos.winid .. ")<CR>"
  end, { expr = true, desc = "クリック (ツリー/一覧は離した位置を開く)" })

  -- ツリーの中で選択モード (VISUAL) になったら、すぐ解除する
  -- (ツリーに文字の選択が入って、クリックやキーでの移動が効かなくなるのを防ぐ)
  api.nvim_create_autocmd("ModeChanged", {
    group = g,
    pattern = "*:[vV\22sS\19]*",
    callback = function()
      if vim.bo.filetype == "remote-tree" or vim.bo.filetype == "term-list" then
        api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
      end
    end,
  })

  -- 接続先ファイルを :w したらアップロード
  api.nvim_create_autocmd("BufWritePost", {
    group = g,
    callback = function(ev) if vim.b[ev.buf].remote_file then M.upload(ev.buf) end end,
  })

  -- SSH ターミナルで cd したら、ツリーも追従 (OSC 7)
  api.nvim_create_autocmd("TermRequest", {
    group = g,
    callback = function(ev)
      local seq = type(ev.data) == "table" and ev.data.sequence or ev.data
      if type(seq) ~= "string" then return end
      local path = seq:match("^\027%]7;file://[^/]*(/.*)$")
      local host = vim.b[ev.buf].remote_host
      if not (path and host) then return end
      path = path:gsub("\027\\$", ""):gsub("\a$", "")
      vim.b[ev.buf].remote_cwd = path
      if state.host ~= host then return end
      if state.cwd ~= path then
        M.open_dir(path)
      else
        -- プロンプトが出るたび (= コマンドを実行した後) に読み直す。mkdir / touch などを反映
        M.refresh()
      end
    end,
  })

  -- ツリーが表示されている間は定期的に読み直す (Claude Code など、ターミナル以外での変更を反映)
  local focused = true
  api.nvim_create_autocmd("FocusLost", { group = g, callback = function() focused = false end })
  api.nvim_create_autocmd("FocusGained", { group = g, callback = function() focused = true M.refresh() end })
  api.nvim_create_autocmd("BufEnter", {
    group = g,
    callback = function(ev) if vim.bo[ev.buf].filetype == "remote-tree" then M.refresh() end end,
  })
  local timer = vim.uv.new_timer()
  timer:start(5000, 5000, vim.schedule_wrap(function()
    if focused then M.refresh() end
  end))

  -- 別ホストの SSH ターミナルに切り替えたら、ツリーもそのホストに切り替え
  api.nvim_create_autocmd("BufEnter", {
    group = g,
    callback = function(ev)
      local host = vim.b[ev.buf].remote_host
      if vim.bo[ev.buf].buftype == "terminal" and host and state.host ~= host then
        M.attach(vim.b[ev.buf].remote_target, vim.b[ev.buf].remote_cwd)
      end
      -- ツリーだけが残ったら終了する (neo-tree と同じ挙動)
      if vim.bo[ev.buf].filetype == "remote-tree" then
        local n = 0
        for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
          if api.nvim_win_get_config(w).relative == "" then n = n + 1 end
        end
        if n == 1 then vim.schedule(function() pcall(vim.cmd, "confirm quit") end) end
      end
    end,
  })

  -- SSH が終了したら: 同じホストの接続が残っていなければツリーを戻す
  api.nvim_create_autocmd("TermClose", {
    group = g,
    callback = function(ev)
      local host = vim.b[ev.buf].remote_host
      if not host then return end
      vim.schedule(function()
        if state.host ~= host or #sessions(host) > 0 then return end
        local other = sessions()[1]
        if other then
          M.attach(vim.b[other].remote_target, vim.b[other].remote_cwd)
        else
          M.detach()
        end
      end)
    end,
  })
end

return M
