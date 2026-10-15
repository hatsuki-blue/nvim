-- エラー / 警告の文章を日本語にする (対応表で置き換えるだけ。AI や通信は使わない)
--   * 日本語のメッセージを持たない clangd (C/C++) と Ruff (Python) のよく出るものを訳す
--   * 表にないものは英語のまま
--   * Pyright (Python)・TypeScript・lua_ls は、ツール自身の日本語版を使う (init.lua で設定)
local M = {}

local rules = {}
-- pat: Lua のパターン (^...$ で全体一致)。rep: 訳文。{1} {2} … にキャプチャが入る
local function add(pat, rep) table.insert(rules, { pat, rep }) end

-- ===== clangd (C / C++) =====
-- ; や カッコ
add("^Expected ';' at end of declaration$", "宣言の最後に ';' がありません")
add("^Expected ';' after expression$", "式の後に ';' がありません")
add("^Expected ';' after return statement$", "return の後に ';' がありません")
add("^Expected ';' after do/while statement$", "do-while の後に ';' がありません")
add("^Expected ';' after top level declarator$", "宣言の後に ';' がありません")
add("^Expected ';' after (.-)$", "{1} の後に ';' がありません")
add("^Expected ';' in '(.-)'$", "'{1}' の中に ';' がありません")
-- ※'([^']+)' と書いて引用符の中だけに一致させる ('(.-)' だと gcc の
--   "expected ',' or ';' before 'x'" 全体に一致して誤訳になる)
add("^Expected '([^']+)' after '([^']+)'$", "'{2}' の後に '{1}' がありません")
add("^Expected '([^']+)'$", "'{1}' がありません (閉じ忘れ・書き忘れ)")
add("^Expected expression$", "式がありません (書きかけ、または余分な記号があります)")
add("^Expected statement$", "文がありません (余分な記号や、カッコの対応を確認してください)")
add("^Expected identifier or '%('$", "名前 (識別子) がありません")
add("^Expected identifier$", "名前 (識別子) がありません")
add("^Expected parameter declarator$", "引数の宣言が正しくありません")
add("^Expected function body after function declarator$", "関数の宣言の後に本体 { } がありません")
add('^Expected "FILENAME" or <FILENAME>$', '#include の後に "ファイル名" か <ファイル名> がありません')
add("^Extraneous closing brace %('}'%)$", "閉じカッコ '}' が多すぎます")
add("^Extraneous '(.-)' before '(.-)'$", "'{2}' の前に余分な '{1}' があります")
add("^Missing terminating '(.-)' character$", "閉じの {1} がありません (文字列・文字が閉じていません)")
add("^Unterminated /%* comment$", "コメントの /* が閉じていません")
add("^Function definition is not allowed here$", "ここでは関数を定義できません (関数の中に書いている、または } の閉じ忘れ)")
add("^Empty character constant$", "文字定数 '' が空です")
add("^Multi%-character character constant$", "文字定数 ' ' に複数の文字が入っています (文字列なら \" \" を使います)")

-- ヘッダ / 宣言
add("^'(.-)' file not found$", "ヘッダファイル '{1}' が見つかりません")
add("^Included header (.-) is not used directly$", "ヘッダ {1} はこのファイルで直接使われていません")
add("^Use of undeclared identifier '(.-)'; did you mean '(.-)'%?$", "'{1}' は宣言されていません ('{2}' の書き間違い?)")
add("^Use of undeclared identifier '(.-)'$", "'{1}' は宣言されていません (宣言忘れ・書き間違い)")
add("^Call to undeclared library function '(.-)' with type .*$", "ライブラリ関数 '{1}' が宣言されていません (#include を確認してください)")
add("^Call to undeclared function '(.-)'.*$", "関数 '{1}' が宣言されていません (関数の宣言・#include を確認してください)")
add("^Implicitly declaring library function '(.-)' with type .*$", "ライブラリ関数 '{1}' が宣言されていません (#include を確認してください)")
add("^Unknown type name '(.-)'$", "'{1}' という型はありません (書き間違い・#include 忘れ)")
add("^Redefinition of '(.-)' with a different type: .*$", "'{1}' が別の型で定義し直されています (同じ名前の宣言が2つあります)")
add("^Redefinition of '(.-)'$", "'{1}' が2回定義されています")
add("^Conflicting types for '(.-)'$", "'{1}' の型が、前の宣言と食い違っています")
add("^Type specifier missing, defaults to 'int'.*$", "型の指定がありません")
add("^Variable has incomplete type '(.-)'$", "型 '{1}' の定義が見つかりません")
add("^Declaration shadows a local variable$", "外側にある同じ名前の変数を隠しています")

