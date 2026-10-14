# nvim config

Neovim 0.12 以上向けの設定 (lazy.nvim)。Windows と Linux で使えます。

- `init.lua` — 基本設定とプラグイン
- `lua/user/terminal.lua` — 下のパネルのターミナル (VSCode 風)
- `lua/user/remote.lua` — SSH 接続先のファイルツリーと編集
- `lazy-lock.json` — プラグインのバージョン固定

キー操作は nvim 内で `F1` (または `<Space>k`) を押すと一覧が出ます。

## セットアップ (Windows)

```powershell
winget install Neovim.Neovim Git.Git Microsoft.PowerShell OpenJS.NodeJS.LTS BurntSushi.ripgrep.MSVC BrechtSanders.WinLibs.POSIX.UCRT DEVCOM.JetBrainsMonoNerdFont
git clone https://github.com/hatsuki-blue/nvim.git $env:LOCALAPPDATA\nvim
nvim
```

ターミナルのフォントを `JetBrainsMono NFM` にしてください
(Windows Terminal: 設定 → プロファイル → 既定値 → 外観)。

## セットアップ (Linux)

### 1. パッケージ

Ubuntu / Debian:

```bash
sudo apt update
sudo apt install -y git curl unzip build-essential ripgrep nodejs npm python3-venv xclip
```

Fedora:

```bash
sudo dnf install -y git curl unzip gcc gcc-c++ make ripgrep nodejs npm python3 xclip
```

Arch:

```bash
sudo pacman -S --needed git curl unzip base-devel ripgrep nodejs npm python xclip
```

| パッケージ | 使う機能 |
|---|---|
| git, curl, unzip | プラグインと LSP のダウンロード・展開 |
| build-essential (gcc) | treesitter のパーサーのビルド |
| ripgrep | `<Space>fg` (文字列で探す) |
| nodejs, npm | 多くの LSP と prettier |
| python3-venv | Python 系ツールの導入 (Mason) |
| xclip | クリップボード連携 (Wayland は `wl-clipboard`)。サーバーなど GUI が無い環境では不要 |

Go や Rust のコードを書く場合は、`golang` と `rustup` も入れてください。

### 2. Neovim 0.12 以上

ディストリのパッケージは古いことが多いので、公式のバイナリを使います。

```bash
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
sudo tar -C /opt -xzf nvim-linux-x86_64.tar.gz
sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
nvim --version | head -1
```

ARM (Raspberry Pi など) は `nvim-linux-arm64.tar.gz` に読み替えてください。

#### sudo が使えない / プロキシがある環境 (学校の共有 PC など)

管理者権限がなくても、ホームディレクトリに展開すれば使えます。

**ブラウザでダウンロードする場合** (ブラウザがプロキシ経由で使えていれば、これが一番楽):

1. ブラウザで <https://github.com/neovim/neovim/releases/latest> を開く
2. `nvim-linux-x86_64.tar.gz` をダウンロード (ARM は `nvim-linux-arm64.tar.gz`)
3. ターミナルで展開して実行

```bash
cd ~/Downloads
tar xzf nvim-linux-x86_64.tar.gz
./nvim-linux-x86_64/bin/nvim
```

**ターミナルだけで済ませる場合** (`プロキシホスト:ポート` などは自分の環境の値に置き換える):

```bash
cd ~
curl -x http://プロキシホスト:ポート -U ユーザー名:パスワード -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
tar xzf nvim-linux-x86_64.tar.gz
./nvim-linux-x86_64/bin/nvim
```

パスワードはシェルの履歴 (`~/.bash_history`) に残ります。共有 PC では、使い終わったら
`history -c` で消すか、`-U ユーザー名` だけにして、パスワードは聞かれてから入力してください。

**毎回パスを打ちたくないとき** (以後は `nvim` だけで起動します):

```bash
echo 'export PATH="$HOME/nvim-linux-x86_64/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

`~/Downloads` に展開した場合は、パスを `$HOME/Downloads/nvim-linux-x86_64/bin` に読み替えてください。

起動時に `GLIBC_2.xx not found` と出る場合は、その PC の OS が古く、公式のバイナリが動きません。
AppImage 形式の `nvim-linux-x86_64.appimage` を使う方法があります
(`chmod u+x nvim-linux-x86_64.appimage` のあと、FUSE が使えない環境では
`./nvim-linux-x86_64.appimage --appimage-extract` で展開して、中の `squashfs-root/usr/bin/nvim` を使う)。

どの方法でも、起動したら `nvim --version | head -1` で、バージョンが 0.12 以上か確認してください。

git や node などが入っていない環境でも、nvim 本体は動きます。
その場合は、プラグインの導入 (git)、言語サーバー (node)、シンタックスハイライト (gcc) など、
足りないものに関係する機能だけが使えません。

### 3. フォント (アイコン表示)

```bash
mkdir -p ~/.local/share/fonts
curl -fLo /tmp/JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip -o /tmp/JetBrainsMono.zip -d ~/.local/share/fonts/JetBrainsMono
fc-cache -f
```

ターミナルのフォントを `JetBrainsMono Nerd Font Mono` にしてください。
SSH 越しに使うサーバー側では、手元のターミナルのフォントが使われるので不要です。

### 4. 設定を取得して起動

```bash
git clone https://github.com/hatsuki-blue/nvim.git ~/.config/nvim
nvim
```

## 初回起動

プラグイン、LSP サーバー、treesitter のパーサーが自動で入ります (数分かかります)。
終わったら一度 nvim を閉じて、もう一度起動してください。
進み具合は `:Lazy` と `:Mason` で確認できます。

## SSH 機能

- `~/.ssh/config` のホスト一覧を使います (`<Space>ts` で選択、`:SSH ホスト名`)
- 接続先のファイルツリーは鍵認証が前提です (パスワード認証のホストはターミナルのみ)
- 接続先で Claude Code を使うには、接続先にも Claude Code を入れてください (`<Space>tr`)

## 補足 (Linux)

- 下のパネルのターミナルは `$SHELL` を使います
- ウィンドウ移動の `Alt-h/j/k/l` は、ターミナルによっては Alt が効かないことがあります。
  その場合は `Ctrl-w` に続けて `h/j/k/l` を使ってください
