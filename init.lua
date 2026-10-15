-- ===== 基本設定 =====
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ===== 環境ごとのスイッチ (学校の PC など、制限のある環境向け) =====
-- 設定フォルダに空のファイルを置くか、環境変数で切り替える。nvim 内の :Offline / :NoIcons でも切り替え可
--   offline  : 起動時の自動ダウンロード (LSP・整形ツール・パーサー・補完の高速版) をしない。
--              プロキシなどで外に出られない環境で、起動のたびに失敗・待ちが起きるのを防ぐ
--   no-icons : Nerd Font が無い環境向けに、アイコンを使わず普通の文字で表示する
local function flag(name, env)
  return vim.env[env] == "1" or vim.uv.fs_stat(vim.fn.stdpath("config") .. "/" .. name) ~= nil
end
vim.g.offline = flag("offline", "NVIM_OFFLINE")
vim.g.have_nerd_font = not flag("no-icons", "NVIM_NO_ICONS")
local offline, icons = vim.g.offline, vim.g.have_nerd_font
if not icons then
  -- アイコン用のプラグインを読み込ませない (各プラグインはアイコン無しの表示に切り替わる)
  package.preload["nvim-web-devicons"] = function() error("nvim-web-devicons は no-icons で無効") end
end

-- 文字コード: 内部は UTF-8、日本語の古いファイル(Shift_JIS/EUC-JP)も自動判別して開く
vim.opt.encoding = "utf-8"
vim.opt.fileencoding = "utf-8"
vim.opt.fileencodings = { "ucs-bom", "utf-8", "cp932", "euc-jp", "latin1" }
vim.opt.fileformats = { "unix", "dos" }
vim.opt.ambiwidth = "single" -- "double" にすると全角記号の幅が広がる (Nerd Font と相性が悪いので single)
vim.opt.helplang = { "ja", "en" }

local o = vim.opt
o.showmode = false -- lualine が表示するので不要
o.cmdheight = 1
o.laststatus = 3 -- ステータスラインを全体で1本
o.number = true
-- 行番号は普通の番号にする (相対番号だと、エラーの「〜行目」と画面の数字が合わずわかりにくい)
o.relativenumber = false
o.cursorline = true
o.signcolumn = "yes"
o.termguicolors = true
o.mouse = "a"
-- OS のクリップボードと共有 (xclip などのクリップボード連携が無い環境では使わない。
-- 無いのに設定すると、コピーのたびに "clipboard: No provider" と出る)
if vim.fn.has("win32") == 1 or vim.fn.has("mac") == 1 or vim.fn.executable("xclip") == 1
  or vim.fn.executable("xsel") == 1 or vim.fn.executable("wl-copy") == 1 then
  o.clipboard = "unnamedplus"
end
o.ignorecase = true
o.smartcase = true
o.undofile = true
-- スワップファイル (編集中の一時ファイル) は残す。
--   保存し忘れたまま強制終了 (ウィンドウを閉じる・PC が落ちる) したときの復元に使う。
--   ただし古いものが残っていると、次にそのファイルを開くたびに E325 の確認画面やエラーが出るので、
--   下の SwapExists で自動処理し、7日たった古いものは起動時に自動で消す。
o.swapfile = true
-- 別の nvim で同じファイルを変更した場合は、画面に戻ったときに自動で読み直す
o.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  callback = function()
    if vim.fn.mode() ~= "c" and vim.bo.buftype == "" then pcall(vim.cmd, "checktime") end
  end,
})
o.updatetime = 250
o.scrolloff = 8
o.splitright = true
o.splitbelow = true
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.wrap = false


-- ===== キーの方針 =====
-- Vim を覚えるため、Vim / nvim 本来のキーの動きは変えない。
-- 追加するのは、Vim が何も割り当てていないキーだけ:
--   * <Space> (リーダーキー) から始まるもの   * F4   * Alt-h/j/k/l
-- 元に戻す u / やり直し Ctrl-r / 保存 :w / コピー y / 貼り付け p / 画面移動 Ctrl-w h/j/k/l などは Vim のまま
local map = vim.keymap.set
map("n", "<Esc>", "<cmd>nohlsearch<CR>") -- 検索の色付けを消す (Vim では Esc は通常モードで何もしない)
-- Alt-h/j/k/l: どこからでも (入力中・選択中・ターミナルの中でも) 隣の画面へ。
-- Vim 本来の画面移動は Ctrl-w h/j/k/l (通常モードで使える。こちらを覚えるのがおすすめ)
for _, k in ipairs({ "h", "j", "k", "l" }) do
  map({ "n", "i" }, "<M-" .. k .. ">", "<Cmd>wincmd " .. k .. "<CR>")
  map({ "x", "s" }, "<M-" .. k .. ">", "<Esc><Cmd>wincmd " .. k .. "<CR>")
  map("t", "<M-" .. k .. ">", [[<C-\><C-n><C-w>]] .. k)
end
map("n", "<leader>w", "<cmd>w<CR>", { desc = "保存 (:w と同じ)" })
-- 入力モードを Ctrl-c で抜けても、Esc と同じ扱いにする (見た目の動きは同じ)。
--   Vim の Ctrl-c は「入力モードを抜けた」合図 (InsertLeave) を出さないため、入力中は隠している
--   エラー表示が出ないままになる。Vim の設定でよく使われる定番の修正
map("i", "<C-c>", "<Esc>")

