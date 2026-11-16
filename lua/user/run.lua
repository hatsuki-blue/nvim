-- 今のファイルを実行する (<Space>r / :Run [引数])
--   保存してから、下のパネルのターミナルで、コンパイル (必要な言語のみ) と実行をする。
--   C / C++ の実行ファイルは、ソースの隣ではなく nvim のキャッシュ置き場に作る (フォルダを散らかさない)
local M = {}
local is_windows = vim.fn.has("win32") == 1
local ns = vim.api.nvim_create_namespace("user_run")

local function exe(name) return vim.fn.executable(name) == 1 end
local function first(...)
  for _, name in ipairs({ ... }) do
    if exe(name) then return name end
  end
  return nil
end

-- シェルに渡す文字として、安全に囲む (PowerShell と sh で書き方が違う)
local function q(s)
  if is_windows then return "'" .. s:gsub("'", "''") .. "'" end
  return "'" .. s:gsub("'", [['\'']]) .. "'"
end

-- 「コンパイルして、成功したら実行」をつなげる
local function chain(build, run)
  if is_windows then return build .. "; if ($?) { " .. run .. " }" end
  return build .. " && " .. run
end

-- プログラムを呼び出す書き方 (PowerShell では、引用符で囲んだパスの前に & が必要)
local function call(path) return (is_windows and "& " or "") .. q(path) end

local function out_path(file)
  local dir = vim.fn.stdpath("cache") .. "/run"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. vim.fn.fnamemodify(file, ":t:r") .. (is_windows and ".exe" or "")
end

-- 言語ごとの実行方法。戻り値: コマンド (文字列) / nil と、足りないものの説明
local runners = {
  c = function(file)
    local cc = first("gcc", "clang", "cc")
    if not cc then return nil, "C コンパイラ (gcc)" end
    local out = out_path(file)
    return chain(cc .. " -Wall -g -o " .. q(out) .. " " .. q(file) .. " -lm", call(out))
  end,
  cpp = function(file)
    local cc = first("g++", "clang++", "c++")
    if not cc then return nil, "C++ コンパイラ (g++)" end
    local out = out_path(file)
    return chain(cc .. " -Wall -g -std=c++17 -o " .. q(out) .. " " .. q(file), call(out))
  end,
  python = function(file)
    local py = first("python3", "python", "py")
    if not py then return nil, "Python" end
    return py .. " " .. q(file)
  end,
  javascript = function(file)
    if not exe("node") then return nil, "Node.js" end
    return "node " .. q(file)
  end,
  typescript = function(file)
    local r = first("tsx", "deno", "bun")
    if not r then return nil, "TypeScript の実行環境 (tsx / deno / bun)" end
    return r .. (r == "tsx" and " " or " run ") .. q(file)
  end,
  lua = function(file)
    local l = first("lua", "luajit")
    return (l or "nvim -l") .. " " .. q(file)
  end,
  sh = function(file) return (first("bash", "sh") or "sh") .. " " .. q(file) end,
  bash = function(file) return "bash " .. q(file) end,
  go = function(file)
    if not exe("go") then return nil, "Go" end
    return "go run " .. q(file)
  end,
  rust = function(file)
    if vim.fs.find("Cargo.toml", { upward = true, path = vim.fs.dirname(file) })[1] and exe("cargo") then return "cargo run" end
    if not exe("rustc") then return nil, "Rust (rustc)" end
    local out = out_path(file)
    return chain("rustc -o " .. q(out) .. " " .. q(file), call(out))
  end,
  java = function(file)
    if not exe("java") then return nil, "Java" end
    return "java " .. q(file)
  end,
  ruby = function(file)
    if not exe("ruby") then return nil, "Ruby" end
    return "ruby " .. q(file)
  end,
  php = function(file)
    if not exe("php") then return nil, "PHP" end
    return "php " .. q(file)
  end,
}

function M.run(args)
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= "" or file == "" then
    return vim.notify("実行するファイルを開いてください (名前を付けて保存したファイルが対象です)", vim.log.levels.WARN)
  end
  if vim.b[buf].remote_file then
    return vim.notify("接続先のファイルは、ここからは実行できません。接続先のターミナル (Space ts) で実行してください", vim.log.levels.WARN)
  end
  local ft = vim.bo[buf].filetype
  local runner = runners[ft]
  if not runner then
    return vim.notify("この種類のファイル (" .. (ft ~= "" and ft or "不明") .. ") の実行方法は、登録されていません", vim.log.levels.WARN)
  end
  if vim.bo[buf].modified then
    local ok, err = pcall(vim.cmd, "silent write")
    if not ok then return vim.notify("保存できなかったので、実行しませんでした: " .. tostring(err), vim.log.levels.ERROR) end
  end
  file = vim.fs.normalize(vim.fn.fnamemodify(file, ":p"))
  local cmd, missing = runner(file)
  if not cmd then
    return vim.notify(missing .. " が見つからないので、実行できません", vim.log.levels.ERROR)
  end
  if args and args ~= "" then cmd = cmd .. " " .. args end
  M.last = { cmd = cmd, cwd = vim.fs.dirname(file), label = "実行: " .. vim.fn.fnamemodify(file, ":t"), file = file, src = buf }
  M.again()
