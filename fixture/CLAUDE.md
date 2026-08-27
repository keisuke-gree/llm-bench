# AIへのルール

## 基本ルール

- **思考は英語で行うこと**。ただし、**出力は日本語で回答すること**。
- **コードのコメントとエラーログメッセージは日本語**で記述すること。
- ハードコーディングは絶対に必要な場合を除き避けること。

## ツール使用規則

- 検索は `rg`（ripgrep）に統一する。`grep` / `grep -r` は使わない。
   - `grep -rn X` → `rg -n X`、`grep -nE "a|b" f` → `rg -n "a|b" f`
- ファイル探索は `fd` に統一する。`find` は使わない。
   - `find . -name "*.ts"` → `fd -e ts`、`find . -type f -name "foo*"` → `fd "foo"`
   - `Library/PackageCache/` 等 gitignore 対象を探す場合は `fd --no-ignore` を使う
