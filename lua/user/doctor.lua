-- :EnvCheck — この PC で、どの機能が使えるかを一覧で表示する
--   学校の PC など、入っているものが PC ごとに違う環境で、「何が使えて、何が足りないか」を確かめるためのもの
local M = {}

local function exe(name) return vim.fn.executable(name) == 1 end
local function mark(ok) return ok and "  ○ " or "  × " end

-- 言語サーバー: { 表示名, コマンド, 対象 }
local servers = {
  { "clangd", "clangd", "C / C++" },
  { "pyright", "pyright-langserver", "Python" },
  { "lua_ls", "lua-language-server", "Lua" },
  { "ts_ls", "typescript-language-server", "JavaScript / TypeScript" },
  { "gopls", "gopls", "Go" },
  { "rust_analyzer", "rust-analyzer", "Rust" },
  { "bashls", "bash-language-server", "シェルスクリプト" },
}

function M.report()
  local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"
  local function has_server(cmd)
    return exe(cmd) or vim.uv.fs_stat(mason_bin .. cmd) ~= nil or vim.uv.fs_stat(mason_bin .. cmd .. ".cmd") ~= nil
  end
  local L = {}
  local function add(s) L[#L + 1] = s end

  add(" モード")
  add("  オフラインモード (:Offline) : " .. (vim.g.offline and "オン (自動ダウンロードしない)" or "オフ"))
  add("  アイコン無しモード (:NoIcons): " .. (vim.g.have_nerd_font and "オフ" or "オン"))
  add("  コピー・貼り付けの共有        : " .. (vim.g.clipboard_kind or "× 使えません (nvim の中だけ)"))
  add("")
  add(" 基本のツール")
  local tools = {
    { "git", "プラグインの取得・更新、変更箇所の表示" },
    { "gcc", "C の実行 (Space r)、エラー表示、シンタックスハイライトの準備" },
    { "g++", "C++ の実行 (Space r)、エラー表示" },
    { "python3", "Python の実行 (Space r)" },
    { "node", "多くの言語サーバーと prettier (整形)" },
    { "rg", "文字列で探す (Space fg)" },
    { "make", "make" },
  }
  for _, t in ipairs(tools) do
    local ok = exe(t[1]) or (t[1] == "python3" and exe("python"))
    add(mark(ok) .. string.format("%-8s", t[1]) .. " " .. t[2])
  end
  add("")
  add(" 言語サーバー (LSP)  ※ × でも、C / C++ / Python は辞書で補完できます")
  for _, s in ipairs(servers) do
    add(mark(has_server(s[2])) .. string.format("%-14s", s[1]) .. " " .. s[3])
  end
  add("")
  add(" プラグイン")
  local ok_lazy, lazy = pcall(require, "lazy")
  if ok_lazy then
    local missing = {}
    for _, p in ipairs(lazy.plugins()) do
      if not p._.installed then missing[#missing + 1] = p.name end
    end
    if #missing == 0 then
      add("  ○ すべて入っています (" .. #lazy.plugins() .. " 個)")
    else
      add("  × 入っていないもの: " .. table.concat(missing, ", "))
      add("     ネットにつながる状態で :Lazy restore を実行してください")
    end
  end
  local ok_ts, ts = pcall(require, "nvim-treesitter")
  local parsers = ok_ts and ts.get_installed and ts.get_installed() or {}
  add(mark(#parsers > 0) .. "シンタックスハイライトのパーサー: " .. #parsers .. " 個"
    .. (#parsers == 0 and " (無くても、Vim 標準の色付けで表示されます)" or ""))
  add("")
  add(" 今のファイルの補完")
  local buf = M.source_buf or vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  local names = {}
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do names[#names + 1] = c.name end
  add("  ファイルの種類: " .. (ft ~= "" and ft or "(なし)"))
  if #names > 0 then
    add("  ○ 言語サーバーが動いています: " .. table.concat(names, ", "))
  elseif require("user.offline_cmp").active(buf) then
    add("  ○ オフライン補完 (辞書 + 自分のコード) が有効です")
    add("     標準関数・自分の関数・構造体のメンバ・スニペット・ファイル内の単語が候補に出ます")
  else
    add("  △ 言語サーバーは動いていません。スニペットと、開いているファイルの単語が候補に出ます")
  end
  add("")
  add(" (q か Esc で閉じる)")
  return L
end

function M.show()
  M.source_buf = vim.api.nvim_get_current_buf()
  local lines = M.report()
  M.source_buf = nil
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local w = 0
  for _, l in ipairs(lines) do w = math.max(w, vim.fn.strdisplaywidth(l)) end
  w = math.min(w + 2, vim.o.columns - 4)
  local h = math.min(#lines, vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", width = w, height = h,
    row = math.floor((vim.o.lines - h) / 2), col = math.floor((vim.o.columns - w) / 2),
    style = "minimal", border = "rounded", title = " この PC で使える機能 ", title_pos = "center",
  })
  for _, k in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", k, function() pcall(vim.api.nvim_win_close, win, true) end, { buffer = buf })
  end
end

function M.setup()
  vim.api.nvim_create_user_command("EnvCheck", M.show, { desc = "この PC で使える機能の一覧" })
end

return M