-- 関数 / 引数 / 戻り値
add("^Too few arguments to function call, expected (%d+), have (%d+)$", "関数の引数が足りません ({1} 個必要ですが {2} 個です)")
add("^Too many arguments to function call, expected (%d+), have (%d+)$", "関数の引数が多すぎます ({1} 個必要ですが {2} 個です)")
add("^Too few arguments to function call, single argument '(.-)' was not specified$", "関数の引数 '{1}' がありません")
add("^Non%-void function does not return a value in all control paths$", "値を返さずに終わる場合があります (すべての分岐で return が必要です)")
add("^Non%-void function does not return a value$", "戻り値のある関数なのに、値を return していません")
add("^Void function '(.-)' should not return a value$", "void 関数 '{1}' は値を返せません")
add("^Address of stack memory associated with local variable '(.-)' returned$", "ローカル変数 '{1}' のアドレスを返しています (関数を抜けると無効になります)")

-- 型 / 変換
add("^Incompatible integer to pointer conversion %a+ '(.-)' with an expression of type '(.-)'$", "整数 ({2}) をポインタ ({1}) として使っています")
add("^Incompatible pointer to integer conversion %a+ '(.-)' with an expression of type '(.-)'$", "ポインタ ({2}) を整数 ({1}) として使っています")
add("^Incompatible pointer types %a+ '(.-)' with an expression of type '(.-)'$", "ポインタの型が合いません ({1} に {2} を使っています)")
add("^Incompatible pointer types .*$", "ポインタの型が合いません")
add("^Assigning to '(.-)' from incompatible type '(.-)'$", "'{1}' に、型の合わない '{2}' を代入しています")
add("^Initializing '(.-)' with an expression of incompatible type '(.-)'$", "'{1}' を、型の合わない '{2}' で初期化しています")
add("^Returning '(.-)' from a function with incompatible result type '(.-)'$", "戻り値の型 '{2}' に合わない '{1}' を返しています")
add("^Passing '(.-)' to parameter of incompatible type '(.-)'$", "引数の型が合いません ('{2}' に '{1}' を渡しています)")
add("^Implicit conversion from '(.-)' to '(.-)' changes value from (.-) to (.-)$", "'{1}' から '{2}' への変換で値が変わります ({3} → {4})")
add("^Implicit conversion loses %a+%-?%a* precision: '(.-)' to '(.-)'$", "'{1}' から '{2}' への変換で精度が落ちます")
add("^Comparison of integers of different signs: '(.-)' and '(.-)'$", "符号の異なる整数を比較しています ('{1}' と '{2}')")
add("^Expression is not assignable$", "この式には代入できません")
add("^Cannot assign to variable '(.-)' with const%-qualified type '(.-)'$", "const の変数 '{1}' には代入できません")
add("^Read%-only variable is not assignable$", "読み取り専用の変数には代入できません")

-- 配列 / ポインタ / 構造体
add("^Excess elements in array initializer$", "配列の初期値が、配列の大きさより多すぎます")
add("^Excess elements in scalar initializer$", "初期値が多すぎます")
add("^Array index (%-?%d+) is past the end of the array %(that has type '(.-)'%)$", "添字 {1} は配列 ({2}) の範囲外です")
add("^Array index (%-?%d+) is before the beginning of the array$", "添字 {1} は配列の範囲外 (先頭より前) です")
add("^Subscripted value is not an array, pointer, or vector$", "配列やポインタではないものに [ ] を使っています")
add("^Indirection requires pointer operand %('(.-)' invalid%)$", "ポインタではない '{1}' に * を使っています")
add("^No member named '(.-)' in '(.-)'$", "'{2}' に '{1}' というメンバはありません")
add("^Member reference type '(.-)' is a pointer; did you mean to use '%->'%?$", "'{1}' はポインタです。'.' ではなく '->' を使います")
add("^Member reference type '(.-)' is not a pointer; did you mean to use '%.'%?$", "'{1}' はポインタではありません。'->' ではなく '.' を使います")
add("^Member reference base type '(.-)' is not a structure or union$", "'{1}' は構造体ではないので . や -> は使えません")

-- printf / scanf の書式
add("^Format specifies type '(.-)' but the argument has type '(.-)'$", "書式は '{1}' 型ですが、引数は '{2}' 型です (%d・%f などを確認)")
add("^Format specifies type '(.-)' but the argument has underlying type '(.-)'$", "書式は '{1}' 型ですが、引数は '{2}' 型です")
add("^More '%%' conversions than data arguments$", "書式の % の数に対して、引数が足りません")
add("^Data argument not used by format string$", "書式で使われない引数があります (% が足りません)")
add("^Invalid conversion specifier '(.-)'$", "'%{1}' は使えない書式です")
add("^Format string is not a string literal.*$", "書式が文字列リテラルではありません (安全でない可能性があります)")