-- 起動時の空のタブ [No Name] は、ファイルを開いたら自動で閉じる (タブ一覧に残り続けないように)
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(ev)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= ev.buf and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted and vim.bo[b].buftype == ""
        and vim.api.nvim_buf_get_name(b) == "" and not vim.bo[b].modified
        and vim.api.nvim_buf_line_count(b) == 1 and vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == ""
        and #vim.fn.win_findbuf(b) == 0 then
        vim.schedule(function() pcall(vim.api.nvim_buf_delete, b, {}) end)
      end
    end
  end,
})
map("n", "<leader>..", function()
  vim.cmd("cd ..")
  vim.cmd("Neotree dir=" .. vim.fn.fnameescape(vim.fn.getcwd()))
end, { desc = "作業ディレクトリを1つ上へ" })

-- ===== スワップファイルの自動処理 =====
-- ファイルを開くときに、そのファイルのスワップが既にあった場合 (確認画面 E325 の代わり):
--   * 別の nvim が今そのファイルを開いている → 読み取り専用で開く (二重編集を防ぐ)
--   * 持ち主がいない古いスワップで、保存していない編集が入っている → 自動で復元して知らせる
--   * 持ち主がいない古いスワップで、編集が入っていない → 削除して普通に開く
-- スワップの持ち主の nvim が、今もこの PC で動いているか
--   * 別の PC で作られたスワップ (学校のように、ホームがネットワーク上で複数の PC から使う場合) は、
--     この PC からは確かめられないので「動いていない」とみなす
--   * 番号が同じでも、別のプログラムに番号が再利用されていることがあるので、
--     Linux では実際に nvim かどうかも確かめる
local function swap_owner_alive(info)
  if not (info.pid and info.pid > 0) or info.pid == vim.uv.os_getpid() then return false end
  if info.host and info.host ~= "" and info.host:lower() ~= vim.uv.os_gethostname():lower() then return false end
  if vim.uv.kill(info.pid, 0) ~= 0 then return false end
  local f = io.open("/proc/" .. info.pid .. "/comm", "r")
  if f then
    local comm = f:read("*l") or ""
    f:close()
    return comm:find("nvim", 1, true) ~= nil
  end
  return true
end

vim.api.nvim_create_autocmd("SwapExists", {
  callback = function(ev)
    local sw = vim.v.swapname
    local info = vim.fn.swapinfo(sw)
    if info.error then return end -- 読めないときは nvim 標準の確認画面に任せる
    local name = vim.fn.fnamemodify(ev.file ~= "" and ev.file or (info.fname or ""), ":t")
    if swap_owner_alive(info) then
      vim.v.swapchoice = "o"
      vim.schedule(function()
        vim.notify(
          "「" .. name .. "」は、別の nvim (端末のほかのタブなど) で開いているため、読み取り専用で開きました。\n"
            .. "そちらを閉じてから開き直してください。どうしても編集するときは :set noreadonly",
          vim.log.levels.WARN
        )
      end)
    elseif info.dirty == 1 then
      vim.v.swapchoice = "r"
      vim.schedule(function()
        pcall(vim.fn.delete, sw) -- 復元に使った古いスワップは用済み (残すと次回も復元の対象になる)
        vim.notify(
          "「" .. name .. "」の、保存していなかった前回の編集を復元しました。\n"
            .. "このまま保存する: Ctrl-s ／ 破棄して保存済みの内容に戻す: :e!",
          vim.log.levels.WARN
        )
      end)
    else
      vim.v.swapchoice = "d"
    end
  end,
})

-- 7日以上たった、持ち主のいない古いスワップを、起動時に消す
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.defer_fn(function()
      local dir = vim.fn.stdpath("state") .. "/swap"
      local limit = os.time() - 7 * 24 * 3600
      for name, kind in vim.fs.dir(dir) do
        if kind == "file" then
          local path = dir .. "/" .. name
          local st = vim.uv.fs_stat(path)
          if st and st.mtime.sec < limit then
            local info = vim.fn.swapinfo(path)
            if not swap_owner_alive(info) then pcall(vim.fn.delete, path) end
          end
        end
      end
    end, 3000)
  end,
})

-- ファイルを開いた直後に、入力モードにするか (VSCode 風)。
--   Vim を覚えるため、今は false (Vim と同じく通常モードで開く。入力は i で始める)。
--   true にすると、ファイルツリー・接続先ツリー・検索から開いたときに入力モードになる
vim.g.open_in_edit = false
function _G.UserEnterEdit()
  if not vim.g.open_in_edit then return end
  local b = vim.api.nvim_get_current_buf()
  if vim.bo[b].buftype == "" and vim.bo[b].modifiable and not vim.bo[b].readonly
    and vim.api.nvim_buf_get_name(b) ~= "" and not vim.api.nvim_get_mode().mode:match("^[iR]") then
    vim.cmd("startinsert")
  end
end

