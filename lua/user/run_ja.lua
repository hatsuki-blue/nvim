-- 実行したとき (Space r) のエラーを、日本語で説明する
--   * Python の例外 (NameError など)、C / C++ の異常終了 (Segmentation fault など)、
--     コンパイルエラー (gcc の英語のメッセージ) が対象
--   * 対応表で置き換えるだけ。表にないものは何も出さない (元のメッセージはそのまま画面に残る)
local M = {}

-- ===== Python の例外 =====
-- { 例外の名前, 内容のパターン, 説明 }。{1} {2} … にパターンの ( ) の中身が入る
local py = {
  { "NameError", "^name '(.-)' is not defined", "'{1}' という名前は定義されていません (書き間違い、または定義する前に使っています)" },
  { "UnboundLocalError", "'(.-)'", "関数の中で、変数 '{1}' に値を入れる前に使っています (関数の外の変数を書き換えるなら global が必要)" },
  { "ZeroDivisionError", "", "0 で割りました" },
  { "IndexError", "^list index out of range", "リストの範囲外の番号を指定しました (番号は 0 から「長さ - 1」まで)" },
  { "IndexError", "^string index out of range", "文字列の範囲外の番号を指定しました (番号は 0 から「長さ - 1」まで)" },
  { "IndexError", "^pop from empty list", "空のリストから pop しようとしました" },
  { "IndexError", "", "範囲外の番号を指定しました" },
  { "KeyError", "^(.*)$", "辞書に {1} というキーはありません" },
  { "TypeError", "^unsupported operand type%(s%) for (.-): '(.-)' and '(.-)'", "{2} と {3} は {1} で計算できません (int() や str() で型をそろえます)" },
  { "TypeError", '^can only concatenate str %(not "(.-)"%) to str', "文字列と {1} は + でつなげられません (str() で文字列にします)" },
  { "TypeError", "^'(.-)' object is not iterable", "{1} は for などで繰り返せません" },
  { "TypeError", "^'(.-)' object is not subscriptable", "{1} には [ ] を使えません" },
  { "TypeError", "^'(.-)' object is not callable", "{1} は関数ではないので、( ) を付けて呼び出せません (関数と同じ名前の変数を作っていませんか)" },
  { "TypeError", "^'(.-)' object cannot be interpreted as an integer", "整数が必要なところに {1} を渡しています (range() などは整数だけ)" },
  { "TypeError", "^'(.-)' not supported between instances of '(.-)' and '(.-)'", "{2} と {3} は {1} で比べられません (型をそろえます)" },
  { "TypeError", "^(.-) missing (%d+) required positional arguments?: (.*)$", "{1} の引数が {2} 個足りません ({3})" },
  { "TypeError", "^(.-) takes (%d+) positional arguments? but (%d+) w%a+ given", "{1} の引数は {2} 個ですが、{3} 個渡しています" },
  { "TypeError", "^(.-) got an unexpected keyword argument '(.-)'", "{1} に '{2}' という名前の引数はありません" },
  { "TypeError", "^list indices must be integers or slices, not (%a+)", "リストの番号は整数で指定します ({1} は使えません)" },
  { "TypeError", "^string indices must be integers", "文字列の番号は整数で指定します" },
  { "TypeError", "^object of type '(.-)' has no len%(%)", "{1} には長さがありません (len() は使えません)" },
  { "TypeError", "", "型が合っていません" },
  { "ValueError", "^invalid literal for int%(%) with base (%d+): (.*)$", "{2} は整数に変換できません (数字以外が入っています)" },
  { "ValueError", "^could not convert string to float: (.*)$", "{1} は実数に変換できません" },
  { "ValueError", "^not enough values to unpack %(expected (%d+), got (%d+)%)", "値が足りません (変数は {1} 個ですが、値は {2} 個です。入力の個数を確認します)" },
  { "ValueError", "^too many values to unpack %(expected (%d+)", "値が多すぎます (変数は {1} 個です)" },
  { "ValueError", "^math domain error", "計算できない値です (負の数の平方根、0 以下の対数など)" },
  { "ValueError", "is not in list", "その値はリストの中にありません" },
  { "ValueError", "", "値が正しくありません" },
  { "AttributeError", "^'NoneType' object has no attribute '(.-)'", "None に対して .{1} を使っています (戻り値のない関数の結果を使っていませんか。例: a = a.sort())" },
  { "AttributeError", "^'(.-)' object has no attribute '(.-)'", "{1} に '{2}' という属性・メソッドはありません (書き間違い?)" },
  { "AttributeError", "^module '(.-)' has no attribute '(.-)'", "モジュール {1} に '{2}' はありません (書き間違い、または同じ名前の自分のファイルがあります)" },
  { "ModuleNotFoundError", "^No module named '(.-)'", "モジュール '{1}' が見つかりません (書き間違い、または pip install {1} が必要)" },
  { "ImportError", "^cannot import name '(.-)' from '(.-)'", "{2} から '{1}' を読み込めません (書き間違い?)" },
  { "FileNotFoundError", "No such file or directory: (.*)$", "ファイル {1} が見つかりません (名前と場所を確認します。実行は、プログラムのあるフォルダで行われます)" },
  { "PermissionError", "", "そのファイル・フォルダを読み書きする権限がありません" },
  { "IsADirectoryError", "", "ファイルではなくフォルダを開こうとしました" },
  { "RecursionError", "", "再帰が深すぎます (終了条件が無い、または正しくない可能性があります)" },
  { "EOFError", "", "入力が足りません (input() で読むものが、もうありません)" },
  { "KeyboardInterrupt", "", "Ctrl-C で止めました" },
  { "IndentationError", "^(.*)$", nil }, -- 構文エラーは diag_ja の表を使う
  { "TabError", "^(.*)$", nil },
  { "SyntaxError", "^(.*)$", nil },
  { "OverflowError", "", "数が大きすぎて扱えません" },
  { "MemoryError", "", "メモリが足りません (リストが大きすぎる、または無限に増え続けています)" },
  { "AssertionError", "", "assert の条件が成り立ちませんでした" },
  { "StopIteration", "", "次の値がもうありません (next() の呼びすぎ)" },
  { "UnicodeDecodeError", "", "ファイルの文字コードが違います (open(..., encoding=\"utf-8\") か \"cp932\" を指定します)" },
  { "UnicodeEncodeError", "", "その文字コードでは表せない文字があります" },
  { "NotImplementedError", "", "まだ実装されていない機能です" },
  { "RuntimeError", "^dictionary changed size during iteration", "辞書を for で回している途中で、その辞書の要素を増減させました" },
}

