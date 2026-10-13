-- ===== 基本設定 =====
vim.g.mapleader = " "
vim.g.maplocalleader = " "

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
o.relativenumber = true
o.cursorline = true
o.signcolumn = "yes"
o.termguicolors = true
o.mouse = "a"
o.clipboard = "unnamedplus"
o.ignorecase = true
o.smartcase = true
o.undofile = true
o.updatetime = 250
o.scrolloff = 8
o.splitright = true
o.splitbelow = true
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.wrap = false


local map = vim.keymap.set
map("n", "<Esc>", "<cmd>nohlsearch<CR>")
-- ウィンドウ移動: 通常は Ctrl-hjkl、どこでも (ターミナル内でも) Alt-hjkl
-- ※ターミナル内の Ctrl-h/j/k/l は bash 等が使う (Ctrl-k 行削除 / Ctrl-l 画面クリア) ので奪わない
for _, k in ipairs({ "h", "j", "k", "l" }) do
  map("n", "<C-" .. k .. ">", "<C-w>" .. k)
  map({ "n", "i" }, "<M-" .. k .. ">", "<Cmd>wincmd " .. k .. "<CR>")
  -- 文字を選択中 (VISUAL) でも移動できる。選択は解除して移動する
  map({ "x", "s" }, "<M-" .. k .. ">", "<Esc><Cmd>wincmd " .. k .. "<CR>")
  map("t", "<M-" .. k .. ">", [[<C-\><C-n><C-w>]] .. k)
end
map("n", "<leader>w", "<cmd>w<CR>", { desc = "保存" })
-- VSCode と同じ Ctrl-s でも保存 (入力中・選択中でも可)
map({ "n", "i", "x" }, "<C-s>", "<Cmd>w<CR><Esc>", { desc = "保存" })

-- VSCode と同じ Ctrl-z で元に戻す / Ctrl-y でやり直し (入力中でも可)
--   * nvim 本来の Ctrl-z は「nvim を一時停止する」キー。Windows では何も起きない
--   * Ctrl-y (本来は画面を1行スクロール) は潰れるが、スクロールは Ctrl-e / ホイールで足りる
--   * ターミナルの中では割り当てない (シェルに Ctrl-z / Ctrl-y がそのまま届く)
map({ "n", "x" }, "<C-z>", "u", { desc = "元に戻す" })
map("i", "<C-z>", "<Cmd>undo<CR>", { desc = "元に戻す" })
map({ "n", "x" }, "<C-y>", "<C-r>", { desc = "やり直し" })
map("i", "<C-y>", "<Cmd>redo<CR>", { desc = "やり直し" })
-- 入力中の元に戻すが、細かく刻まれるようにする (そのままだと、入力を始めてから Esc までが
-- 1回分になり、Ctrl-z で書いたものが全部消える)。スペースと改行で区切る
map("i", "<Space>", "<C-g>u<Space>")
map("i", "<CR>", "<C-g>u<CR>")
map("n", "<leader>..", function()
  vim.cmd("cd ..")
  vim.cmd("Neotree dir=" .. vim.fn.fnameescape(vim.fn.getcwd()))
end, { desc = "作業ディレクトリを1つ上へ" })
map("v", "<", "<gv")
map("v", ">", ">gv")

