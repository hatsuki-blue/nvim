-- C / C++ のエラー表示を、clangd (LSP) が使えない環境でも行う
--   * clangd が動いていないバッファだけ、gcc (g++) で構文エラーと警告を調べて表示する
--   * 保存していない内容もそのまま調べる (gcc に標準入力で渡す)
--   * 学校の PC など、LSP を入れられない環境向け。clangd が動いていれば何もしない
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("c_check_gcc")
local pending = {}

local function has_clangd(buf)
  return #vim.lsp.get_clients({ bufnr = buf, name = "clangd" }) > 0
end

local function compiler(ft)
  if ft == "cpp" then return vim.fn.executable("g++") == 1 and "g++" or nil end
  return vim.fn.executable("gcc") == 1 and "gcc" or nil
end

-- gcc の出力 ("<stdin>:行:列: error: 内容") を診断に変換する
local function parse(stderr)
  local diags = {}
  for line in (stderr or ""):gmatch("[^\r\n]+") do
    local l, c, sev, msg = line:match("^<stdin>:(%d+):(%d+): ([%a ]+): (.*)$")
    if not l then
      -- 列番号が無い形式 ("<stdin>:行: error: 内容")
      l, sev, msg = line:match("^<stdin>:(%d+): ([%a ]+): (.*)$")
      c = 1
    end
    if l and (sev == "error" or sev == "fatal error" or sev == "warning") then
      table.insert(diags, {
        lnum = tonumber(l) - 1,
        col = math.max(tonumber(c) - 1, 0),
        severity = sev == "warning" and vim.diagnostic.severity.WARN or vim.diagnostic.severity.ERROR,
        message = (msg:gsub("%s*%[%-W[^%]]*%]$", "")), -- 末尾の [-Wformat=] などは消す
        source = "gcc",
      })
    end
  end
  return diags
end

function M.check(buf)
  if not api.nvim_buf_is_valid(buf) then return end
  local ft = vim.bo[buf].filetype
  if ft ~= "c" and ft ~= "cpp" then return end
  if has_clangd(buf) then return vim.diagnostic.reset(ns, buf) end
  local cc = compiler(ft)
  if not cc then return end
  local text = table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
  local name = api.nvim_buf_get_name(buf)
  local dir = name ~= "" and vim.fn.fnamemodify(name, ":p:h") or vim.fn.getcwd()
  local tick = api.nvim_buf_get_changedtick(buf)
  local cmd = {
    cc, "-fsyntax-only", "-Wall", "-fdiagnostics-plain-output", "-fno-diagnostics-color",
    "-x", ft == "cpp" and "c++" or "c", "-I", dir, "-",
  }
  -- 英語 + ASCII の引用符で出させる (日本語訳は diag_ja の対応表で行う)
  local ok = pcall(vim.system, cmd, { stdin = text, text = true, cwd = dir, env = { LC_ALL = "C", LANG = "C" } },
    function(r)
      vim.schedule(function()
        if not api.nvim_buf_is_valid(buf) or api.nvim_buf_get_changedtick(buf) ~= tick then return end
        if has_clangd(buf) then return vim.diagnostic.reset(ns, buf) end
        vim.diagnostic.set(ns, buf, parse(r.stderr))
      end)
    end)
  if not ok then vim.diagnostic.reset(ns, buf) end
end

-- 入力が落ち着いてから調べる (打つたびに gcc を動かさない)
function M.schedule(buf, delay)
  pending[buf] = (pending[buf] or 0) + 1
  local id = pending[buf]
  vim.defer_fn(function()
    if pending[buf] == id then M.check(buf) end
  end, delay or 400)
end

function M.setup()
  local g = api.nvim_create_augroup("user_c_check", {})
  api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave", "TextChanged" }, {
    group = g,
    pattern = { "*.c", "*.h", "*.cpp", "*.cc", "*.cxx", "*.hpp", "*.hh" },
    callback = function(ev) M.schedule(ev.buf) end,
  })
  -- 入力中も、少し手を止めたら調べる
  api.nvim_create_autocmd("TextChangedI", {
    group = g,
    pattern = { "*.c", "*.h", "*.cpp", "*.cc", "*.cxx", "*.hpp", "*.hh" },
    callback = function(ev) M.schedule(ev.buf, 1000) end,
  })
  -- clangd が後から動き出したら、gcc の表示は消す (二重表示を防ぐ)
  api.nvim_create_autocmd("LspAttach", {
    group = g,
    callback = function(ev)
      local c = vim.lsp.get_client_by_id(ev.data.client_id)
      if c and c.name == "clangd" then vim.diagnostic.reset(ns, ev.buf) end
    end,
  })
end

return M