-- ファイルをクリックしたら、入力モードにするか (VSCode 風)。
--   Vim を覚えるため、今は false (Vim と同じく、クリックはカーソルを動かすだけ)。
--   true にすると、ファイルをクリックしたらすぐ入力できるようになる
vim.g.click_to_insert = false
-- ※全体 (グローバル) に割り当てると nvim のダブルクリック判定が乱れるので、
--   普通のファイルのバッファにだけ割り当てる
vim.api.nvim_create_autocmd("BufWinEnter", {
  callback = function(ev)
    -- ツリー・一覧 (buftype=nofile) などには割り当てない (それぞれ独自のクリック処理があるため)
    if vim.b[ev.buf].click_insert_mapped or vim.bo[ev.buf].buftype ~= "" then return end
    vim.b[ev.buf].click_insert_mapped = true
    vim.keymap.set("n", "<LeftRelease>", function()
      local b = vim.api.nvim_get_current_buf()
      if vim.g.click_to_insert and vim.bo[b].buftype == "" and vim.bo[b].modifiable and not vim.bo[b].readonly
        and vim.api.nvim_get_mode().mode == "n" then
        vim.cmd("startinsert")
      end
    end, { buffer = ev.buf, desc = "クリックしたら入力状態に" })
  end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() vim.hl.on_yank() end,
})

-- ===== ターミナル / SSH / Claude Code =====
-- 実装は lua/user/terminal.lua (下のパネル) と lua/user/remote.lua (接続先ツリー)
local term = require("user.terminal")
local remote = require("user.remote")
term.setup()
remote.setup()

map("n", "<leader>q", term.close_current, { desc = "今のファイルを閉じる" })
map({ "n", "t" }, "<F4>", term.toggle, { desc = "ターミナル 開閉" })
map("n", "<leader>tt", term.shell, { desc = "この PC のターミナル" })
map("n", "<leader>tl", term.pick, { desc = "ターミナル一覧から選ぶ" })
-- 追加/分割は「今のターミナルと同じ種類」(SSH 中なら同じホストへ SSH)
map("n", "<leader>tn", function() term.new_like(false) end, { desc = "ターミナルを追加" })
map("n", "<leader>tv", function() term.new_like(true) end, { desc = "ターミナルを左右に分割して追加" })
map("t", "<M-n>", function() term.new_like(false) end, { desc = "ターミナルを追加" })
map("t", "<M-v>", function() term.new_like(true) end, { desc = "ターミナルを分割して追加" })
map("t", "<M-x>", function() term.kill(vim.api.nvim_get_current_buf()) end, { desc = "このターミナルを終了" })
map("n", "<leader>ts", function() remote.pick_and_connect() end, { desc = "SSH 接続 (ホストを選ぶ)" })
map("n", "<leader>tr", function() remote.pick_and_connect(nil, { claude = true }) end, { desc = "SSH 先で Claude Code" })
map("n", "<leader>tc", "<cmd>Claude<CR>", { desc = "Claude Code (この PC)" })
map("n", "<leader>e", remote.toggle_tree, { desc = "ファイルツリー 開閉 (接続中は接続先)" })
map("n", "<leader>E", function()
  remote.hide()
  vim.cmd("Neotree show")
end, { desc = "この PC のファイルツリー" })

-- :SSH [ホスト]  (省略すると一覧から選ぶ / Tab で補完 / 小文字 :ssh も可)
vim.api.nvim_create_user_command("SSH", function(a) remote.pick_and_connect(a.fargs) end,
  { nargs = "*", complete = remote.complete })
-- :SSHClaude [ホスト]  接続先で Claude Code を起動
vim.api.nvim_create_user_command("SSHClaude", function(a) remote.pick_and_connect(a.fargs, { claude = true }) end,
  { nargs = "*", complete = remote.complete })
