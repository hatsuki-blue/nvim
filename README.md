# nvim config

Windows 向けの Neovim 設定 (lazy.nvim)。

- `init.lua` — 基本設定とプラグイン
- `lua/user/terminal.lua` — 下のパネルのターミナル (VSCode 風)
- `lua/user/remote.lua` — SSH 接続先のファイルツリーと編集
- `lazy-lock.json` — プラグインのバージョン固定

## セットアップ (Windows)

```powershell
winget install Neovim.Neovim Git.Git Microsoft.PowerShell OpenJS.NodeJS.LTS BurntSushi.ripgrep.MSVC BrechtSanders.WinLibs.POSIX.UCRT DEVCOM.JetBrainsMonoNerdFont
git clone https://github.com/hatsuki-blue/nvim.git $env:LOCALAPPDATA\nvim
nvim
```

初回起動でプラグイン・LSP・パーサーが自動で入ります。
ターミナルのフォントは `JetBrainsMono NFM` にしてください。
SSH 機能は `~/.ssh/config` のホスト一覧と、鍵認証を使います。