-- よくある書き間違い / その他
add("^Using the result of an assignment as a condition without parentheses$", "条件の中で代入 (=) をしています。比較なら == を使います")
add("^Expression result unused$", "式の結果が使われていません (この行は何もしていません)")
add("^Unused variable '(.-)'$", "変数 '{1}' は使われていません")
add("^Unused parameter '(.-)'$", "引数 '{1}' は使われていません")
add("^Unused function '(.-)'$", "関数 '{1}' は使われていません")
add("^Unused label '(.-)'$", "ラベル '{1}' は使われていません")
add("^Variable '(.-)' is uninitialized when used here$", "変数 '{1}' に値を入れる前に使っています")
add("^Variable '(.-)' is used uninitialized whenever .*$", "変数 '{1}' が、値を入れないまま使われる場合があります")
add("^Division by zero is undefined$", "0 で割っています")
add("^Remainder by zero is undefined$", "0 で割った余りを求めています")
add("^Code will never be executed$", "このコードは実行されることがありません")
add("^No newline at end of file$", "ファイルの最後に改行がありません")
add("^Invalid preprocessing directive$", "不正なプリプロセッサ命令です (#include などのつづりを確認)")
add("^Unterminated conditional directive$", "#if / #ifdef に対応する #endif がありません")

-- ===== gcc (clangd が無い環境で、user/c_check.lua が使う) =====
-- ; や カッコ
add("^Expected '(.-)' or '(.-)' before '(.-)' token$", "'{3}' の前に '{1}' か '{2}' がありません (前の行の ; 抜けなど)")
add("^Expected '(.-)' or '(.-)' before '(.-)'$", "'{3}' の前に '{1}' か '{2}' がありません (前の行の ; 抜けなど)")
add("^Expected expression before '(.-)' token$", "'{1}' の前に式がありません (書きかけ、または余分な記号があります)")
add("^Expected expression before '(.-)'$", "'{1}' の前に式がありません (書きかけ、または余分な記号があります)")
add("^Expected identifier or '%(' before '(.-)' token$", "'{1}' の前に名前 (識別子) がありません")
add("^Expected identifier or '%(' before '(.-)'$", "'{1}' の前に名前 (識別子) がありません")
add("^Expected '(.-)' before '(.-)' token$", "'{2}' の前に '{1}' がありません")
add("^Expected '(.-)' before '(.-)'$", "'{2}' の前に '{1}' がありません")
add("^Expected declaration or statement at end of input$", "ファイルが途中で終わっています (} の閉じ忘れ)")
add("^Missing terminating (.) character$", "閉じの {1} がありません (文字列・文字が閉じていません)")
add("^Stray '(.-)' in program$", "使えない文字が入っています (全角スペースや全角の記号など)")
-- 宣言 / 関数
add("^'(.-)' undeclared %(first use in this function%)$", "'{1}' は宣言されていません (宣言忘れ・書き間違い)")
add("^'(.-)' undeclared here %(not in a function%)$", "'{1}' は宣言されていません (宣言忘れ・書き間違い)")
add("^'(.-)' redeclared as different kind of symbol$", "'{1}' が、別の種類として宣言し直されています")
add("^Implicit declaration of function '(.-)'$", "関数 '{1}' が宣言されていません (関数の宣言・#include を確認してください)")
add("^Too few arguments to function '(.-)'$", "関数 '{1}' の引数が足りません")
add("^Too many arguments to function '(.-)'$", "関数 '{1}' の引数が多すぎます")
add("^Passing argument (%d+) of '(.-)' .*$", "関数 '{2}' の {1} 番目の引数の型が合いません")
add("^Return type defaults to 'int'$", "戻り値の型が書かれていません (int とみなします)")
add("^'return' with no value, in function returning non%-void$", "戻り値のある関数で、値のない return をしています")
add("^Control reaches end of non%-void function$", "戻り値のある関数なのに、最後まで return がありません")
add("^Function returns address of local variable$", "ローカル変数のアドレスを返しています (関数を抜けると無効になります)")
add("^(.-): No such file or directory$", "ヘッダファイル '{1}' が見つかりません")
-- 型 / 変換
add("^Initialization of '(.-)' from '(.-)' makes pointer from integer without a cast$", "整数 ({2}) をポインタ ({1}) として使っています")
add("^Assignment to '(.-)' from '(.-)' makes pointer from integer without a cast$", "整数 ({2}) をポインタ ({1}) として使っています")
add("^Initialization of '(.-)' from '(.-)' makes integer from pointer without a cast$", "ポインタ ({2}) を整数 ({1}) として使っています")
add("^Assignment to '(.-)' from '(.-)' makes integer from pointer without a cast$", "ポインタ ({2}) を整数 ({1}) として使っています")
add("^Initialization of '(.-)' from incompatible pointer type '(.-)'$", "ポインタの型が合いません ({1} に {2} を使っています)")
add("^Assignment to '(.-)' from incompatible pointer type '(.-)'$", "ポインタの型が合いません ({1} に {2} を使っています)")
add("^Comparison of integer expressions of different signedness: '(.-)' and '(.-)'$", "符号の異なる整数を比較しています ('{1}' と '{2}')")
add("^Lvalue required as left operand of assignment$", "代入の左側に、代入できないもの (数値など) があります")
-- 配列
add("^Array subscript (%-?%d+) is above array bounds of '(.-)'$", "添字 {1} は配列 ({2}) の範囲外です")
add("^Subscripted value is neither array nor pointer nor vector$", "配列やポインタではないものに [ ] を使っています")
-- printf の書式
add("^Format '(.-)' expects argument of type '(.-)', but argument (%d+) has type '(.-)'$", "書式 '{1}' は '{2}' 型を受け取りますが、{3} 番目の引数は '{4}' 型です")
add("^Format '(.-)' expects a matching '(.-)' argument$", "書式 '{1}' に対応する引数がありません ('{2}' 型が必要)")
add("^Too many arguments for format$", "書式に対して、引数が多すぎます")
-- よくある書き間違い
add("^Suggest parentheses around assignment used as truth value$", "条件の中で代入 (=) をしています。比較なら == を使います")
add("^Statement with no effect$", "この文は何もしていません")
add("^Variable '(.-)' set but not used$", "変数 '{1}' に値を入れていますが、使われていません")
add("^'(.-)' is used uninitialized$", "変数 '{1}' に値を入れる前に使っています")
add("^Division by zero$", "0 で割っています")

