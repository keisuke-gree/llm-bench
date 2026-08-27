# llm-bench

ローカルLLM(Ollama)の「コードベースを調査する能力」を、Claude Code上で4つの軸で
比較評価するための、再利用可能なベンチマーク環境です。

- **軸1: 生成速度**(tokens/sec)
- **軸2: 実用的なコンテキスト上限**(100% GPUを維持できる最大のコンテキスト長)
- **軸3: ツール呼び出し精度**(調査の**過程** — ツール選択・構文エラー・幻覚・完結性)
- **軸4: コード調査の精度**(調査の**結論** — 最終的な回答が正解セットと一致するか)

軸1・2は`bin/sweep.sh`が完全自動で測定します。軸3・4はClaude Code上で実際にコード調査
タスクを解かせ、回答をブラインドな状態で記録した上で採点します。

## 前提

- macOS
- [Ollama](https://ollama.com/)(評価対象のモデルは事前に`ollama pull <model名>`で
  取得しておくこと)
- Claude Code
- `jq` / `bash`(macOS標準の`/bin/bash` 3.2系で動作します)

## ディレクトリ構成

```
llm-bench/
├── README.md               このファイル
├── .gitignore
├── fixture/                 検証対象のコードベース(エージェントはここで起動する)
│   ├── .claude/settings.json
│   ├── CLAUDE.md
│   ├── composer.json
│   ├── src/
│   └── tests/
├── bin/                    自動化スクリプト
│   ├── prepare.sh          モデルの切り替え〜サーバー起動・検証
│   ├── record.sh           軸3・4の回答をブラインドなファイル名で払い出す
│   ├── score.sh            軸3・4のスコアをブラインドIDのまま記録する
│   ├── restore.sh          検証環境の片付け
│   ├── sweep.sh            軸1・2の自動スイープ測定
│   └── new-report.sh       雛形から日付入りのレポートファイルを生成する
├── docs/                   使い方のドキュメント
│   ├── runbook.md          実行手順書(コマンドをコピペしながら進める用)
│   ├── spec.md             設計仕様書(なぜそう測るか・なぜその基準か)
│   └── setup.md            このベンチマーク環境自体の使い方の詳細
├── reports/                測定結果とその考察(レポートHTML)
│   ├── README.md           レポート索引
│   ├── _template.html      レポートの雛形(bin/new-report.shが使う)
│   └── YYYY-MM-DD-<スラグ>.html  日付入りの個別レポート
├── tasks/
│   └── tasks.md            軸3・4で使うタスク文面(Claude Codeに貼り付ける)
├── answers/
│   └── answers.md          正解セットと採点用の情報
└── results/
    └── .gitkeep            結果ファイル・回答・対応表・スコアの出力先(共有しない)
```

### `answers/` と `tasks/` を `fixture/` の外に置いている理由

エージェントは`fixture/`をカレントディレクトリとして起動します。もし`tasks/`や
`answers/`が`fixture/`の中にあると、エージェントがコードベースを探索する過程で
正解セットや「これがベンチマークである」ことに気づいてしまい、評価そのものが
無意味になります。`fixture/`の中には正解やベンチマークであることを示す情報は
一切含めていません。この分離は必ず維持してください。

## 典型的な作業フロー

1. **軸1・2の測定(全自動)**

   ```bash
   ./bin/sweep.sh
   ```

   全モデル×全コンテキスト長の組を自動でスイープし、結果を`results/`配下にMarkdownで出力します。

2. **モデルを準備する**

   ```bash
   ./bin/prepare.sh <model名>
   ```

   `fixture/.claude/settings.json`の`model`等を書き換え、そのモデル・コンテキスト長で
   `ollama serve`を起動し、ウォームアップと検証(100% GPUか等)まで行います。

3. **Claude Codeを起動する**

   ```bash
   cd fixture && claude --setting-sources project
   ```

4. **タスクを1件ずつ実施する**

   タスクごとに以下を繰り返します。

   - `/clear`で会話をリセットする(前タスクの情報が残ると精度評価が歪むため)
   - `tasks/tasks.md`の該当タスクの文面をそのまま貼り付ける
   - エージェントの回答を得たら、別ターミナルで `./bin/record.sh <タスク番号>` を実行し、
     払い出されたファイルに回答を貼り付けて保存する(モデル名を伏せたファイル名になる)

5. **全モデル終了後、採点する**

   `answers/answers.md`の正解セットと、`results/answers/`配下の回答ファイルを突き合わせて
   採点します。`results/mapping.tsv`(どのファイルがどのモデルかの対応表)は採点時には
   参照しないでください(ブラインド採点のため)。この作業は`benchmark-score` Skillに
   任せられます。採点結果は`./bin/score.sh <ブラインドID> --axis3 <0-5> --axis4 <0-5>`で
   `results/scores.tsv`に記録します(ブラインドIDのまま記録し、モデル名の解決はレポート
   生成時に行います)。

6. **レポートを作る**

   `./bin/new-report.sh <スラグ>`で`reports/`配下に日付入りのレポートファイルを生成し、
   `benchmark-report` Skillで`results/`の実測値とスコアを転記・分析します。
   詳細は`reports/README.md`を参照してください。

7. **片付ける**

   ```bash
   ./bin/restore.sh
   ```

   `bin/prepare.sh`が起動した`ollama serve`を停止します。