end

-- 直前と同じものを、もう一度実行する
function M.again()
  if not M.last then return M.run() end
  local term = require("user.terminal")
  -- 前回の実行結果のターミナルは閉じる (実行のたびに増えていかないように)
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then pcall(term.kill, M.buf) end
  if M.last.src and vim.api.nvim_buf_is_valid(M.last.src) then vim.diagnostic.reset(ns, M.last.src) end
  M.buf = term.run(M.last.cmd, { cwd = M.last.cwd, vars = { term_label = M.last.label } })
end

-- 実行が終わったら、エラーを日本語で説明する (lua/user/run_ja.lua)
--   * 実行結果の最後に、説明の行を足す (画面の表示だけ。出力そのものは変えない)
--   * エラーの行がわかるときは、ソースのその行にも印を付ける (次に実行するか、書き換えると消える)
local function explain(term_buf, status)
  local last = M.last
  if not last or not vim.api.nvim_buf_is_valid(term_buf) then return end
  local lines = vim.api.nvim_buf_get_lines(term_buf, 0, -1, false)
  -- ターミナルは、幅に収まらない行を折り返して複数の行にしている。幅いっぱいの行は、次の行とつなげて元に戻す
  local width, joined = 0, {}
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  local carry = nil
  for _, l in ipairs(lines) do
    local full = carry and (carry .. l) or l
    if width > 0 and vim.fn.strdisplaywidth(l) >= width then
      carry = full
    else
      joined[#joined + 1] = full
      carry = nil
    end
  end
  if carry then joined[#joined + 1] = carry end
  local res = require("user.run_ja").explain(joined, last.file, status)
  if not res then return end
  local row = #lines
  while row > 1 and lines[row] == "" do row = row - 1 end
  local virt = { { { "", "Comment" } }, { { "── 日本語での説明 ──", "DiagnosticInfo" } } }
  for _, t in ipairs(res.text) do virt[#virt + 1] = { { " " .. t, "DiagnosticError" } } end
  pcall(vim.api.nvim_buf_set_extmark, term_buf, ns, row - 1, 0, { virt_lines = virt })
  -- 説明が画面の外にならないように、ターミナルを一番下まで送る
  for _, w in ipairs(vim.fn.win_findbuf(term_buf)) do
    pcall(function()
      vim.api.nvim_win_set_cursor(w, { row, 0 })
      vim.api.nvim_win_call(w, function()
        vim.fn.winrestview({ topline = math.max(1, row - vim.api.nvim_win_get_height(w) + #virt + 1) })
      end)
    end)
  end
  local src = last.src
  if #res.marks > 0 and src and vim.api.nvim_buf_is_valid(src) then
    local diags, count = {}, vim.api.nvim_buf_line_count(src)
    for _, m in ipairs(res.marks) do
      -- その行に、すでにエラーの表示 (編集中の構文チェックなど) があれば、重ねて出さない
      if m.line >= 1 and m.line <= count and #vim.diagnostic.get(src, { lnum = m.line - 1 }) == 0 then
        diags[#diags + 1] = {
          lnum = m.line - 1, col = 0, message = m.message, source = "実行したときのエラー",
          severity = vim.diagnostic.severity.ERROR,
        }
      end
    end
    vim.diagnostic.set(ns, src, diags)
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      buffer = src, once = true,
      callback = function() vim.diagnostic.reset(ns, src) end,
    })
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("TermClose", {
    group = vim.api.nvim_create_augroup("user_run", {}),
    callback = function(ev)
      if ev.buf ~= M.buf then return end
      local status = vim.v.event.status
      -- 出力の最後の行が画面に出そろってから調べる
      vim.defer_fn(function() pcall(explain, ev.buf, status) end, 150)
    end,
  })
  vim.api.nvim_create_user_command("Run", function(a) M.run(a.args) end,
    { nargs = "*", desc = "今のファイルを実行 (後ろに書いたものは、プログラムへの引数)" })
  vim.keymap.set("n", "<leader>r", function() M.run() end, { desc = "今のファイルを実行" })
  vim.keymap.set("n", "<leader>R", M.again, { desc = "直前と同じものをもう一度実行" })
end

return M
