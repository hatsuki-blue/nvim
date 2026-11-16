-- Python の構文エラーの表示を、言語サーバー (pyright など) が使えない環境でも行う
--   * エラーを出せる LSP が動いていないバッファだけ、python 自身で構文を調べて表示する
--   * 保存していない内容もそのまま調べる (標準入力で渡す。プログラムは実行しない)
--   * 文章は lua/user/diag_ja.lua の対応表で日本語にする
--   * わかるのは構文エラー (カッコ・コロン・字下げ・全角文字など) だけ。
--     変数名の書き間違いなどは、実行したとき (Space r) にわかる
local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("py_check")
local pending = {}

-- 構文を調べるだけの小さなプログラム。結果を「行 列 終わりの行 終わりの列 内容」で出す
local SCRIPT = [[
import sys
src = sys.stdin.buffer.read().decode("utf-8", "replace")
try:
    compile(src, "<stdin>", "exec")
except SyntaxError as e:
    out = "\t".join(str(x) for x in (e.lineno, e.offset, getattr(e, "end_lineno", None), getattr(e, "end_offset", None), e.msg))
    sys.stdout.buffer.write(out.encode("utf-8"))
except Exception:
    pass
]]

local python
local function find_python()
  if python == nil then
    python = false
    for _, name in ipairs({ "python3", "python" }) do
      if vim.fn.executable(name) == 1 then
        python = name
        break
      end
    end
  end
  return python or nil
end

-- エラーを出せる LSP (pyright / basedpyright / pylsp / ruff など) が動いているか
local function has_lsp(buf)
  return #vim.lsp.get_clients({ bufnr = buf }) > 0
end

function M.check(buf)
  if not api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "python" or vim.bo[buf].buftype ~= "" then return end
  if has_lsp(buf) then return vim.diagnostic.reset(ns, buf) end
  local py = find_python()
  if not py then return end
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local tick = api.nvim_buf_get_changedtick(buf)
  local ok = pcall(vim.system, { py, "-c", SCRIPT }, { stdin = table.concat(lines, "\n") .. "\n", text = false },
    function(r)
      vim.schedule(function()
        if not api.nvim_buf_is_valid(buf) or api.nvim_buf_get_changedtick(buf) ~= tick then return end
        if has_lsp(buf) then return vim.diagnostic.reset(ns, buf) end
        local l, c, el, ec, msg = (r.stdout or ""):match("^(%d+)\t(%S+)\t(%S+)\t(%S+)\t(.*)$")
        if not l then return vim.diagnostic.reset(ns, buf) end
        local lnum = math.min(math.max(tonumber(l) - 1, 0), math.max(#lines - 1, 0))
        local text = lines[lnum + 1] or ""
        -- Python の列は「何文字目か」(1 始まり)。nvim は「何バイト目か」(0 始まり) なので直す
        local function col_of(n, line_text)
          n = tonumber(n)
          if not n or n < 1 then return 0 end
          local b = vim.fn.byteidx(line_text, n - 1)
          return b >= 0 and b or #line_text
        end
        local d = {
          lnum = lnum, col = col_of(c, text),
          severity = vim.diagnostic.severity.ERROR, message = msg, source = "python",
        }
        local end_l = tonumber(el)
        if end_l and end_l - 1 == lnum and tonumber(ec) and tonumber(ec) > (tonumber(c) or 0) then
          d.end_lnum, d.end_col = lnum, col_of(ec, text)
        end
        vim.diagnostic.set(ns, buf, { d })
      end)
    end)
  if not ok then vim.diagnostic.reset(ns, buf) end
end

-- 入力が落ち着いてから調べる
function M.schedule(buf, delay)
  pending[buf] = (pending[buf] or 0) + 1
  local id = pending[buf]
  vim.defer_fn(function()
    if pending[buf] == id then M.check(buf) end
  end, delay or 400)
end

function M.setup()
  local g = api.nvim_create_augroup("user_py_check", {})
  api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave", "TextChanged" }, {
    group = g, pattern = { "*.py" },
    callback = function(ev) M.schedule(ev.buf) end,
  })
  api.nvim_create_autocmd("TextChangedI", {
    group = g, pattern = { "*.py" },
    callback = function(ev) M.schedule(ev.buf, 1000) end,
  })
  api.nvim_create_autocmd("LspAttach", {
    group = g,
    callback = function(ev)
      if vim.bo[ev.buf].filetype == "python" then vim.diagnostic.reset(ns, ev.buf) end
    end,
  })
end

return M