local function fill(tpl, caps)
  return (tpl:gsub("{(%d)}", function(n) return caps[tonumber(n)] or "" end))
end

local function python_error(name, msg)
  local diag_ja = require("user.diag_ja")
  for _, r in ipairs(py) do
    if r[1] == name then
      local caps = { msg:match(r[2]) }
      if #caps > 0 then
        if r[3] == nil then return diag_ja.translate(msg) end
        return fill(r[3], caps)
      end
    end
  end
  return nil
end

-- ===== C / C++ の異常終了 =====
-- { 出力に含まれる文字 (パターン), 説明 }
local crashes = {
  { "[Ss]egmentation fault", "メモリの不正なアクセスで止まりました (Segmentation fault)。よくある原因: 配列の範囲外・scanf の & 忘れ・NULL や初期化していないポインタの使用・止まらない再帰" },
  { "stack smashing detected", "配列の範囲の外に書き込みました (配列の大きさと、ループの回数・入力の長さを確認します)" },
  { "[Ff]loating point exception", "整数を 0 で割りました (割り算・余りの計算の、割る数を確認します)" },
  { "double free or corruption", "同じメモリを2回 free した、または確保した範囲の外に書き込みました" },
  { "free%(%): invalid pointer", "malloc で確保していないものを free しました" },
  { "malloc%(%): ", "確保したメモリの範囲の外に書き込んだ可能性があります (malloc の大きさを確認します)" },
  { "corrupted size vs%. prev_size", "確保したメモリの範囲の外に書き込んだ可能性があります (malloc の大きさを確認します)" },
  { "terminate called after throwing an instance of 'std::out_of_range'", "範囲外の番号を指定しました (vector の at() や string の substr() など)" },
  { "terminate called after throwing an instance of 'std::bad_alloc'", "メモリを確保できませんでした (大きさの指定が大きすぎる、または負の数になっています)" },
  { "terminate called after throwing an instance of 'std::invalid_argument'", "変換できない値です (stoi などに、数字ではない文字列を渡しています)" },
  { "terminate called", "C++ の例外が起きて止まりました" },
  { "[Bb]us error", "メモリの不正なアクセスで止まりました (Bus error)" },
  { "Assertion .* failed", "assert の条件が成り立たずに止まりました" },
  { "Aborted", "異常終了しました (Aborted)" },
  { "undefined reference to [`'](.-)'", "関数 '{1}' の本体が見つかりません (名前の書き間違い、または別のファイルにある関数です)" },
  { "ld returned 1 exit status", nil },
}

