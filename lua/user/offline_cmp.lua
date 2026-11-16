-- オフライン補完: 言語サーバー (LSP) が無い環境でも、補完・引数の表示・説明を出す
--   学校の PC など、clangd や pyright を入れられない環境向け。
--   そのファイルで補完のできる LSP が動いているときは、何もしない (LSP の方が正確なので任せる)。
--
--   できること (C / C++ / Python):
--     * 標準ライブラリの関数・定数・型を、日本語の説明つきで補完 (lua/user/dict/ の辞書)
--       C++ は cout / vector / sort などと、「変数.」の後の push_back / size なども
--     * 自分で書いた関数・マクロ・型・列挙の定数を、引数つきで補完
--       (C は #include "..." で読み込んでいる自分のヘッダの中も調べる)
--     * 構造体のメンバを「変数.」「ポインタ->」の後に補完 (変数の型を宣言から調べる)
--     * #include < の後にヘッダ名、# の後に #define などを補完
--     * Python: import の後にモジュール名、「モジュール名.」の後に中身、「self.」の後に属性
--     * 関数名( を打つと、引数の一覧を小さく表示し、今打っている引数を強調
--     * K で、標準関数や自分の関数の説明を表示
--
--   補完の一覧への組み込みは blink.cmp の「ソース」として行う (init.lua の sources.providers.offline)
local M = {}
local api = vim.api

local Kind = vim.lsp.protocol.CompletionItemKind
local PLAIN, SNIPPET = 1, 2

local LANG = { c = "c", cpp = "c", python = "python" }

-- 同じ名前のスニペット (snippets/ フォルダ) があるキーワード。スニペットの方を出すので、キーワードとしては出さない
local HAS_SNIPPET = {}
for _, kw in ipairs({
  "for", "while", "do", "if", "else", "switch", "case", "struct", "enum", -- C
  "elif", "try", "def", "class", "lambda", "import", "from", -- Python
}) do
  HAS_SNIPPET[kw] = true
end

-- ===== LSP が動いているか =====
local function has_lsp(buf, capability)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client.server_capabilities and client.server_capabilities[capability] then return true end
  end
  return false
end

-- このバッファで、オフライン補完を使うか
function M.active(buf)
  buf = (buf == nil or buf == 0) and api.nvim_get_current_buf() or buf
  return LANG[vim.bo[buf].filetype] ~= nil and not has_lsp(buf, "completionProvider")
end

-- ===== 辞書 =====
local dict_cache = {}
local function dict(lang)
  if dict_cache[lang] == nil then
    local ok, d = pcall(require, "user.dict." .. lang)
    if ok then
      d.by_name, d.is_keyword = {}, {}
      for _, it in ipairs(d.items) do d.by_name[it[1]] = it end
      for _, kw in ipairs(d.keywords or {}) do d.is_keyword[kw] = true end
    end
    dict_cache[lang] = ok and d or false
  end
  return dict_cache[lang] or nil
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- 説明 (Markdown)。code: 宣言、note: 1行の補足、text: 説明の文章
local function doc(lang, code, note, text)
  local out = {}
  if code and code ~= "" then out[#out + 1] = "```" .. lang .. "\n" .. code .. "\n```" end
  if note and note ~= "" then out[#out + 1] = note end
  if text and text ~= "" then out[#out + 1] = (text:gsub("\n", "  \n")) end
  return { kind = "markdown", value = table.concat(out, "\n\n") }
end

-- 関数の候補を確定したときに入れる文字。 name( ) の中にカーソルを置く。
--   すでに後ろに ( があるとき (名前だけを書き換えるとき) は、名前だけを入れる
local function call_text(name, no_args, next_char)
  if next_char == "(" then return name, PLAIN end
  if no_args then return name .. "()", PLAIN end
  return name .. "($0)", SNIPPET
end

-- ===== C: 自分のコードから、関数・マクロ・型・構造体を集める =====
local CONTROL = {
  ["if"] = true, ["else"] = true, ["while"] = true, ["for"] = true, ["switch"] = true, ["return"] = true,
  ["sizeof"] = true, ["do"] = true, ["case"] = true, ["typedef"] = true, ["goto"] = true,
}

-- コメントと文字列の中身を消す (行数は変えない)
local function clean_lines(lines)
  local out, in_block = {}, false
  for i, l in ipairs(lines) do
    if in_block then
      local e = l:find("*/", 1, true)
      if e then
        l, in_block = string.rep(" ", e + 1) .. l:sub(e + 2), false
      else
        l = ""
      end
    end
    if not in_block then
      l = l:gsub('"[^"\\]*\\.[^"]*"', '""'):gsub('"[^"]*"', '""'):gsub("'\\?.'", "' '")
      l = l:gsub("/%*.-%*/", " ")
      local s = l:find("/*", 1, true)
      local c = l:find("//", 1, true)
      if s and (not c or s < c) then
        l, in_block = l:sub(1, s - 1), true
      elseif c then
        l = l:sub(1, c - 1)
      end
    end
    out[i] = l
  end
  return out
end

-- 構造体の中身 ("{ int x; char *name; }") から、メンバの一覧を作る
local function parse_members(body)
  local members = {}
  body = body:sub(2, -2):gsub("%b{}", " ") -- 入れ子の構造体の中身は見ない
  body = body:gsub("%f[%w_]public%s*:", " "):gsub("%f[%w_]private%s*:", " "):gsub("%f[%w_]protected%s*:", " ") -- C++
  for decl in body:gmatch("([^;]+);") do
    decl = trim(decl:gsub("%s+", " "))
    local fp = decl:match("%(%s*%*%s*([%a_][%w_]*)%s*%)") -- 関数ポインタ
    if fp then
      members[#members + 1] = { name = fp, type = "関数ポインタ" }
    elseif decl ~= "" and not decl:find("(", 1, true) then
      local first, rest = decl:match("^([^,]+)(.*)$")
      first = first:gsub("%s*%[.*$", ""):gsub("%s*:%s*[%w_]+%s*$", "") -- 配列の [10] やビットフィールドの :3 を外す
      local base, name = first:match("^(.-)([%a_][%w_]*)%s*$")
      if name and base then
        local stars = base:match("%*+%s*$") or ""
        local btype = trim(base:gsub("%*+%s*$", ""))
        if btype ~= "" then
          members[#members + 1] = { name = name, type = trim(btype .. " " .. stars) }
          for piece in rest:gmatch(",([^,]+)") do
            local st, nm = piece:match("^%s*(%**)%s*([%a_][%w_]*)")
            if nm then members[#members + 1] = { name = nm, type = trim(btype .. " " .. st) } end
          end
        end
      end
    end
  end
  return members
end

-- lines を調べて、sym に集める
--   file: そのコードがあるファイル (今のバッファなら nil)。定義へのジャンプ (gd) に使う
local function scan_c(lines, sym, file)
  local cl = clean_lines(lines)
  local text = table.concat(cl, "\n")
  -- 名前 → 定義の場所。prefer: すでに場所を知っていても上書きする (プロトタイプ宣言より、本体の定義を優先)
  local function at(name, line, prefer)
    if prefer or not sym.where[name] then sym.where[name] = { file = file, line = line, proto = not prefer } end
  end
  local function line_of(pos) return select(2, text:sub(1, pos):gsub("\n", "")) + 1 end

  -- 構造体 / 共用体
  for _, kw in ipairs({ "struct", "union", "class" }) do
    local init = 1
    while true do
      local s, e, tag, body, alias = text:find("%f[%w_]" .. kw .. "%f[^%w_]%s*([%a_]?[%w_]*)%s*(%b{})%s*%**%s*([%a_]?[%w_]*)", init)
      if not s then break end
      local is_typedef = text:sub(math.max(1, s - 12), s - 1):find("typedef%s+$") ~= nil
      local members = parse_members(body)
      if tag ~= "" then
        sym.structs[tag] = members
        at(tag, line_of(s), true)
      end
      if is_typedef and alias ~= "" then
        at(alias, line_of(s), true)
        sym.structs[alias] = members
        sym.types[alias] = kw .. (tag ~= "" and (" " .. tag) or "")
      end
      init = e + 1
    end
  end

  -- 列挙
  for pos, body in text:gmatch("()%f[%w_]enum%f[^%w_]%s*[%a_]?[%w_]*%s*(%b{})") do
    local enum_line = line_of(pos)
    for piece in body:sub(2, -2):gmatch("[^,]+") do
      local name = piece:match("^%s*([%a_][%w_]*)")
      if name then
        sym.enums[name] = true
        at(name, enum_line)
      end
    end
  end

  -- 関数・マクロ・typedef ({ } の外にあるものだけ)
  local depth = 0
  for i, l in ipairs(cl) do
    if depth == 0 then
      local name, rest = l:match("^%s*#%s*define%s+([%a_][%w_]*)(.*)$")
      if name then
        at(name, i, true)
        local args = rest:match("^(%b())")
        if args then
          sym.funcs[name] = { sig = "#define " .. name .. args, macro = true, noargs = args:match("^%(%s*%)$") ~= nil }
        else
          sym.macros[name] = trim(rest)
        end
      elseif l:find("^%s*typedef%f[^%w_]") and not l:find("{", 1, true) then
        local alias = l:match("([%a_][%w_]*)%s*;%s*$") or l:match("%(%s*%*%s*([%a_][%w_]*)%s*%)")
        if alias then
          at(alias, i)
          sym.types[alias] = trim((l:gsub("^%s*typedef%s+", ""):gsub(";%s*$", "")))
          local tag = l:match("struct%s+([%a_][%w_]*)") or l:match("union%s+([%a_][%w_]*)")
          if tag then sym.alias_of[alias] = tag end
        end
      else
        local prefix, fname, args = l:match("^([%a_][%w_%s%*]-)%f[%a_]([%a_][%w_]*)%s*(%b())%s*[{;]?%s*$")
        if fname and not CONTROL[fname] and not CONTROL[trim(prefix):match("^[%a_]+") or ""] then
          sym.funcs[fname] = {
            sig = trim(prefix:gsub("%s+", " ")) .. " " .. fname .. args:gsub("%s+", " "),
            noargs = args:match("^%(%s*%)$") ~= nil or args:match("^%(%s*void%s*%)$") ~= nil,
            line = i,
          }
          sym.funcs[fname].sig = sym.funcs[fname].sig:gsub("%* ", "*")
          at(fname, i, not l:find(";%s*$")) -- ; で終わるのはプロトタイプ宣言
        end
      end
    end
    local _, opens = l:gsub("{", "")
    local _, closes = l:gsub("}", "")
    depth = math.max(depth + opens - closes, 0)
  end
end

local function new_sym()
  return { funcs = {}, macros = {}, types = {}, structs = {}, enums = {}, alias_of = {}, where = {} }
end

-- ヘッダファイルの中身 (更新時刻が変わるまで覚えておく)
local header_cache = {}
local function scan_header(path, sym, seen, depth)
  if seen[path] or depth > 3 then return end
  seen[path] = true
  local st = vim.uv.fs_stat(path)
  if not st or st.type ~= "file" or st.size > 512 * 1024 then return end
  local c = header_cache[path]
  if not c or c.mtime ~= st.mtime.sec or c.size ~= st.size then
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then return end
    c = { mtime = st.mtime.sec, size = st.size, lines = lines }
    header_cache[path] = c
  end
  scan_c(c.lines, sym, path)
  local dir = vim.fs.dirname(path)
  for _, l in ipairs(c.lines) do
    local inc = l:match('^%s*#%s*include%s*"([^"]+)"')
    if inc then scan_header(vim.fs.normalize(dir .. "/" .. inc), sym, seen, depth + 1) end
  end
end

-- バッファと、そこから読み込んでいる自分のヘッダの記号 (バッファが変わるまで覚えておく)
local sym_cache = {}
local function c_symbols(buf)
  local tick = api.nvim_buf_get_changedtick(buf)
  local c = sym_cache[buf]
  if c and c.tick == tick and c.lang == "c" then return c.sym, c.lines end
  local lines = api.nvim_buf_line_count(buf) <= 20000 and api.nvim_buf_get_lines(buf, 0, -1, false) or {}
  local sym = new_sym()
  scan_c(lines, sym)
  local name = api.nvim_buf_get_name(buf)
  local dir = name ~= "" and vim.fs.dirname(vim.fs.normalize(name)) or vim.fn.getcwd()
  local seen = {}
  if name ~= "" then seen[vim.fs.normalize(name)] = true end
  for _, l in ipairs(lines) do
    local inc = l:match('^%s*#%s*include%s*"([^"]+)"')
    if inc then scan_header(vim.fs.normalize(dir .. "/" .. inc), sym, seen, 1) end
  end
  sym_cache[buf] = { tick = tick, sym = sym, lines = lines, lang = "c" }
  return sym, lines
end

-- 型の文字列 ("struct node *" や "Node") から、構造体の名前を取り出す
local function struct_key(sym, type_str)
  if not type_str then return nil end
  local t = type_str:gsub("%*", " "):gsub("%f[%w_]const%f[^%w_]", " "):gsub("%f[%w_]volatile%f[^%w_]", " ")
  local tag = t:match("struct%s+([%a_][%w_]*)") or t:match("union%s+([%a_][%w_]*)")
  local key = tag or trim(t)
  for _ = 1, 5 do
    if sym.structs[key] then return key end
    if not sym.alias_of[key] then break end
    key = sym.alias_of[key]
  end
  return sym.structs[key] and key or nil
end

-- 変数の宣言を、カーソルの行から上に向かって探し、構造体の名前を返す
local function var_struct(sym, lines, row, var)
  for i = math.min(row, #lines), 1, -1 do
    local l = lines[i]
    if l:find(var, 1, true) then
      local tag = l:match("struct%s+([%a_][%w_]*)[%s%*]+[^;()]-%f[%w_]" .. var .. "%f[^%w_]")
        or l:match("union%s+([%a_][%w_]*)[%s%*]+[^;()]-%f[%w_]" .. var .. "%f[^%w_]")
      if tag then
        local key = struct_key(sym, tag)
        if key then return key end
      end
      for s, t in l:gmatch("()%f[%w_]([%a_][%w_]*)%f[^%w_]") do
        if t ~= var and (sym.structs[t] or sym.alias_of[t])
          and l:find("^[%s%*]+[^;()]-%f[%w_]" .. var .. "%f[^%w_]", s + #t) then
          local key = struct_key(sym, t)
          if key then return key end
        end
      end
    end
  end
  return nil
end

-- 「a.b[0]->」のような式を、名前の並び { "a", "b" } に分ける (カーソルの直前が . か -> のとき)
local function member_chain(before)
  local chain, s = {}, before
  while true do
    local op_len = (s:sub(-2) == "->" and 2) or (s:sub(-1) == "." and 1) or 0
    if op_len == 0 then break end
    s = s:sub(1, -op_len - 1):gsub("%s+$", "")
    while s:find("%b[]$") do s = s:gsub("%b[]$", ""):gsub("%s+$", "") end
    local name = s:match("([%a_][%w_]*)$")
    if not name then return chain, false end -- f(). や ). など。型は調べられない
    table.insert(chain, 1, name)
    s = s:sub(1, -#name - 1):gsub("%s+$", "")
  end
  return chain, true
end

local function c_member_items(sym, lines, row, before, cpp)
  local chain, ok = member_chain(before)
  local key
  if ok and #chain > 0 then
    key = var_struct(sym, lines, row, chain[1])
    for i = 2, #chain do
      if not key then break end
      local found
      for _, m in ipairs(sym.structs[key]) do
        if m.name == chain[i] then found = struct_key(sym, m.type) end
      end
      key = found
    end
  end
  local items = {}
  local function add(k, members, sure)
    for _, m in ipairs(members) do
      items[#items + 1] = {
        label = m.name, kind = Kind.Field, insertText = m.name, insertTextFormat = PLAIN,
        labelDetails = { description = sure and m.type or (m.type .. "  (" .. k .. ")") },
        documentation = doc("c", m.type .. " " .. m.name .. ";", k .. " のメンバ"),
        sortText = (sure and "0" or "1") .. m.name,
      }
    end
  end
  if key then
    add(key, sym.structs[key], true)
  else
    -- 型がわからないときは、知っている構造体のメンバをすべて出す (同じ中身は1回だけ)
    local done = {}
    for k, members in pairs(sym.structs) do
      if not done[members] then
        done[members] = true
        add(k, members, false)
      end
    end
    -- C++: 標準のコンテナ (vector, string など) のメンバ関数
    for _, m in ipairs(cpp and cpp.methods or {}) do
      local is_call = m[2]:find("(", 1, true) ~= nil
      local text, fmt = m[1], PLAIN
      if is_call then text, fmt = call_text(m[1], m[2]:find("%(%)$") ~= nil, nil) end
      items[#items + 1] = {
        label = m[1], kind = is_call and Kind.Method or Kind.Field, insertText = text, insertTextFormat = fmt,
        labelDetails = { description = m[3] }, documentation = doc("cpp", m[2], m[3], m[4]), sortText = "2" .. m[1],
      }
    end
  end
  return items
end

local DIRECTIVES = {
  { "include", "ヘッダを読み込む。#include <stdio.h> / #include \"my.h\"" },
  { "define", "マクロ (置き換え) を定義する。#define N 100" },
  { "undef", "マクロの定義を取り消す" },
  { "ifdef", "そのマクロが定義されていれば、#endif までを有効にする" },
  { "ifndef", "そのマクロが定義されていなければ、#endif までを有効にする (ヘッダの二重読み込み防止に使う)" },
  { "if", "条件が真なら、#endif までを有効にする" },
  { "elif", "#if の「そうでなく、もし」" },
  { "else", "#if / #ifdef の「そうでなければ」" },
  { "endif", "#if / #ifdef / #ifndef の終わり" },
  { "pragma once", "このヘッダを1回だけ読み込む (二重読み込み防止)" },
  { "error", "コンパイルをエラーで止める" },
}

-- /usr/include にあるヘッダ (あれば、辞書に無いものも候補に出す)
local sys_headers
local function system_headers()
  if sys_headers then return sys_headers end
  sys_headers = {}
  for _, dir in ipairs({ "/usr/include", "/usr/local/include" }) do
    local ok, it = pcall(vim.fs.dir, dir)
    if ok and it then
      local n = 0
      for name, kind in it do
        if kind == "file" and name:match("%.h$") then sys_headers[#sys_headers + 1] = name end
        n = n + 1
        if n > 3000 then break end
      end
    end
  end
  return sys_headers
end

local function c_items(ctx, before, next_char)
  local d = dict("c")
  local cpp = vim.bo[ctx.bufnr].filetype == "cpp" and dict("cpp") or nil
  local items = {}
  local row = ctx.cursor[1]

  -- #include <
  local hstart, typed = before:match("^%s*#%s*include%s*<()([^>]*)$")
  if hstart then
    local close = next_char == ">" and "" or ">"
    local done = {}
    local function add(name, text, sort)
      if done[name] then return end
      done[name] = true
      items[#items + 1] = {
        label = name, kind = Kind.File, insertTextFormat = PLAIN, filterText = name, sortText = sort .. name,
        textEdit = {
          newText = name .. close,
          range = { start = { line = row - 1, character = hstart - 1 }, ["end"] = { line = row - 1, character = hstart - 1 + #typed } },
        },
        documentation = text and doc("c", "#include <" .. name .. ">", nil, text) or nil,
      }
    end
    for i, h in ipairs(cpp and cpp.headers or {}) do add(h[1], h[2], string.format("0%03d", i)) end
    for i, h in ipairs(d and d.headers or {}) do add(h[1], h[2], string.format("1%03d", i)) end
    for _, name in ipairs(system_headers()) do add(name, nil, "2") end
    -- "string." や "sys/" まで打った後は、そこまでが同じものだけに絞る
    --   (. や / の後は、補完の絞り込みが「その後ろの文字」だけで行われるため)
    local prefix = typed:match("^(.*[%./])")
    if prefix then
      items = vim.tbl_filter(function(it) return it.label:sub(1, #prefix) == prefix end, items)
    end
    return items
  end
  if before:find('^%s*#%s*include%s*"') then return {} end -- "..." は path (ファイル名の補完) に任せる

  -- # の後
  if before:find("^%s*#%s*%a*$") then
    for i, dv in ipairs(DIRECTIVES) do
      items[#items + 1] = {
        label = dv[1], kind = Kind.Keyword, insertText = dv[1], insertTextFormat = PLAIN,
        sortText = string.format("%02d", i), documentation = doc("c", "#" .. dv[1], nil, dv[2]),
      }
    end
    return items
  end

  local sym, lines = c_symbols(ctx.bufnr)

  -- 変数. / ポインタ->
  local head = before:gsub("[%w_]*$", "")
  if head:find("%f[%w_]%d[%w_]*%.$") then return {} end -- 3.14 のような数の途中
  if head:sub(-1) == "." or head:sub(-2) == "->" then
    return c_member_items(sym, lines, row, head, cpp)
  end

  -- 自分で書いたもの
  local mine = {}
  for name, f in pairs(sym.funcs) do
    mine[name] = true
    local text, fmt = call_text(name, f.noargs, next_char)
    items[#items + 1] = {
      label = name, kind = Kind.Function, insertText = text, insertTextFormat = fmt,
      labelDetails = { description = f.macro and "マクロ" or "自分の関数" },
      documentation = doc("c", f.sig, f.macro and "このプログラムで定義したマクロ" or "このプログラムで定義した関数"),
    }
  end
  for name, value in pairs(sym.macros) do
    mine[name] = true
    items[#items + 1] = {
      label = name, kind = Kind.Constant, insertText = name, insertTextFormat = PLAIN,
      labelDetails = { description = value ~= "" and value:sub(1, 24) or "マクロ" },
      documentation = doc("c", "#define " .. name .. " " .. value, "このプログラムで定義したマクロ"),
    }
  end
  for name, def in pairs(sym.types) do
    mine[name] = true
    items[#items + 1] = {
      label = name, kind = Kind.Struct, insertText = name, insertTextFormat = PLAIN,
      labelDetails = { description = "自分の型" },
      documentation = doc("c", "typedef " .. def .. (def:find(name, 1, true) and "" or (" " .. name)) .. ";", "このプログラムで定義した型"),
    }
  end
  for name in pairs(sym.enums) do
    mine[name] = true
    items[#items + 1] = {
      label = name, kind = Kind.EnumMember, insertText = name, insertTextFormat = PLAIN,
      labelDetails = { description = "列挙の定数" },
    }
  end

  -- 今のファイルが読み込んでいるヘッダ。標準関数を確定したとき、足りない #include を自動で足すのに使う
  local included, last_include, any_include = {}, 0, false
  for i, l in ipairs(lines) do
    local h = l:match('^%s*#%s*include%s*[<"]([^>"]+)[>"]')
    if h then included[h], last_include, any_include = true, i, true end
    if i > 400 and not h and last_include > 0 and i - last_include > 200 then break end
  end
  local function include_edit(header)
    if header == "" or included[header] or included["bits/stdc++.h"] then return nil end
    if cpp and included["c" .. header:gsub("%.h$", "")] then return nil end -- <cstdio> は <stdio.h> と同じ
    if header == "stddef.h" and any_include then return nil end -- NULL や size_t は、ほかのヘッダにも入っている
    return {
      newText = "#include <" .. header .. ">\n",
      range = { start = { line = last_include, character = 0 }, ["end"] = { line = last_include, character = 0 } },
    }
  end

  -- 標準ライブラリ (C++ のファイルでは、C++ の辞書を先に見る)
  for _, dd in ipairs({ cpp or false, d or false }) do
    for _, it in ipairs(dd and dd.items or {}) do
      local name, sig, header, text, kind = it[1], it[2], it[3], it[4], it[5]
      if not mine[name] then
        mine[name] = true
        local item = {
          label = name, labelDetails = { description = header },
          documentation = doc(dd == cpp and "cpp" or "c", sig, header ~= "" and ("`#include <" .. header .. ">`") or nil, text),
        }
        if kind == "type" then
          item.kind, item.insertText, item.insertTextFormat = Kind.Class, name, PLAIN
        elseif kind == "const" then
          item.kind, item.insertText, item.insertTextFormat = Kind.Constant, name, PLAIN
        else
          item.kind = Kind.Function
          item.insertText, item.insertTextFormat = call_text(name, sig:find("%(void%)$") ~= nil, next_char)
        end
        local edit = include_edit(header)
        if edit then
          item.additionalTextEdits = { edit }
          item.documentation.value = item.documentation.value
            .. "\n\n(確定すると `#include <" .. header .. ">` を自動で追加します)"
        end
        items[#items + 1] = item
      end
    end
    for _, kw in ipairs(dd and dd.keywords or {}) do
      if not HAS_SNIPPET[kw] and not mine[kw] then
        mine[kw] = true
        items[#items + 1] = { label = kw, kind = Kind.Keyword, insertText = kw, insertTextFormat = PLAIN }
      end
    end
  end
  return items
end

-- ===== Python =====
local function py_scan(buf)
  local tick = api.nvim_buf_get_changedtick(buf)
  local c = sym_cache[buf]
  if c and c.tick == tick and c.lang == "python" then return c.sym end
  local sym = { funcs = {}, classes = {}, aliases = {}, attrs = {}, methods = {}, where = {} }
  local lines = api.nvim_buf_line_count(buf) <= 20000 and api.nvim_buf_get_lines(buf, 0, -1, false) or {}
  for i, l in ipairs(lines) do
    local indent, name, args = l:match("^(%s*)def%s+([%a_][%w_]*)%s*(%b())")
    if name then
      sym.where[name] = sym.where[name] or { line = i }
      local f = { sig = "def " .. name .. args, noargs = args:match("^%(%s*%)$") ~= nil or args:match("^%(%s*self%s*%)$") ~= nil }
      if indent ~= "" and args:find("^%(%s*self") then sym.methods[name] = f else sym.funcs[name] = f end
    end
    local cls = l:match("^%s*class%s+([%a_][%w_]*)")
    if cls then
      sym.classes[cls] = trim(l)
      sym.where[cls] = sym.where[cls] or { line = i }
    end
    local mod, alias = l:match("^%s*import%s+([%w_%.]+)%s+as%s+([%a_][%w_]*)")
    if mod then sym.aliases[alias] = mod end
    for attr in l:gmatch("self%.([%a_][%w_]*)%s*=[^=]") do sym.attrs[attr] = true end
  end
  sym_cache[buf] = { tick = tick, sym = sym, lang = "python" }
  return sym
end

local function py_module_items(d, mod)
  local items = {}
  local m = d.modules[mod]
  for _, it in ipairs(m and m[2] or {}) do
    local name, sig, text = it[1], it[2], it[3]
    local is_call = sig:find("(", 1, true) ~= nil
    local item = {
      label = name, kind = is_call and Kind.Function or Kind.Constant, labelDetails = { description = mod },
      documentation = doc("python", sig, nil, text), insertText = name, insertTextFormat = PLAIN,
    }
    if is_call and not sig:find("^@") then item.insertText, item.insertTextFormat = call_text(name, sig:find("%(%)$") ~= nil, nil) end
    items[#items + 1] = item
  end
  return items
end

local function py_items(ctx, before, next_char)
  local d = dict("python")
  if not d then return {} end
  local items = {}
  local sym = py_scan(ctx.bufnr)

  -- import モジュール名 / from モジュール名
  if before:find("^%s*import%s+[%w_,%s]*$") or before:find("^%s*from%s+[%w_]*$") then
    for name, m in pairs(d.modules) do
      items[#items + 1] = {
        label = name, kind = Kind.Module, insertText = name, insertTextFormat = PLAIN,
        documentation = doc("python", "import " .. name, nil, m[1]),
      }
    end
    return items
  end
  -- from モジュール名 import
  local from_mod = before:match("^%s*from%s+([%w_]+)%s+import%s+[%w_,%s]*$")
  if from_mod then
    for _, it in ipairs(py_module_items(d, from_mod)) do
      it.insertText, it.insertTextFormat = it.label, PLAIN
      items[#items + 1] = it
    end
    return items
  end

  -- 何か.
  local head = before:gsub("[%w_]*$", "")
  if head:find("%f[%w_]%d[%w_]*%.$") then return {} end -- 3.14 のような数の途中
  if head:sub(-1) == "." then
    local owner = head:match("([%a_][%w_]*)%.$")
    local mod = owner and (sym.aliases[owner] or owner)
    if owner == "self" then
      for name in pairs(sym.attrs) do
        items[#items + 1] = { label = name, kind = Kind.Field, insertText = name, insertTextFormat = PLAIN,
          labelDetails = { description = "属性" } }
      end
      for name, f in pairs(sym.methods) do
        local text, fmt = call_text(name, f.noargs, next_char)
        items[#items + 1] = { label = name, kind = Kind.Method, insertText = text, insertTextFormat = fmt,
          labelDetails = { description = "メソッド" }, documentation = doc("python", f.sig) }
      end
      return items
    end
    if mod and d.modules[mod] and #d.modules[mod][2] > 0 then return py_module_items(d, mod) end
    for _, it in ipairs(d.methods) do
      local name, sig, owner_type, text = it[1], it[2], it[3], it[4]
      local ins, fmt = call_text(name, sig:find("%(%)") ~= nil and not sig:find("%([^)]") , next_char)
      items[#items + 1] = {
        label = name, kind = Kind.Method, insertText = ins, insertTextFormat = fmt,
        labelDetails = { description = owner_type }, documentation = doc("python", sig, nil, text),
      }
    end
    for name, f in pairs(sym.methods) do
      local ins, fmt = call_text(name, f.noargs, next_char)
      items[#items + 1] = { label = name, kind = Kind.Method, insertText = ins, insertTextFormat = fmt,
        labelDetails = { description = "自分のメソッド" }, documentation = doc("python", f.sig) }
    end
    return items
  end

  -- 自分で書いたもの
  local mine = {}
  for name, f in pairs(sym.funcs) do
    mine[name] = true
    local text, fmt = call_text(name, f.noargs, next_char)
    items[#items + 1] = { label = name, kind = Kind.Function, insertText = text, insertTextFormat = fmt,
      labelDetails = { description = "自分の関数" }, documentation = doc("python", f.sig, "このプログラムで定義した関数") }
  end
  for name, def in pairs(sym.classes) do
    mine[name] = true
    items[#items + 1] = { label = name, kind = Kind.Class, insertText = name, insertTextFormat = PLAIN,
      labelDetails = { description = "自分のクラス" }, documentation = doc("python", def) }
  end
  for alias, mod in pairs(sym.aliases) do
    mine[alias] = true
    items[#items + 1] = { label = alias, kind = Kind.Module, insertText = alias, insertTextFormat = PLAIN,
      labelDetails = { description = mod } }
  end
  -- 組み込み
  for _, it in ipairs(d.items) do
    local name, sig, group, text, kind = it[1], it[2], it[3], it[4], it[5]
    if not mine[name] then
      local item = { label = name, labelDetails = { description = group }, documentation = doc("python", sig, nil, text),
        insertText = name, insertTextFormat = PLAIN }
      if kind == "type" then
        item.kind = Kind.Class
      elseif kind == "kw" then
        item.kind = Kind.Keyword
      else
        item.kind = Kind.Function
        item.insertText, item.insertTextFormat = call_text(name, sig:find("%(%)$") ~= nil, next_char)
      end
      items[#items + 1] = item
    end
  end
  for _, kw in ipairs(d.keywords) do
    if not HAS_SNIPPET[kw] then
      items[#items + 1] = { label = kw, kind = Kind.Keyword, insertText = kw, insertTextFormat = PLAIN }
    end
  end
  return items
end

-- ===== ほかのソース (ファイル内の単語・スニペット) との調整 =====
-- カーソルの前が「構造体のメンバ」「ヘッダ名」「モジュールの中身」を打つ場所か。
--   そこでは、関係のない候補 (スニペットやファイル内の単語) を出さない
--   kind: "snippets" / "buffer"
function M.exclusive(ctx, kind)
  local ok, res = pcall(function()
    local buf = ctx.bufnr
    local lang = LANG[vim.bo[buf].filetype]
    local before = ctx.line:sub(1, ctx.cursor[2])
    local head = before:gsub("[%w_]*$", "")
    local dot = head:sub(-1) == "." or head:sub(-2) == "->"
    -- Python の import の行
    local import = lang == "python" and (before:find("^%s*import%s") ~= nil or before:find("^%s*from%s") ~= nil)
    -- スニペットは、「何か.」の後、C の # の行、import の行では出さない
    if kind == "snippets" then return dot or import or (lang == "c" and before:find("^%s*#") ~= nil) end
    if not lang or not M.active(buf) then return false end
    if import then return true end
    if lang == "c" then
      if before:find("^%s*#%s*include%s*<") or before:find("^%s*#%s*%a*$") then return true end
      return dot and (vim.bo[buf].filetype == "cpp" or next(c_symbols(buf).structs) ~= nil)
    end
    local owner = dot and head:match("([%a_][%w_]*)%.$")
    local d = dict("python")
    return owner ~= nil and d ~= nil and d.modules[py_scan(buf).aliases[owner] or owner] ~= nil
  end)
  return ok and res or false
end

-- 辞書の候補と同じ単語は、「ファイル内の単語」の候補からは外す (同じ名前が2つ並ばないように)
function M.dedupe_words(ctx, items)
  local buf = ctx.bufnr
  if not M.active(buf) then return items end
  local ok, res = pcall(function()
    local d = dict(LANG[vim.bo[buf].filetype])
    local cpp = vim.bo[buf].filetype == "cpp" and dict("cpp") or nil
    return vim.tbl_filter(function(it)
      local kw = (d and d.is_keyword[it.label]) or (cpp and cpp.is_keyword[it.label])
      return not (kw and not HAS_SNIPPET[it.label]) and M.lookup(buf, it.label) == nil
    end, items)
  end)
  return ok and res or items
end

-- ===== blink.cmp のソース =====
function M.new(opts)
  return setmetatable({ opts = opts or {} }, { __index = M })
end

function M:enabled() return M.active(0) end

function M:get_trigger_characters() return { ".", ">", "<", "#" } end

function M:get_completions(ctx, callback)
  local items = {}
  local ok, err = pcall(function()
    local lang = LANG[vim.bo[ctx.bufnr].filetype]
    local col = ctx.cursor[2]
    local before, next_char = ctx.line:sub(1, col), ctx.line:sub(col + 1, col + 1)
    if lang == "c" then
      items = c_items(ctx, before, next_char)
    elseif lang == "python" then
      items = py_items(ctx, before, next_char)
    end
  end)
  if not ok then
    items = {}
    vim.schedule(function() vim.notify_once("オフライン補完でエラー: " .. tostring(err), vim.log.levels.WARN) end)
  end
  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

-- ===== 名前から、宣言と説明を調べる (引数の表示と K で使う) =====
-- 戻り値: { sig = 宣言, note = 補足, text = 説明, lang = 言語 }
function M.lookup(buf, name)
  local lang = LANG[vim.bo[buf].filetype]
  if not lang or not name or name == "" then return nil end
  local d = dict(lang)
  if lang == "c" then
    local sym = c_symbols(buf)
    local f = sym.funcs[name]
    if f then return { sig = f.sig, note = f.macro and "このプログラムで定義したマクロ" or "このプログラムで定義した関数", lang = "c" } end
    if sym.macros[name] then return { sig = "#define " .. name .. " " .. sym.macros[name], note = "このプログラムで定義したマクロ", lang = "c" } end
    if sym.types[name] then return { sig = "typedef " .. sym.types[name] .. ";", note = "このプログラムで定義した型", lang = "c" } end
    local cpp = vim.bo[buf].filetype == "cpp" and dict("cpp") or nil
    for _, dd in ipairs({ cpp or false, d or false }) do
      local it = dd and dd.by_name[name]
      if it then
        return { sig = it[2], note = it[3] ~= "" and ("`#include <" .. it[3] .. ">`") or nil, text = it[4], lang = dd == cpp and "cpp" or "c" }
      end
    end
    for _, dd in ipairs({ cpp or false, d or false }) do
      for _, h in ipairs(dd and dd.headers or {}) do
        if h[1] == name then return { sig = "#include <" .. name .. ">", text = h[2], lang = "c" } end
      end
    end
    for _, m in ipairs(cpp and cpp.methods or {}) do
      if m[1] == name then return { sig = m[2], note = m[3] .. " のメンバ", text = m[4], lang = "cpp" } end
    end
  else
    local sym = py_scan(buf)
    local f = sym.funcs[name] or sym.methods[name]
    if f then return { sig = f.sig, note = "このプログラムで定義した関数", lang = "python" } end
    if sym.classes[name] then return { sig = sym.classes[name], note = "このプログラムで定義したクラス", lang = "python" } end
    local it = d and d.by_name[name]
    if it then return { sig = it[2], note = it[3], text = it[4], lang = "python" } end
    if d and d.modules[name] then return { sig = "import " .. name, text = d.modules[name][1], lang = "python" } end
    for _, m in ipairs(d and d.methods or {}) do
      if m[1] == name then return { sig = m[2], note = m[3] .. " のメソッド", text = m[4], lang = "python" } end
    end
  end
  return nil
end

-- ===== K: 説明を表示 =====
--   LSP があれば LSP の説明、無ければ辞書の説明、どちらも無ければ Vim 本来の K (C なら man)
function M.hover()
  local buf = api.nvim_get_current_buf()
  if has_lsp(buf, "hoverProvider") then return vim.lsp.buf.hover() end
  local word = vim.fn.expand("<cword>")
  -- stdio.h のようなヘッダ名の上では、ヘッダの説明を出す
  local file = vim.fn.expand("<cfile>")
  local info = M.lookup(buf, word) or (file ~= word and M.lookup(buf, file)) or nil
  if not info and LANG[vim.bo[buf].filetype] == "python" then
    -- math.sqrt のような「モジュール.名前」
    local d = dict("python")
    local line, col = api.nvim_get_current_line(), api.nvim_win_get_cursor(0)[2] + 1
    local s = col
    while s > 1 and line:sub(s - 1, s - 1):match("[%w_%.]") do s = s - 1 end
    local mod = line:sub(s):match("^([%a_][%w_]*)%." .. vim.pesc(word))
    mod = mod and (py_scan(buf).aliases[mod] or mod)
    for _, it in ipairs(d and mod and d.modules[mod] and d.modules[mod][2] or {}) do
      if it[1] == word then info = { sig = it[2], text = it[3], lang = "python" } end
    end
  end
  if not info then
    local ok = pcall(vim.cmd, "normal! K")
    if not ok then vim.notify("「" .. word .. "」の説明は見つかりませんでした") end
    return
  end
  local d = doc(info.lang, info.sig, info.note, info.text)
  vim.lsp.util.open_floating_preview(vim.split(d.value, "\n"), "markdown", { border = "rounded", focus_id = "offline_hover" })
end

-- ===== 引数の表示 (関数名( を打ったとき) =====
local sig_ns = api.nvim_create_namespace("offline_signature")
local sig = { win = nil, buf = nil }

local function sig_close()
  if sig.win and api.nvim_win_is_valid(sig.win) then pcall(api.nvim_win_close, sig.win, true) end
  sig.win = nil
end

-- カーソルの前から、まだ閉じていない ( を探し、関数名と、今が何番目の引数かを返す
local function call_at_cursor(before)
  local depth, commas = 0, 0
  local in_str = false
  -- 文字列の中のカンマやカッコは数えない (簡易: " の数で判定)
  local cleaned = before:gsub('\\"', "  "):gsub("'.'", "   ")
  for i = #cleaned, 1, -1 do
    local ch = cleaned:sub(i, i)
    if ch == '"' then
      in_str = not in_str
    elseif not in_str then
      if ch == ")" or ch == "]" or ch == "}" then
        depth = depth + 1
      elseif ch == "(" or ch == "[" or ch == "{" then
        if depth == 0 then
          if ch ~= "(" then return nil end
          local name = cleaned:sub(1, i - 1):match("([%a_][%w_]*)%s*$")
          return name, commas
        end
        depth = depth - 1
      elseif ch == "," and depth == 0 then
        commas = commas + 1
      end
    end
  end
  return nil
end

-- 宣言の中の、n 番目 (0 始まり) の引数の範囲 (バイト位置。0 始まり・終わりは含まない)
local function param_range(text, n)
  local open = text:find("(", 1, true)
  if not open then return nil end
  local depth, start, idx = 0, open + 1, 0
  for i = open + 1, #text do
    local ch = text:sub(i, i)
    if ch == "(" or ch == "[" then
      depth = depth + 1
    elseif (ch == ")" or ch == "]") and depth > 0 then
      depth = depth - 1
    elseif (ch == "," or ch == ")") and depth == 0 then
      if idx == n or (ch == ")" and text:sub(start, i - 1):find("%.%.%.") ) then
        local s = start
        while text:sub(s, s) == " " do s = s + 1 end
        if s > i - 1 then return nil end
        return s - 1, i - 1
      end
      if ch == ")" then return nil end
      idx, start = idx + 1, i + 1
    end
  end
  return nil
end

local function sig_update()
  local buf = api.nvim_get_current_buf()
  if not LANG[vim.bo[buf].filetype] or vim.bo[buf].buftype ~= "" or has_lsp(buf, "signatureHelpProvider") then
    return sig_close()
  end
  local col = api.nvim_win_get_cursor(0)[2]
  local name, index = call_at_cursor(api.nvim_get_current_line():sub(1, col))
  local info = name and M.lookup(buf, name)
  if not info or not info.sig:find("(", 1, true) then return sig_close() end
  local text = " " .. info.sig:gsub("^def ", ""):gsub("^#define ", "") .. " "
  -- Python のメソッドは、self を除いて数える
  if text:find("%(%s*self%s*,") then index = index + 1 end
  if not (sig.buf and api.nvim_buf_is_valid(sig.buf)) then
    sig.buf = api.nvim_create_buf(false, true)
    vim.bo[sig.buf].bufhidden = "hide"
  end
  api.nvim_buf_set_lines(sig.buf, 0, -1, false, { text })
  api.nvim_buf_clear_namespace(sig.buf, sig_ns, 0, -1)
  local s, e = param_range(text, index)
  if s then
    pcall(api.nvim_buf_set_extmark, sig.buf, sig_ns, 0, s, { end_col = e, hl_group = "LspSignatureActiveParameter" })
  end
  local width = math.min(vim.fn.strdisplaywidth(text), math.max(vim.o.columns - 4, 20))
  -- カーソルの上に出す (補完の一覧は下に出るので、重ならない)。画面の上端では下に出す
  local above = vim.fn.winline() > 3
  local cfg = {
    relative = "cursor", row = above and -3 or 1, col = 0, width = width, height = 1,
    style = "minimal", border = "rounded", focusable = false, zindex = 60,
  }
  if sig.win and api.nvim_win_is_valid(sig.win) then
    pcall(api.nvim_win_set_config, sig.win, cfg)
  else
    cfg.noautocmd = true
    local ok, win = pcall(api.nvim_open_win, sig.buf, false, cfg)
    if not ok then return end
    sig.win = win
    vim.wo[win].wrap = false
  end
end

-- ===== gd: 定義へ移動 =====
--   LSP があれば LSP、無ければ自分のコードの中 (C は読み込んでいる自分のヘッダも) から探す。
--   見つからなければ Vim 本来の gd (関数の中の宣言へ)
local function where(buf, name)
  local lang = LANG[vim.bo[buf].filetype]
  if lang == "c" then return (c_symbols(buf)).where[name] end
  if lang == "python" then return py_scan(buf).where[name] end
  return nil
end

function M.goto_definition()
  local buf = api.nvim_get_current_buf()
  if has_lsp(buf, "definitionProvider") then return vim.lsp.buf.definition() end
  local word = vim.fn.expand("<cword>")
  local ok, w = pcall(where, buf, word)
  if not ok or not w then return pcall(vim.cmd, "normal! gd") end
  -- ヘッダにあるのがプロトタイプ宣言だけなら、同じ名前の .c / .cpp にある本体を探す (list.h → list.c)
  if w.file and w.proto then
    for _, ext in ipairs({ ".c", ".cpp", ".cc" }) do
      local src = w.file:gsub("%.[^./\\]+$", "") .. ext
      local st = vim.uv.fs_stat(src)
      if st and st.type == "file" and st.size < 512 * 1024 then
        local read_ok, lines = pcall(vim.fn.readfile, src)
        local sym = new_sym()
        if read_ok and pcall(scan_c, lines, sym, src) and sym.where[word] and not sym.where[word].proto then
          w = sym.where[word]
          break
        end
      end
    end
  end
  vim.cmd("normal! m'") -- Ctrl-o で元の場所に戻れるようにする
  if w.file and vim.fs.normalize(api.nvim_buf_get_name(buf)) ~= w.file then
    local opened = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(w.file))
    if not opened then return vim.notify("ファイルを開けませんでした: " .. w.file, vim.log.levels.WARN) end
  end
  local line = math.min(w.line, api.nvim_buf_line_count(0))
  local col = (api.nvim_buf_get_lines(0, line - 1, line, false)[1] or ""):find(word, 1, true)
  api.nvim_win_set_cursor(0, { line, (col or 1) - 1 })
  vim.cmd("normal! zz")
end

-- ===== grn: 名前の変更 =====
--   LSP があれば LSP (プロジェクト全体・正確)。無ければ、今のファイルの中の同じ単語をすべて置き換える
function M.rename()
  local buf = api.nvim_get_current_buf()
  if has_lsp(buf, "renameProvider") then return vim.lsp.buf.rename() end
  local old = vim.fn.expand("<cword>")
  if old == "" or not old:match("^[%a_][%w_]*$") then return vim.notify("名前の上にカーソルを置いてください") end
  vim.ui.input({ prompt = "新しい名前 (このファイル内の " .. old .. " をすべて変更): ", default = old }, function(new)
    if not new or new == "" or new == old then return end
    if not new:match("^[%a_][%w_]*$") then return vim.notify("名前に使えない文字が入っています: " .. new, vim.log.levels.WARN) end
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local count, changed = 0, {}
    for i, l in ipairs(lines) do
      local replaced, n = l:gsub("%f[%w_]" .. old .. "%f[^%w_]", new)
      if n > 0 then
        count = count + n
        changed[#changed + 1] = { i, replaced }
      end
    end
    for _, c in ipairs(changed) do api.nvim_buf_set_lines(buf, c[1] - 1, c[1], false, { c[2] }) end
    vim.notify(("%s → %s: %d か所を変更しました (文字列やコメントの中も含みます。戻すには u)"):format(old, new, count))
  end)
end

-- ===== 関数などの一覧 (LSP も構文解析も無いとき用) =====
function M.outline()
  local buf = api.nvim_get_current_buf()
  local lang = LANG[vim.bo[buf].filetype]
  if not lang then return vim.notify("この種類のファイルの一覧は作れません") end
  local sym = lang == "c" and (c_symbols(buf)) or py_scan(buf)
  local list = {}
  for name, w in pairs(sym.where) do
    if not w.file then
      local f = sym.funcs[name] or (sym.methods and sym.methods[name])
      local text = f and f.sig or (sym.classes and sym.classes[name])
        or (sym.macros and sym.macros[name] and ("#define " .. name)) or name
      list[#list + 1] = { line = w.line, text = text }
    end
  end
  if #list == 0 then return vim.notify("このファイルに、関数や型の定義は見つかりませんでした") end
  table.sort(list, function(a, b) return a.line < b.line end)
  vim.ui.select(list, {
    prompt = "関数などの一覧",
    format_item = function(it) return ("%4d  %s"):format(it.line, it.text) end,
  }, function(it)
    if not it then return end
    vim.cmd("normal! m'")
    api.nvim_win_set_cursor(0, { it.line, 0 })
    vim.cmd("normal! zz")
  end)
end

function M.setup()
  local group = api.nvim_create_augroup("offline_cmp", { clear = true })
  api.nvim_create_autocmd({ "TextChangedI", "CursorMovedI", "InsertEnter" }, {
    group = group,
    callback = function()
      local ok = pcall(sig_update)
      if not ok then sig_close() end
    end,
  })
  api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "WinLeave" }, { group = group, callback = sig_close })
  api.nvim_create_autocmd("BufWipeout", { group = group, callback = function(ev) sym_cache[ev.buf] = nil end })
  api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "c", "cpp", "python" },
    callback = function(ev)
      vim.keymap.set("n", "K", M.hover, { buffer = ev.buf, desc = "説明を表示 (LSP が無ければ辞書)" })
      vim.keymap.set("n", "gd", M.goto_definition, { buffer = ev.buf, desc = "定義へ (LSP が無ければ自分のコードから探す)" })
      vim.keymap.set("n", "grn", M.rename, { buffer = ev.buf, desc = "名前の変更 (LSP が無ければ、このファイル内)" })
    end,
  })
end

-- テスト用
M._internal = { scan_c = scan_c, new_sym = new_sym, call_at_cursor = call_at_cursor, param_range = param_range, member_chain = member_chain }

return M