-- ファイルをクリックしたら、すぐ入力できる状態にする (VSCode と同じ感覚)
--   * クリックだけだと操作モードのままで、文字を打つと Vim のコマンドになってしまうため
--   * ドラッグでの範囲選択は今までどおり (選択中に離したときは何もしない)
--   * ツリー・ターミナル・読み取り専用のファイルには効かない
--   * やめたいときは、下の true を false にする
vim.g.click_to_insert = true
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
  " 基本操作                              ",
  "  i           文字を入力する (Esc で戻る)",
  "  Ctrl-s / <Space>w  保存                ",
  "  Tab         補完を確定 (薄い文字を確定)",
  "  <Space>q    今のファイルを閉じる       ",
  "  :qa         nvim を終了                ",
  "  Alt-h/j/k/l 左/下/上/右の画面へ移動    ",
  "  Ctrl-z / Ctrl-y  元に戻す / やり直す   ",
  "  (操作モードでは u / Ctrl-r も可)       ",
  "  dd / yy / p 行を 削除 / コピー / 貼付  ",
  "  /文字 Enter 検索 (n で次、Esc で解除)  ",
  "",
  " ファイル・検索                         ",
  "  <Space>e    ファイルツリー 開閉        ",
  "              (SSH 接続中は接続先のツリー)",
  "  <Space>E    この PC のツリー           ",
  "  (ツリー内) BS か u で上の階層へ        ",
  "  (ツリー内) . で選んだフォルダをルートに",
  "  <Space>..   作業ディレクトリを1つ上へ  ",
  "  <Space>ff   ファイル名で探す           ",
  "  <Space>fg   文字列で探す (grep)        ",
  "  <Space>fb   開いているファイル一覧     ",
  "  <Space>fc   テーマ切り替え             ",
  "  -           フォルダをバッファで開く   ",
  "  Shift-l/h   次/前のタブ                ",
  "",
  " コード (LSP)                           ",
  "  gd / gr     定義へ / 参照一覧          ",
  "  K           説明を表示                 ",
  "  <Space>rn   名前変更                   ",
  "  <Space>ca   修正候補                   ",
  "  <Space>cf   整形 (保存時にも自動)      ",
  "  <Space>d    この行のエラーを詳しく表示 ",
  "  ]d / [d     次 / 前のエラーへ移動      ",
  "  <Space>xx   このファイルのエラー一覧   ",
  "  gcc         行コメント切り替え         ",
  "",
  " ターミナル                             ",
  "  F4          下のパネル 開閉 (中身は継続)",
  "  <Space>tt   この PC のターミナル       ",
  "  <Space>tn   ターミナルを追加 (Alt-n)   ",
  "  <Space>tv   左右に分割して追加 (Alt-v) ",
  "              (SSH 中なら同じホストに接続)",
  "  Alt-x       今のターミナルを終了       ",
  "  右の一覧    クリック/Enter で切替、x 終了",
  "  <Space>tl   ターミナル一覧から選ぶ     ",
  "  <Space>tc   Claude Code (この PC)      ",
  "  Esc Esc     操作モードへ (シェルのみ)  ",
  "",
  " SSH                                    ",
  "  <Space>ts   ホストを選んで接続         ",
  "  <Space>tr   接続先で Claude Code       ",
  "  exit        切断 (ツリーも元に戻る)    ",
  "  (接続先ツリー) Enter 開く / BS 上へ    ",
  "  (接続先ツリー) ? で操作一覧            ",
  "  接続先のファイルは :w で接続先に保存   ",
  "",
  " 困ったら: <Space> を押して待つ / F1 でこの画面",
  " (この画面は q か Esc で閉じる)",
}