## `~/.zshrc`を書き換えない設計

`bin/prepare.sh`はモデルの切り替えのたびにコンテキスト長や`OLLAMA_KEEP_ALIVE`を
変更する必要がありますが、これらは**`~/.zshrc`のような永続設定ファイルには一切書き込まず**、
`ollama serve`を起動する際の**プロセス環境変数**として渡します
(`OLLAMA_CONTEXT_LENGTH=N OLLAMA_KEEP_ALIVE=DUR ollama serve`の形)。

この設計により:

- 設定ファイルの書き換え事故(他の設定を巻き添えで壊す、書き戻し忘れ等)のリスクがゼロになる
- 検証後の「復元」作業が原理的に不要になる(そもそも何も変えていないため)。
  `bin/restore.sh`はサーバープロセスを止めるだけで済む

という2つの利点が得られます。`fixture/.claude/settings.json`の`model`等はモデル切り替えの
たびに書き換わりますが、次に`bin/prepare.sh`を実行すれば上書きされるため、こちらもあえて
自動では元に戻していません。

## `fixture/.claude/settings.json` について

`permissions`と`sandbox`は、ある本番環境を模した設定になっています。自分の環境に
合わせて調整して構いませんが、**モデル間で必ず同一の設定を使ってください**(条件が
揃わないと比較が成立しません)。`bin/prepare.sh`は`model` /
`env.CLAUDE_CODE_MAX_CONTEXT_TOKENS` / `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW`の3キーのみを
書き換え、`permissions`・`sandbox`には一切触れません。

### `claudeMdExcludes`が効いているかの確認方法

このファイルには次の設定が入っています。

```json
"claudeMdExcludes": ["**/.claude/CLAUDE.md"]
```

これはユーザー個人の`~/.claude/CLAUDE.md`をこのベンチマークのコンテキストから除外する
ための設定です。除外する理由は、そこに書かれた指示（「検索は`rg`に統一する」等のツール使用規則）が
**軸3で測定するツール選択の挙動を左右してしまう**ためです。各自の個人設定によって結果が変わると、
モデル間の比較が成立しません。

`claudeMdExcludes`は絶対パスへのglobマッチで、**チルダ展開は効きません**（`"~/.claude/CLAUDE.md"`
と書いても除外されないことを実測で確認済み）。個人名を含まない形にするため`**/`を使っています。

効いているかどうかは、`fixture/`でClaude Codeを起動して`/context`を実行し、`Memory files`に
`CLAUDE.md`が**1件だけ**（`fixture/CLAUDE.md`のみ）計上されていることで確認できます。
`~/.claude/CLAUDE.md`が併記されている場合は除外できていません。

## フィクスチャを公開しないこと

`fixture/`の合成コードと`answers/`の正解セットが公開範囲に出ると、いずれモデルの
学習データに取り込まれ、調査せず記憶で答えられるようになって測定が無意味になります。
**必ずprivateリポジトリで運用してください。**

## 各スクリプトの説明

| スクリプト | 説明 |
|---|---|
| `bin/prepare.sh` | モデル名の解決・存在確認・`fixture/.claude/settings.json`のパッチ・`ollama serve`の起動・ウォームアップと検証(100% GPUか等)までを1コマンドで行う |
| `bin/record.sh` | 現在のモデルを`fixture/.claude/settings.json`から自動で読み取り、軸3・4の回答をランダムなブラインドIDのファイルとして払い出す |
| `bin/score.sh` | 軸3・4のスコアをブラインドIDのまま`results/scores.tsv`に記録する(`results/mapping.tsv`は参照しない) |
| `bin/restore.sh` | `bin/prepare.sh`が起動した`ollama serve`を停止し、検証環境を片付ける |
| `bin/sweep.sh` | 軸1・2(生成速度・実用的なコンテキスト上限)を全モデル×全コンテキスト長で自動測定する |
| `bin/new-report.sh` | `reports/_template.html`から日付入りのレポートファイルを`reports/`配下に生成する |

各スクリプトは`--help`で詳しい使い方を確認できます。`bin/prepare.sh`は`--dry-run`で
実際の書き込み無しに変更内容だけを確認できます。

## 詳しいドキュメント

- 実行手順を上から順に進めたい場合は `docs/runbook.md` を参照してください。
- 「なぜこの4軸で測るのか」「なぜこの採点基準なのか」等の設計根拠は `docs/spec.md` を参照してください。
- 実際に測定した結果とその考察は `reports/` 配下のレポートを参照してください（ブラウザで開いてください。専門用語はホバーで説明が出ます）。索引は `reports/README.md` にあります。最新のレポート（`reports/2026-08-27-initial-comparison.html`）は3モデルの比較、アーキテクチャ（MoE/dense）による速度差の分析、ハードウェア投資が解決策になるかの検討を含みます。
- このベンチマーク環境(`fixture/`のコードベースやタスクの設計意図)自体について詳しく知りたい場合は
  `docs/setup.md` を参照してください。

## 実行環境についての注意

- `bin/prepare.sh` / `bin/restore.sh` / `bin/sweep.sh` は、人間が通常のターミナルから
  直接実行する想定です。Claude Codeのエージェント経由では、サンドボックスのlocalhost遮断により
  `ollama`コマンドが使えず動作しません。
- macOS標準の`/bin/bash`(3.2系)で動作します。