vim.cmd([[cnoreabbrev <expr> ssh (getcmdtype() == ':' && getcmdline() ==# 'ssh') ? 'SSH' : 'ssh']])
-- :Term コマンド  (PowerShell で実行。終了しても結果は残る)
vim.api.nvim_create_user_command("Term", function(a)
  term.run(a.args, { vars = { term_label = a.args } })
end, { nargs = "+" })
-- :Claude [引数]  この PC で Claude Code
vim.api.nvim_create_user_command("Claude", function(a)
  term.run(vim.list_extend({ "claude" }, a.fargs),
    { esc = false, vars = { term_label = "Claude Code (この PC)", is_claude = true, autoclose = true } })
end, { nargs = "*" })

-- 引数なしで起動したら、ファイルツリーを開く
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    if vim.fn.argc() == 0 then vim.cmd("Neotree show") end
  end,
})

-- ===== チートシート (<Space>k / :Cheatsheet) =====
local cheatsheet = {
  " モード",
  "  i / a          入力モード (カーソルの前 / 後から)",
  "  o / O          下 / 上に行を足して入力",
  "  Esc            通常モードに戻る",
  "  v / V / Ctrl-v 選択 (文字 / 行 / 矩形)",
  "  :              コマンド (:w 保存  :q 閉じる)",
  "",
  " 移動",
  "  h j k l        左 下 上 右",
  "  w / b / e      次の単語 / 前の単語 / 単語の末尾",
  "  0 / ^ / $      行頭 / 最初の文字 / 行末",
  "  gg / G         先頭 / 末尾 (25G で 25 行目)",
  "  Ctrl-d / Ctrl-u 半画面 下 / 上",
  "  %              対応するカッコへ",
  "  f{文字}        行内のその文字へ (; で次)",
  "  Ctrl-o / Ctrl-i 移動の履歴を戻る / 進む",
  "",
  " 編集",
  "  x              1 文字削除",
  "  dd / yy / p    行の削除 / コピー / 貼り付け",
  "  dw / cw        単語を削除 / 書き換え",
  "  ciw / ci\"      単語 / \"\" の中を書き換え",
  "  u / Ctrl-r     元に戻す / やり直す",
  "  .              直前の変更をくり返す",
  "  > / <          インデント (選択中。くり返しは .)",
  "  gcc / gc       コメント (行 / 選択中)",
  "  (y と p は OS のクリップボードと共有)",
  "",
  " 検索・置換",
  "  /文字 Enter    検索 (n で次 / N で前)",
  "  *              カーソルの単語を検索",
  "  :%s/前/後/g    ファイル全体を置換",
  "",
  " ファイル・画面",
  "  :w / :q / :wq / :q!  保存 / 閉じる / 両方 / 破棄",
  "  :e ファイル名  開く",
  "  [b / ]b        前 / 次のファイル (上のタブ)",
  "  Ctrl-w h/j/k/l 左 / 下 / 上 / 右の画面へ",
  "  Ctrl-w s / v / q 横に分割 / 縦に分割 / 閉じる",
  "",
  " 補完・コード (LSP)",
  "  Ctrl-n / Ctrl-p 候補を選ぶ (入力中)",
  "  Ctrl-y / Ctrl-e 確定 / やめる",
  "  gd / K         定義へ / 説明を表示",
  "  grr / grn / gra 参照一覧 / 名前変更 / 修正候補",
  "  ]d / [d        次 / 前のエラーへ",
  "  Ctrl-w d       エラーの詳細",
  "",
  " この設定で追加したキー (Vim では空いているキー)",
  "  Space e        ファイルツリーへ / 閉じる",
  "  Space ff / fg  ファイル名で探す / 文字列で探す",
  "  Space fb / fr  開いているファイル / 最近のファイル",
  "  Space w / q    保存 / 今のファイルを閉じる",
  "  Space cf       整形",
  "  Space xx       このファイルのエラー一覧",
  "  F4             ターミナルへ / 隠す",
  "  Space tt / tc  この PC のターミナル / Claude Code",
  "  Space ts / tr  SSH 接続 / 接続先で Claude Code",
  "  Alt-h/j/k/l    隣の画面へ (ターミナルの中からも)",
  "",
  " ターミナルの中",
  "  Ctrl-\\ Ctrl-n  通常モードへ (シェルでは Esc Esc も可)",
  "  i              入力に戻る",
  "",
  " 困ったら: Esc を押す / :help 調べたいこと / :Tutor (練習)",
  " Space を押して待つと、次に押せるキーが出ます",
  " (この画面は q か Esc で閉じる / Space k でまた開く)",
}

local function show_cheatsheet()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, cheatsheet)
  vim.bo[buf].modifiable = false
  local w = 0
  for _, l in ipairs(cheatsheet) do w = math.max(w, vim.fn.strdisplaywidth(l)) end
  w = math.min(w + 2, vim.o.columns - 4)
  local h = math.min(#cheatsheet, vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
    style = "minimal", border = "rounded", title = " キー操作一覧 ", title_pos = "center",
  })
  for _, k in ipairs({ "q", "<Esc>" }) do
    map("n", k, function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  end
end

vim.api.nvim_create_user_command("Cheatsheet", show_cheatsheet, {})
map("n", "<leader>k", show_cheatsheet, { desc = "キー操作の一覧" })
-- F1 は Vim と同じくヘルプ (:help) のまま

-- ===== lazy.nvim ブートストラップ =====
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ===== プラグイン =====
require("lazy").setup({
  -- カラースキーム (<leader>fc で切り替え。選んだテーマは次回起動時も復元)
  {
    "catppuccin/nvim", name = "catppuccin", priority = 1000,
    config = function()
      local f = vim.fn.stdpath("data") .. "/colorscheme.txt"
      local ok, lines = pcall(vim.fn.readfile, f)
      local name = ok and lines[1] or "catppuccin"
      if not pcall(vim.cmd.colorscheme, name) then vim.cmd.colorscheme("catppuccin") end
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function(a) pcall(vim.fn.writefile, { a.match }, f) end,
      })
    end,
  },
  { "folke/tokyonight.nvim", lazy = true },
  { "rebelot/kanagawa.nvim", lazy = true },
  { "rose-pine/neovim", name = "rose-pine", lazy = true },
  { "ellisonleao/gruvbox.nvim", lazy = true },
  { "navarasu/onedark.nvim", lazy = true },
  { "EdenEast/nightfox.nvim", lazy = true },
  { "sainnhe/everforest", lazy = true },
  { "Mofiqul/dracula.nvim", lazy = true },

  -- アイコン (Nerd Font 必須。no-icons のときは読み込まない)
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- バッファをタブ表示
  {
    "akinsho/bufferline.nvim", event = "VeryLazy",
    opts = {
      options = vim.tbl_extend("force", { diagnostics = "nvim_lsp" }, icons and {} or {
        show_buffer_icons = false,
        buffer_close_icon = "x",
        close_icon = "x",
        modified_icon = "+",
        left_trunc_marker = "<",
        right_trunc_marker = ">",
        indicator = { style = "underline" },
      }),
    },
    -- タブ (バッファ) の切り替えは nvim 標準の [b / ]b (:bprevious / :bnext)。
    -- H / L は Vim 本来の動き (画面の上端 / 下端へ) のまま
  },

  -- コマンドライン/通知の UI 改善
  {
    "folke/noice.nvim", event = "VeryLazy",
    dependencies = {
      "MunifTanjim/nui.nvim",
      -- 通知の時刻を 24 時間表記 (例 18:43:31) に固定
      { "rcarriga/nvim-notify", opts = {
        time_formats = { notification = "%H:%M:%S", notification_history = "%H:%M:%S" },
        icons = (not icons) and { ERROR = "E", WARN = "W", INFO = "I", DEBUG = "D", TRACE = "T" } or nil,
      } },
    },
    opts = icons and {} or {
      cmdline = {
        format = {
          cmdline = { icon = ">" },
          search_down = { icon = "/" },
          search_up = { icon = "?" },
          filter = { icon = "$" },
          lua = { icon = "lua" },
          help = { icon = "?" },
        },
      },
    },
  },


  -- キーマップのヒント表示
  {
    "folke/which-key.nvim", event = "VeryLazy",
    opts = {
      delay = 150, -- <Space> を押して0.15秒でメニュー表示
      -- no-icons のときは、キー名もアイコンではなく文字で表示 (which-key 公式の例)
      icons = icons and {} or {
        mappings = false, breadcrumb = ">>", separator = "->", group = "+",
        keys = {
          Up = "<Up> ", Down = "<Down> ", Left = "<Left> ", Right = "<Right> ",
          C = "<C-…> ", M = "<M-…> ", D = "<D-…> ", S = "<S-…> ",
          CR = "<CR> ", Esc = "<Esc> ", ScrollWheelDown = "<ScrollWheelDown> ",
          ScrollWheelUp = "<ScrollWheelUp> ", NL = "<NL> ", BS = "<BS> ",
          Space = "<Space> ", Tab = "<Tab> ",
          F1 = "<F1>", F2 = "<F2>", F3 = "<F3>", F4 = "<F4>", F5 = "<F5>", F6 = "<F6>",
          F7 = "<F7>", F8 = "<F8>", F9 = "<F9>", F10 = "<F10>", F11 = "<F11>", F12 = "<F12>",
        },
      },
      -- ツリー/ターミナル一覧では自動表示しない (キー入力の邪魔になるため)
      disable = { ft = { "remote-tree", "term-list", "neo-tree" }, bt = { "terminal" } },
      spec = {
        { "<leader>f", group = "検索 (find)" },
        { "<leader>t", group = "ターミナル / SSH / Claude" },
        { "<leader>c", group = "コード" },
        { "<leader>x", group = "エラー一覧" },
      },
    },
    keys = { { "<leader>?", function() require("which-key").show({ global = false }) end, desc = "このバッファのキー一覧" } },
  },


  -- ステータスライン
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy", -- 画面が出た直後に読み込む (起動を待たせない)
    opts = {
      options = icons and { theme = "auto", globalstatus = true }
        or { theme = "auto", globalstatus = true, icons_enabled = false,
             section_separators = "", component_separators = "|" },
      sections = {
        lualine_b = {
          { function()
            -- 接続先にいるときは「ホスト:パス」、この PC では作業ディレクトリ
            local rs = require("user.remote").state
            local srv, pc, dir = "\u{f233} ", "\u{f108} ", "\u{f07c} "
            if not icons then srv, pc, dir = "SSH ", "", "" end
            if vim.b.remote_file then return srv .. vim.b.remote_file.host .. " (接続先)" end
            if vim.b.remote_host then
              return srv .. vim.b.remote_host .. ":" .. (vim.b.remote_cwd or "~")
            end
            if vim.bo.filetype == "remote-tree" then
              return srv .. (rs.host or "") .. ":" .. (rs.cwd or "")
            end
            if vim.bo.buftype == "terminal" then return pc .. "この PC" end
            return dir .. vim.fn.getcwd()
          end },
          "branch", "diff", "diagnostics",
        },
        lualine_c = { { function()
          -- 接続先のファイルは手元のキャッシュではなく、接続先のパスを表示
          local mod = vim.bo.modified and " [+]" or ""
          if vim.b.remote_file then return vim.b.remote_file.path .. mod end
          if vim.bo.buftype == "terminal" then return vim.b.term_label or "ターミナル" end
          if vim.bo.filetype == "remote-tree" then return "接続先のファイル (? で操作一覧)" end
          if vim.bo.filetype == "term-list" then return "ターミナル一覧" end
          local name = vim.fn.expand("%:~:.")
          return (name == "" and "[無題]" or name) .. mod .. (vim.bo.readonly and " [読取専用]" or "")
        end } },
        lualine_x = { "encoding", "fileformat", "filetype" }, -- 文字コードを常時表示
      },
    },
  },

  -- サイドバーのファイルツリー (<Space>e で開閉)
  {
    "nvim-neo-tree/neo-tree.nvim", branch = "v3.x", lazy = false,
    dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons", "MunifTanjim/nui.nvim" },
    opts = {
      close_if_last_window = true, -- ツリーだけが残ったら終了 (ツリーが全画面に広がるのを防ぐ)
      -- no-icons のときは、フォルダや git の印を普通の文字で表示
      default_component_configs = icons and {} or {
        icon = { folder_closed = "+", folder_open = "-", folder_empty = "-", default = " " },
        indent = { expander_collapsed = ">", expander_expanded = "v" },
        modified = { symbol = "[+]" },
        git_status = {
          symbols = {
            added = "A", modified = "M", deleted = "D", renamed = "R",
            untracked = "?", ignored = "i", unstaged = "U", staged = "S", conflict = "!",
          },
        },
        diagnostics = { symbols = { error = "E", warn = "W", info = "I", hint = "H" } },
      },
      -- ツリーからファイルを開いたら、編集できる状態 (入力モード) にする
      event_handlers = {
        { event = "file_opened", handler = function() vim.schedule(_G.UserEnterEdit) end },
      },
      filesystem = {
        follow_current_file = { enabled = true },
        filtered_items = { visible = true },
        bind_to_cwd = true, -- 上へ移動 / ルート変更で cwd も追従
        -- ターミナルや Claude Code など、nvim の外でファイルが増減しても自動でツリーに反映
        use_libuv_file_watcher = true,
        -- ツリー最上部を "~" ではなくフルパスで表示
        components = {
          name = function(config, node, state)
            local r = require("neo-tree.sources.common.components").name(config, node, state)
            if node:get_depth() == 1 then
              r.text = (node.path or r.text):gsub("[\\/]$", "")
            end
            return r
          end,
        },
      },
      window = {
        mappings = {
          ["<BS>"] = "navigate_up", -- 上の階層へ
          ["u"] = "navigate_up",    -- 上の階層へ
          ["."] = "set_root",       -- 選択中のフォルダを新しいルートに
        },
      },
    },
  },

  -- ファイラ (バッファのように編集できる)
  {
    -- :Oil でフォルダをバッファとして開く (- は Vim 本来の「前の行の先頭へ」のまま)
    "stevearc/oil.nvim", cmd = "Oil", opts = {},
  },

  -- ファジーファインダー (live_grep には ripgrep が必要)
  {
    "nvim-telescope/telescope.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope-ui-select.nvim" },
    config = function()
      local t = require("telescope")
      -- 選択画面 (SSH ホスト選択など) も telescope の見やすい一覧にする
      -- ファイルを選んで開いたら、編集できる状態 (入力モード) にする
      local actions = require("telescope.actions")
      local function edit_after_open(_, _)
        actions.select_default:enhance({ post = function() vim.schedule(_G.UserEnterEdit) end })
        return true
      end
      t.setup({
        pickers = {
          find_files = { attach_mappings = edit_after_open },
          live_grep = { attach_mappings = edit_after_open },
          buffers = { attach_mappings = edit_after_open },
          oldfiles = { attach_mappings = edit_after_open },
        },
        extensions = { ["ui-select"] = { require("telescope.themes").get_dropdown({}) } },
      })
      t.load_extension("ui-select")
    end,
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "ファイル検索" },
      { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "grep" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "バッファ" },
      { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "ヘルプ" },
      { "<leader>fc", "<cmd>Telescope colorscheme enable_preview=true<CR>", desc = "テーマ切り替え" },
      { "<leader>fr", "<cmd>Telescope oldfiles<CR>", desc = "最近のファイル" },
    },
  },

  -- Git
  { "lewis6991/gitsigns.nvim", event = { "BufReadPre", "BufNewFile" }, opts = {} },

  -- 編集補助
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },
  -- コメントの gcc / gc は nvim 標準の機能を使う (プラグイン不要)
  { "kylechui/nvim-surround", event = "VeryLazy", opts = {} },
  { "lukas-reineke/indent-blankline.nvim", main = "ibl", event = { "BufReadPost", "BufNewFile" }, opts = {} },

  -- LSP (Mason でサーバーを自動導入)
  --   起動を速くするため、ファイルを開いたとき (または :Mason を使ったとき) に読み込む
  {
    "williamboman/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUninstall", "MasonUpdate", "MasonLog" },
    opts = {},
  },
  {
    "williamboman/mason-lspconfig.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      -- offline のときは自動導入しない (入れたいものは :Mason から手動で)
      ensure_installed = offline and {} or {
        "lua_ls",
        "clangd",                      -- C / C++
        "ts_ls", "eslint",             -- JS / TS / React
        "astro",
        "html", "cssls", "tailwindcss", "jsonls",
        "pyright", "ruff",             -- Python
        "gopls",                       -- Go
        "rust_analyzer",               -- Rust
        "emmet_language_server",       -- HTML / CSS の展開
        "bashls", "yamlls", "taplo",   -- shell / YAML / TOML
        "marksman", "dockerls",        -- Markdown / Dockerfile
      },
    },
  },
  -- フォーマッタ / ツールの自動導入
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    -- 足りないツールの確認は、起動して少したってから、7日に1回だけ行う (下の「ツールの自動導入」)
    -- offline のときは読み込まない。手動での確認は :MasonToolsInstall
    lazy = true,
    cmd = { "MasonToolsInstall", "MasonToolsUpdate" },
    enabled = not offline,
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = { "prettier", "stylua", "tree-sitter-cli", "goimports", "gofumpt", "shfmt" },
      run_on_start = true,
      start_delay = 3000,
    },
  },

  -- フォーマット (保存時に自動整形 / 手動は <leader>cf)
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    keys = {
      { "<leader>cf", function() require("conform").format({ lsp_format = "fallback" }) end, desc = "整形" },
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        -- c / cpp は clangd (LSP) の整形にフォールバック
        python = { "ruff_format", "ruff_organize_imports" },
        javascript = { "prettier" },
        javascriptreact = { "prettier" },
        typescript = { "prettier" },
        typescriptreact = { "prettier" },
        astro = { "prettier" },
        html = { "prettier" },
        css = { "prettier" },
        scss = { "prettier" },
        json = { "prettier" },
        jsonc = { "prettier" },
        yaml = { "prettier" },
        go = { "goimports", "gofumpt" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        -- rust / toml は LSP (rust_analyzer / taplo) にフォールバック
        markdown = { "prettier" },
      },
      -- 構文エラーがあるときは整形しない (; 抜けなどで、次の行とつながって崩れるのを防ぐ)
      -- 判定は treesitter (今の文字そのものを即座に解析) と LSP のエラーの両方で行う
      format_on_save = function(bufnr)
        local broken = #vim.diagnostic.get(bufnr, { severity = vim.diagnostic.severity.ERROR }) > 0
        local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
        if ok and parser then
          local tree = parser:parse()[1]
          broken = broken or (tree and tree:root():has_error())
        end
        if broken then
          vim.notify("構文エラーがあるため、自動整形はしませんでした (保存はしています)", vim.log.levels.WARN)
          return nil
        end
        return { timeout_ms = 1000, lsp_format = "fallback" }
      end,
    },
  },

  -- シンタックスハイライト
  --   パーサーの自動導入には C コンパイラ (gcc/clang) と tree-sitter コマンドが必要。
  --   どちらかが無い、または offline のときは導入を飛ばす (導入済みのパーサーでの色付けは行う)
  {
    "nvim-treesitter/nvim-treesitter", branch = "main", lazy = false, build = ":TSUpdate",
    config = function()
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev) pcall(vim.treesitter.start, ev.buf) end,
      })
      local has_cc = vim.fn.executable("gcc") == 1 or vim.fn.executable("clang") == 1
      local mason_ts = vim.fn.stdpath("data") .. "/mason/bin/tree-sitter" .. (vim.fn.has("win32") == 1 and ".cmd" or "")
      local has_ts = vim.fn.executable("tree-sitter") == 1 or vim.uv.fs_stat(mason_ts) ~= nil
      if offline or not has_cc or not has_ts then return end
      -- 足りないパーサーだけを、起動が落ち着いてから入れる (毎回すべてを確認しない)
      vim.defer_fn(function()
        local ok, ts = pcall(require, "nvim-treesitter")
        if not ok then return end
        local want = {
          "c", "cpp", "javascript", "typescript", "tsx", "astro", "html", "css",
          "json", "python", "lua", "markdown", "markdown_inline",
          "go", "gomod", "gosum", "rust", "bash", "yaml", "toml", "dockerfile",
          "scss", "vim", "vimdoc", "query", "regex", "diff", "gitcommit",
        }
        local have = {}
        for _, lang in ipairs(ts.get_installed and ts.get_installed() or {}) do have[lang] = true end
        local missing = vim.tbl_filter(function(lang) return not have[lang] end, want)
        if #missing > 0 then ts.install(missing) end
      end, 2000)
    end,
  },

  -- 補完
  {
    -- ※遅延読み込みはしない (入力を始めたときに読み込むと、最初に打った文字で候補が出ない。
    --   blink.cmp は自分で必要なときだけ動くので、公式も遅延読み込みは不要としている)
    "saghen/blink.cmp", version = "1.*",
    opts = {
      -- Vim 本来の補完と同じキー: Ctrl-n / Ctrl-p で選ぶ、Ctrl-y で確定、Ctrl-e でやめる
      -- (Tab と Enter は普通の文字入力のまま)
      keymap = { preset = "default" },
      -- 選んでいる候補の残りをカーソルの後ろに薄く表示 (例: #include <stdi → o.h> が薄く出る)
      -- no-icons のときは、候補一覧の種類アイコンの代わりに種類名 (Function など) を出す
      completion = vim.tbl_extend("force", { ghost_text = { enabled = true } }, icons and {} or {
        menu = { draw = { columns = { { "label", "label_description", gap = 1 }, { "kind" } } } },
      }),
      -- 候補の絞り込みは Rust 版 (完成品を自動ダウンロード。ビルド不要)。取得できない環境では Lua 版で動く
      -- ※Lua 版は、候補が出た後に "o.h" のように素早く打つと絞り込みが追いつかず、
      --   #include <stdio.h で Tab を押すと stdint.h が入ることがある
      -- offline のときはダウンロードを試みず、最初から Lua 版を使う (起動のたびの失敗・警告を防ぐ)
      fuzzy = offline and { implementation = "lua", prebuilt_binaries = { download = false } }
        or { implementation = "prefer_rust" },
      sources = { default = { "lsp", "path", "buffer" } },
    },
  },
}, {
  checker = { enabled = false },
  -- luarocks は使わない (有効だと hererocks の取得を試みて、プロキシ環境で失敗・停止する)
  rocks = { enabled = false },
  -- nvim 付属の、使っていない機能は読み込まない (起動を速くする)
  --   netrw はファイルツリー (neo-tree / oil) で置き換え済み。gzip / tar / zip は圧縮ファイルの中身を見る機能
  performance = {
    rtp = { disabled_plugins = { "gzip", "netrwPlugin", "tarPlugin", "tohtml", "zipPlugin" } },
  },
  -- no-icons のときは、:Lazy の画面のアイコンを絵文字にする (lazy.nvim 公式の例)
  ui = { icons = icons and {} or {
    cmd = "⌘", config = "🛠", event = "📅", ft = "📂", init = "⚙", keys = "🗝", plugin = "🔌",
    runtime = "💻", require = "🌙", source = "📄", start = "🚀", task = "📌", lazy = "💤 ",
  } },
})