local function show_cheatsheet()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, cheatsheet)
  vim.bo[buf].modifiable = false
  local w, h = 46, #cheatsheet
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
map("n", "<F1>", show_cheatsheet, { desc = "キー操作の一覧" })

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

  -- アイコン (Nerd Font 必須)
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- バッファをタブ表示
  {
    "akinsho/bufferline.nvim", event = "VeryLazy",
    opts = { options = { diagnostics = "nvim_lsp" } },
    keys = {
      { "<S-l>", "<cmd>BufferLineCycleNext<CR>", desc = "次のバッファ" },
      { "<S-h>", "<cmd>BufferLineCyclePrev<CR>", desc = "前のバッファ" },
    },
  },

  -- コマンドライン/通知の UI 改善
  {
    "folke/noice.nvim", event = "VeryLazy",
    dependencies = {
      "MunifTanjim/nui.nvim",
      -- 通知の時刻を 24 時間表記 (例 18:43:31) に固定
      { "rcarriga/nvim-notify", opts = { time_formats = { notification = "%H:%M:%S", notification_history = "%H:%M:%S" } } },
    },
    opts = {},
  },


  -- キーマップのヒント表示
  {
    "folke/which-key.nvim", event = "VeryLazy",
    opts = {
      delay = 150, -- <Space> を押して0.15秒でメニュー表示
      -- ツリー/ターミナル一覧では自動表示しない (キー入力の邪魔になるため)
      disable = { ft = { "remote-tree", "term-list", "neo-tree" }, bt = { "terminal" } },
      spec = {
        { "<leader>f", group = "検索 (find)" },
        { "<leader>t", group = "ターミナル / SSH / Claude" },
        { "<leader>c", group = "コード" },
        { "<leader>r", group = "リネーム" },
        { "<leader>x", group = "エラー一覧" },
      },
    },
    keys = { { "<leader>?", function() require("which-key").show({ global = false }) end, desc = "このバッファのキー一覧" } },
  },


  -- ステータスライン
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      options = { theme = "auto", globalstatus = true },
      sections = {
        lualine_b = {
          { function()
            -- 接続先にいるときは「ホスト:パス」、この PC では作業ディレクトリ
            local rs = require("user.remote").state
            if vim.b.remote_file then return "\u{f233} " .. vim.b.remote_file.host .. " (接続先)" end
            if vim.b.remote_host then
              return "\u{f233} " .. vim.b.remote_host .. ":" .. (vim.b.remote_cwd or "~")
            end
            if vim.bo.filetype == "remote-tree" then
              return "\u{f233} " .. (rs.host or "") .. ":" .. (rs.cwd or "")
            end
            if vim.bo.buftype == "terminal" then return "\u{f108} この PC" end
            return "\u{f07c} " .. vim.fn.getcwd()
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
    "stevearc/oil.nvim", opts = {},
    keys = { { "-", "<cmd>Oil<CR>", desc = "親ディレクトリを開く" } },
  },

  -- ファジーファインダー (live_grep には ripgrep が必要)
  {
    "nvim-telescope/telescope.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope-ui-select.nvim" },
    config = function()
      local t = require("telescope")
      -- 選択画面 (SSH ホスト選択など) も telescope の見やすい一覧にする
      t.setup({ extensions = { ["ui-select"] = { require("telescope.themes").get_dropdown({}) } } })
      t.load_extension("ui-select")
    end,
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "ファイル検索" },
      { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "grep" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "バッファ" },
      { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "ヘルプ" },
      { "<leader>fc", "<cmd>Telescope colorscheme enable_preview=true<CR>", desc = "テーマ切り替え" },
    },
  },

  -- Git
  { "lewis6991/gitsigns.nvim", opts = {} },

  -- 編集補助
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },
  { "numToStr/Comment.nvim", opts = {} }, -- gcc / gc
  { "kylechui/nvim-surround", event = "VeryLazy", opts = {} },
  { "lukas-reineke/indent-blankline.nvim", main = "ibl", opts = {} },

  -- LSP (Mason でサーバーを自動導入)
  {
    "williamboman/mason.nvim", opts = {},
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      ensure_installed = {
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
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = { "prettier", "stylua", "tree-sitter-cli", "goimports", "gofumpt", "shfmt" },
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

  -- シンタックスハイライト (C コンパイラ gcc/clang が無ければ自動でスキップ)
  {
    "nvim-treesitter/nvim-treesitter", branch = "main", lazy = false, build = ":TSUpdate",
    config = function()
      if vim.fn.executable("gcc") == 0 and vim.fn.executable("clang") == 0 then return end
      local ok, ts = pcall(require, "nvim-treesitter")
      if not ok then return end
      ts.install({
        "c", "cpp", "javascript", "typescript", "tsx", "astro", "html", "css",
        "json", "python", "lua", "markdown", "markdown_inline",
        "go", "gomod", "gosum", "rust", "bash", "yaml", "toml", "dockerfile",
        "scss", "vim", "vimdoc", "query", "regex", "diff", "gitcommit",
      })
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev) pcall(vim.treesitter.start, ev.buf) end,
      })
    end,
  },

  -- 補完
  {
    "saghen/blink.cmp", version = "1.*",
    opts = {
      -- VSCode と同じく Tab で補完を確定 (Tab/Shift-Tab で候補を移動、Enter は普通の改行)
      -- 候補が出ていないときの Tab は普通のインデント
      keymap = { preset = "super-tab" },
      -- 選んでいる候補の残りをカーソルの後ろに薄く表示 (例: #include <stdi → o.h> が薄く出る)
      completion = { ghost_text = { enabled = true } },
      -- 候補の絞り込みは Rust 版 (完成品を自動ダウンロード。ビルド不要)。取得できない環境では Lua 版で動く
      -- ※Lua 版は、候補が出た後に "o.h" のように素早く打つと絞り込みが追いつかず、
      --   #include <stdio.h で Tab を押すと stdint.h が入ることがある
      fuzzy = { implementation = "prefer_rust" },
      sources = { default = { "lsp", "path", "buffer" } },
    },
  },
}, {
  checker = { enabled = false },
})

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

-- ===== エラー / 警告の表示 =====
-- 行の右側にエラー内容を表示し、左端に E/W などの印を出す
-- 文章は日本語に置き換える (lua/user/diag_ja.lua の対応表。表にないものは英語のまま)
local diag_ja = require("user.diag_ja")
vim.diagnostic.config({
  virtual_text = {
    prefix = "●",
    spacing = 2,
    format = function(d) return diag_ja.text(d.message) end,
  },
  severity_sort = true, -- 同じ行に複数あるときはエラーを優先して表示
  -- <Space>d の詳細表示: 日本語と、元の英語の両方を出す (どのツールの指摘かも出す)
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
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local function m(lhs, rhs, desc)
      map("n", lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    m("gd", vim.lsp.buf.definition, "定義へ")
    m("gr", vim.lsp.buf.references, "参照")
    m("K", vim.lsp.buf.hover, "ホバー")
    m("<leader>rn", vim.lsp.buf.rename, "リネーム")
    m("<leader>ca", vim.lsp.buf.code_action, "コードアクション")
    m("<leader>d", vim.diagnostic.open_float, "診断を表示")
  end,
})