-- ===== Ruff (Python) =====
add("^Expected an indented block after function definition$", "関数定義の後に、字下げしたブロックが必要です")
add("^Expected an indented block after (.-)$", "{1} の後に、字下げしたブロックが必要です")
add("^[Uu]nexpected EOF while parsing$", "ファイルが途中で終わっています (カッコや引用符の閉じ忘れ)")
add("^Unexpected indentation$", "予期しない字下げがあります")
add("^Expected (.-), found (.-)$", "{1} が必要ですが、{2} があります")
add("^Simple statements must be separated by newlines or semicolons$", "文は改行かセミコロンで区切ってください")
add("^`(.-)` imported but unused$", "`{1}` はインポートされていますが使われていません")
add("^Undefined name `(.-)`$", "`{1}` は定義されていません")
add("^Local variable `(.-)` is assigned to but never used$", "ローカル変数 `{1}` に代入していますが使われていません")
add("^f%-string without any placeholders$", "{} のない f 文字列です")
add("^Module level import not at top of file$", "import がファイルの先頭にありません")
add("^Do not use bare `except`$", "except には例外の種類を書いてください")
add("^Ambiguous variable name: `(.-)`$", "紛らわしい変数名 `{1}` です (l・O・I は 1・0 と見間違えやすい)")
add("^Comparison to `None` should be `cond is None`$", "None との比較は == ではなく is を使います")

-- 末尾の「自動修正あり」
local function strip_fix(msg)
  -- "(fix available)" と "(fixes available)" の両方
  local base = msg:gsub("%s*%(fix%a* available%)$", "")
  return base, base ~= msg
end

-- 英語の文を日本語に (訳せなければ nil)
function M.translate(msg)
  if type(msg) ~= "string" or msg == "" then return nil end
  local base, fix = strip_fix(msg)
  base = base:gsub("%s*%[%-W[^%]]*%]$", "") -- gcc が末尾に付ける警告の種類名 ([-Wformat=] など)
  -- clangd は先頭を大文字にするので、先頭を大文字にした文でも照合する。
  -- ただし元の文で一致するならそちらを優先 (ファイル名などの大文字小文字を変えないため)
  local upper = base:gsub("^%l", string.upper)
  for _, r in ipairs(rules) do
    local caps = { base:match(r[1]) }
    if #caps == 0 then caps = { upper:match(r[1]) } end
    if #caps > 0 then
      local ja = r[2]:gsub("{(%d)}", function(n) return caps[tonumber(n)] or "" end)
      if fix then ja = ja .. " (自動修正あり: この行で gra)" end
      return ja
    end
  end
  return nil
end

-- 表示用: 訳せたら日本語、だめなら英語のまま
function M.text(msg)
  return M.translate(msg) or msg
end

return M