-- ===== ツールの自動導入 (整形ツールなど) =====
-- 起動直後は重くなるので、起動から 8 秒後に、前回の確認から 7 日以上たっているときだけ確認する
if not offline then
  vim.defer_fn(function()
    local stamp = vim.fn.stdpath("state") .. "/mason-tools-checked"
    local st = vim.uv.fs_stat(stamp)
    if st and os.time() - st.mtime.sec < 7 * 24 * 3600 then return end
    local f = io.open(stamp, "w")
    if f then f:close() end
    pcall(require("lazy").load, { plugins = { "mason-tool-installer.nvim" } })
  end, 8000)
end

-- ===== :Offline / :NoIcons (スイッチの切り替え。次回起動から反映) =====
local function toggle_flag(name, label)
  local path = vim.fn.stdpath("config") .. "/" .. name
  if vim.uv.fs_stat(path) then
    os.remove(path)
    vim.notify(label .. " を オフ にしました。nvim を再起動すると反映されます")
  else
    local f = io.open(path, "w")
    if f then f:close() end
    vim.notify(label .. " を オン にしました。nvim を再起動すると反映されます")
  end
end
vim.api.nvim_create_user_command("Offline", function() toggle_flag("offline", "オフラインモード (自動ダウンロードしない)") end, {})
vim.api.nvim_create_user_command("NoIcons", function() toggle_flag("no-icons", "アイコン無しモード") end, {})