-- 終了コードから (メッセージが出ない環境用)。Windows の値も含む
local exit_codes = {
  [139] = crashes[1][2], [136] = crashes[3][2], [134] = "異常終了しました (Aborted)",
  [-1073741819] = crashes[1][2], [3221225477] = crashes[1][2],
  [-1073741676] = crashes[3][2], [3221225620] = crashes[3][2],
  [-1073741571] = "スタックがあふれました (止まらない再帰、または関数の中の配列が大きすぎます)",
  [3221225725] = "スタックがあふれました (止まらない再帰、または関数の中の配列が大きすぎます)",
}

-- 実行結果 (ターミナルの行) を調べる
--   lines: 出力の行、file: 実行したファイルのフルパス、status: 終了コード
--   戻り値: { text = { 説明の行… }, marks = { { line = 行番号, message = 説明 }… } } / 何も無ければ nil
--   marks (ソースの行に付ける印) は、実行中に起きたエラーだけ。コンパイルエラーは、編集中の表示と重なるので付けない
function M.explain(lines, file, status)
  local diag_ja = require("user.diag_ja")
  local text, marks = {}, {}
  local base = vim.fn.fnamemodify(file, ":t")
  -- gcc は、日本語などの環境では引用符を ‘ ’ で出すので、' にそろえる
  local function ascii_quotes(str) return (str:gsub("‘", "'"):gsub("’", "'")) end
  local output = ascii_quotes(table.concat(lines, "\n"))

  -- コンパイルエラー: "ファイル:行:列: error: 内容" (gcc / clang)
  local seen = 0
  for _, l in ipairs(lines) do
    local f, ln, kind, msg = l:match("^(.-):(%d+):%d+: (%a[%a ]*): (.*)$")
    if not f then f, ln, kind, msg = l:match("^(.-):(%d+): (%a[%a ]*): (.*)$") end
    if f and (kind == "error" or kind == "fatal error" or kind == "warning") then
      msg = ascii_quotes(msg)
      local ja = diag_ja.translate(msg)
      if ja and seen < 6 then
        seen = seen + 1
        local here = vim.fn.fnamemodify(f, ":t") == base
        text[#text + 1] = ("%s%s 行目: %s"):format(here and "" or (vim.fn.fnamemodify(f, ":t") .. " の "), ln, ja)
      end
    end
  end

  -- Python の例外: 最後の "名前: 内容" の行と、その前の 'File "…", line N'
  local err_name, err_msg, err_line
  for i = #lines, 1, -1 do
    local name, msg = lines[i]:match("^([%a_][%w_%.]*Error): ?(.*)$")
    if not name then name = lines[i]:match("^(KeyboardInterrupt)%s*$") or lines[i]:match("^([%a_][%w_%.]*Error)%s*$") end
    if not name then name, msg = lines[i]:match("^(StopIteration):? ?(.*)$") end
    if name then
      err_name, err_msg = name:match("[%w_]+$"), msg or ""
      for j = i - 1, math.max(1, i - 40), -1 do
        local f, ln = lines[j]:match('^%s*File "(.-)", line (%d+)')
        if f and (vim.fn.fnamemodify(f, ":t") == base) then
          err_line = tonumber(ln)
          break
        end
      end
      break
    end
  end
  if err_name then
    local ja = python_error(err_name, err_msg)
    if ja then
      text[#text + 1] = (err_line and (err_line .. " 行目: ") or "") .. ja
      -- 構文エラーは、編集中の表示 (py_check や LSP) がすでに印を付けているので、重ねない
      local syntax = err_name == "SyntaxError" or err_name == "IndentationError" or err_name == "TabError"
      if err_line and not syntax then marks[#marks + 1] = { line = err_line, message = ja } end
    end
  end

  -- C / C++ の異常終了
  if #text == 0 or status ~= 0 then
    local found = false
    for _, c in ipairs(crashes) do
      local caps = { output:match(c[1]) }
      if #caps > 0 then
        found = true
        if c[2] then text[#text + 1] = fill(c[2], caps) end
        break
      end
    end
    if not found and #text == 0 and exit_codes[status] then text[#text + 1] = exit_codes[status] end
  end

  if #text == 0 then return nil end
  return { text = text, marks = marks }
end

return M