-- ===== C / C++ (clangd) =====
-- Windows で MSYS2 / WinLibs の gcc を使う場合、clangd は既定で Visual Studio (MSVC) 用として
-- 解析してしまい、stdio.h が見つからずに #include や printf が誤ってエラーになる。
-- gcc (MinGW) 用として解析させる。プロジェクトに compile_commands.json /
-- compile_flags.txt がある場合はそちらが優先される
if vim.fn.has("win32") == 1 and vim.fn.executable("gcc") == 1 then
  vim.lsp.config("clangd", {
    init_options = { fallbackFlags = { "--target=x86_64-w64-mingw32" } },
  })
end
-- Mason 以外で入れた clangd (学校の PC で、ホームに置いて PATH を通した場合など) も使う。
-- Mason で入れたものと同じ設定が使われるので、二重には起動しない
if vim.fn.executable("clangd") == 1 then vim.lsp.enable("clangd") end
-- clangd が無い環境では、gcc でエラーを調べて表示する (lua/user/c_check.lua)
require("user.c_check").setup()

-- ===== エラー / 警告の表示 =====
-- 行の右側にエラー内容を表示し、左端に E/W などの印を出す
-- 文章は日本語に置き換える (lua/user/diag_ja.lua の対応表。表にないものは英語のまま)
local diag_ja = require("user.diag_ja")
vim.diagnostic.config({
  virtual_text = {
    -- 同じ行に複数あるときは ● を並べず「● 5件:」のように件数を出す
    -- (文章が出るのは、そのうち一番重要な1件だけ。全部見るには Ctrl-w d)
    prefix = function(_, i, total)
      if total <= 1 then return "●" end
      return i == total and ("● " .. total .. "件:") or ""
    end,
    spacing = 2,
    format = function(d) return diag_ja.text(d.message) end,
  },
  severity_sort = true, -- 同じ行に複数あるときはエラーを優先して表示
  -- 入力中もエラーを表示し、打つたびに更新する (nvim の標準では、入力中は隠して Esc の後に出す)
  update_in_insert = true,
  -- Ctrl-w d の詳細表示: 日本語と、元の英語の両方を出す (どのツールの指摘かも出す)
  float = {
    border = "rounded",
    source = true,
    format = function(d)
      local ja = diag_ja.translate(d.message)
      return ja and (ja .. "\n  (" .. d.message .. ")") or d.message
    end,
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "E",
      [vim.diagnostic.severity.WARN] = "W",
      [vim.diagnostic.severity.INFO] = "I",
      [vim.diagnostic.severity.HINT] = "H",
    },
  },
})
map("n", "<leader>xx", function()
  local items = vim.diagnostic.toqflist(vim.diagnostic.get(0))
  for _, it in ipairs(items) do it.text = diag_ja.text(it.text) end
  vim.fn.setloclist(0, {}, " ", { title = "エラー一覧", items = items })
  vim.cmd("lopen")
end, { desc = "このファイルのエラー一覧" })

-- ツール自身が日本語のメッセージを持っているものは、日本語版で起動する
--   (Pyright は PC の言語設定から自動で日本語になる)
vim.lsp.config("ts_ls", { init_options = { locale = "ja" } })
vim.lsp.config("lua_ls", { cmd = { "lua-language-server", "--locale=ja-jp" } })

-- ===== LSP キーマップ =====
-- nvim 標準のキーをそのまま使う (設定不要で最初から使える):
--   K 説明 / grr 参照一覧 / grn 名前変更 / gra 修正候補 / gri 実装へ / gO 記号の一覧
--   ]d [d 次/前のエラー / Ctrl-w d エラーの詳細 / 入力中 Ctrl-s 引数の説明
-- 追加するのは gd (定義へ) だけ。Vim 本来の gd (関数内の宣言へ) を、LSP の正確な定義ジャンプに置き換える
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    map("n", "gd", vim.lsp.buf.definition, { buffer = ev.buf, desc = "定義へ" })
  end,
})
