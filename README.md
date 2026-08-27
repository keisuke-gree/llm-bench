# llm-bench

ローカルLLM(Ollama)の「コードベースを調査する能力」を、Claude Code上で4つの軸で
比較評価するための、再利用可能なベンチマーク環境です。

- **軸1: 生成速度**(tokens/sec)
- **軸2: 実用的なコンテキスト上限**(100% GPUを維持できる最大のコンテキスト長)
- **軸3: ツール呼び出し精度**(調査の**過程** — ツール選択・構文エラー・幻覚・完結性)
- **軸4: コード調査の精度**(調査の**結論** — 最終的な回答が正解セットと一致するか)

軸1・2は`bin/sweep.sh`が完全自動で測定します。軸3・4はClaude Code上で実際にコード調査
タスクを解かせ、回答をブラインドな状態で記録した上で採点します。**軸3の採点には
ツール呼び出しの経過を記録したトレースファイル(`results/traces/<ブラインドID>.jsonl`)
が必須です。** 最終回答テキスト(`results/answers/<ブラインドID>.md`)だけでは
調査の過程を検証できず、`bin/run-tasks.sh`で測定し直さない限り軸3は「測定不能」
としてスコアを付けられません。

## 前提

### ソフトウェア

- macOS
- [Ollama](https://ollama.com/)(評価対象のモデルは事前に`ollama pull <model名>`で
  取得しておくこと)
- Claude Code(`auto mode`で起動する必要があります。詳細は後述)
- `jq` / `bash`(macOS標準の`/bin/bash` 3.2系で動作します)

`composer install`は不要です。`fixture/`はコードを読ませるだけで実行しないため、
PHP本体も依存パッケージも要りません。

### ハードウェア

**このベンチマークの推奨コンテキスト長は、すべてVRAM 28.1GiB(Apple M5 Max /
ユニファイドメモリ36GB)での実測から決めています。**

VRAMがこれより少ない環境では、`bin/prepare.sh`がウォームアップ後の検証で
`100% GPU`を維持できず警告を出します。その場合は`--context-length`を下げて
実行してください(下げ幅の見つけ方は軸2の測定そのものです)。

| 軸 | VRAMが異なる環境での扱い |
|---|---|
| 軸1(生成速度) | **`reports/`の既存結果と比較できません。** 環境ごとに測り直してください |
| 軸2(実用的なコンテキスト上限) | 同上。そもそもこの軸はハードウェア依存の値を求めるもの |
| 軸3(ツール呼び出し精度) | 比較できます。モデルの挙動を見る軸のため |
| 軸4(コード調査の精度) | 同上 |

### ディスク

3モデルすべてを取得する場合、**約55GBの空き容量**が必要です(実測値)。

| モデル | ディスク | ロード時のVRAM消費 |
|---|---|---|
| `gemma4:26b` | 18.0 GB | 17 GB(コンテキスト長262144でも) |
| `qwen3-coder:30b` | 18.6 GB | 25 GB(コンテキスト長131072) |
| `qwen3.8:27b` | 17.7 GB | 未測定 |

**ディスクサイズとVRAM消費は別の数字です。** VRAMのほうがコンテキスト長に応じて
増えるため、実際の制約になるのは常にVRAM側です。

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
│   ├── hide-answers.sh     正解セットをリポジトリ外へ物理的に退避/復元する
│   ├── run-tasks.sh        軸3・4のタスクをfixture/で自動実行し回答とトレースを保存する
│   ├── record.sh           軸3・4の回答をブラインドなファイル名で払い出す
│   ├── score.sh            軸3・4のスコアをブラインドIDのまま記録する
│   ├── restore.sh          検証環境の片付け
│   ├── sweep.sh            軸1・2の自動スイープ測定
│   └── new-report.sh       雛形から日付入りのレポートファイルを生成する
├── docs/                   使い方のドキュメント
│   ├── runbook.md          実行手順書(コマンドをコピペしながら進める用)
│   └── spec.md             設計仕様書(なぜそう測るか・なぜその基準か)
├── reports/                測定結果とその考察(レポートHTML)
│   ├── README.md           レポート索引
│   ├── _template.html      レポートの雛形(bin/new-report.shが使う)
│   └── YYYY-MM-DD-<スラグ>.html  日付入りの個別レポート
├── tasks/
│   └── tasks.md            軸3・4で使うタスク文面(Claude Codeに貼り付ける)
├── answers/
│   └── answers.md          正解セットと採点用の情報
└── results/
    ├── .gitkeep            結果ファイル・回答・対応表・スコアの出力先(共有しない)
    ├── answers/            軸3・4の最終回答テキスト(bin/run-tasks.shが生成。軸4採点用)
    └── traces/             軸3・4のツール呼び出しイベントストリーム(bin/run-tasks.shが生成。軸3採点用)
```

### `answers/` と `tasks/` を `fixture/` の外に置いている理由

エージェントは`fixture/`をカレントディレクトリとして起動します。もし`tasks/`や
`answers/`が`fixture/`の中にあると、エージェントがコードベースを探索する過程で
正解セットや「これがベンチマークである」ことに気づいてしまい、評価そのものが
無意味になります。`fixture/`の中には正解やベンチマークであることを示す情報は
一切含めていません。この分離は必ず維持してください。

## 典型的な作業フロー

**人間がやることは2つだけです。** ①対象モデルを`ollama pull`で取得しておくこと、
②リポジトリの**ルートディレクトリ**でClaude Codeを起動し、`benchmark-run` Skillを
呼ぶこと。軸1〜4の測定・実行・採点・レポート生成は`benchmark-run` Skillが自動で
通しで実行します。

```bash
ollama pull <model名>                        # 未取得のモデルがあれば(人間が実行)
claude --permission-mode auto                # リポジトリのルートディレクトリで起動
```

`--permission-mode auto`が`auto mode`の指定です。起動後に切り替えたい場合は、
セッション内で`Shift+Tab`を押すとモードが順に切り替わり、`auto`を選べます。
`.claude/settings.json`の`permissions.defaultMode`では指定できません
(後述)。

### セッション内で依頼する内容

**モデル名を挙げなければ既定の3モデル全部**(`gemma4:26b`・`qwen3-coder:30b`・
`qwen3.8:27b`)が対象になります。軸1・2では4段階のコンテキスト長も全部試すため、
12通りの測定になり、軸3・4を含めると数時間かかります。**対象を絞る場合は
モデル名を明示してください。**

| 依頼したいこと | セッションに入力する内容 |
|---|---|
| 3モデル全部を比較する(既定) | `benchmark-run Skillでベンチマークを実行して` |
| 特定の1モデルだけ測る | `benchmark-run Skillで gemma4:26b だけベンチマークを実行して` |
| 特定の複数モデルを比較する | `benchmark-run Skillで gemma4:26b と qwen3-coder:30b だけベンチマークを実行して` |
| コンテキスト長も絞る | `benchmark-run Skillで gemma4:26b だけ、コンテキスト長は 131072 と 262144 だけでベンチマークを実行して` |
| 新しく追加したモデルを既存の結果と比べる | `benchmark-run Skillで <新モデル名> だけベンチマークを実行して。レポートは既存の reports/ の結果と比較する形にして` |

モデル名は`ollama list`に出る表記(タグ込み。例: `gemma4:26b`)をそのまま書いて
ください。表記が違うと`prepare.sh`が未取得と判定して停止します。

> **`auto mode`が必要な理由。** `bin/`配下のスクリプトは`ollama serve`で
> ポートをbind(listen)しますが、**サンドボックスはbindを拒否します**
> (`Error: listen tcp 127.0.0.1:11434: bind: operation not permitted`)。
> `sandbox.network.allowedDomains`で許可しても解決しません
> (あの設定は外向きの接続にのみ適用され、bindには効かないことを実測で確認済み)。
> 加えて、エージェントが組み立てる複合コマンド(パイプやリダイレクトを含むもの)は
> `permissions.allow`で事前に列挙し尽くせません。`auto mode`ならこれらの確認が
> 自動処理されて通ります。
>
> **測定される側(`fixture/`)は`auto mode`の影響を受けません。** あちらは
> `allowUnsandboxedCommands: false`でサンドボックスを外す経路自体が無く、
> 外部通信も`ollama`の実行もできません。
>
> **リポジトリ側の設定で`auto mode`を既定にすることはできません。**
> `permissions.defaultMode: "auto"`はプロジェクトスコープの設定では付与できず、
> 無視された上でユーザー設定のモードを覆い隠してしまいます。そのため
> `.claude/settings.json`には書かず、起動時に毎回指定します。

`benchmark-run` Skillは内部で以下を順に実行します(詳細は
`.claude/skills/benchmark-run/SKILL.md`を参照)。

1. 対象モデルが`ollama list`にあるか確認する(無ければ停止して人間に取得を促す)
2. `./bin/sweep.sh`で軸1・2(生成速度・実用的なコンテキスト上限)を自動測定する
3. `./bin/hide-answers.sh --hide`で正解セットを物理的に退避する(**必須**。詳細は
   後述の「正解セットへのアクセス制御の実態」を参照)
4. モデルごとに`./bin/prepare.sh <model> --force`でモデルを切り替え、
   `./bin/run-tasks.sh`で軸3・4のタスクを無人実行する
5. `./bin/hide-answers.sh --restore`で正解セットを復元する
6. `benchmark-score` Skillの手順で採点する
7. `benchmark-report` Skillの手順でレポートを生成する
8. `./bin/restore.sh`で検証環境を片付ける

### 設定ファイルが2つある理由

このリポジトリには`settings.json`が2箇所あります。役割が正反対です。

| ファイル | 役割 | サンドボックス |
|---|---|---|
| `.claude/settings.json`（ルート） | **ベンチマークを回す側**。`ollama`やスクリプトを実行する | **有効。ただしlocalhost:11434のみ許可** |
| `fixture/.claude/settings.json` | **測定される側**。ここでモデルがタスクを解く | **有効。外部通信を一切許可しない**（`allowUnsandboxedCommands: false`） |

`bin/`配下のスクリプトは内部で`ollama`や`curl`を使ってlocalhost:11434と通信します。
サンドボックスは既定でlocalhost宛も遮断するため、そのままでは動きません。

そこでルート側だけ`sandbox.network.allowedDomains`でOllamaのポートを許可しています。

```json
"sandbox": {
  "enabled": true,
  "network": {
    "allowedDomains": ["127.0.0.1:11434", "[::1]:11434", "localhost:11434"]
  }
}
```

**サンドボックス自体は有効なままです。** 許可したのはOllamaのポートだけで、それ以外の
外部通信は引き続き遮断されます。サンドボックスを丸ごと無効化するより安全です。

**`fixture/`側には`allowedDomains`を入れていません。** 測定対象のモデルがOllamaを
直接操作できるようになると、隔離の意味が失われます。

設定は**カレントディレクトリ基準で解決される**ため、`fixture/`で起動したセッションは
ルートの設定を読みません。測定対象の隔離（サンドボックス有効、`ollama`実行不可、
外部通信不可）は維持されます。

### Skillを使わない場合(従来の手動手順)

`benchmark-run` Skillを使わず、各ステップを個別に手動で進めることもできます。

1. **軸1・2の測定(全自動)**

   ```bash
   ./bin/sweep.sh
   ```

   全モデル×全コンテキスト長の組を自動でスイープし、結果を`results/`配下にMarkdownで出力します。

2. **正解セットを退避する**

   ```bash
   ./bin/hide-answers.sh --hide
   ```

   軸3・4の実行前に必ず行います。詳細は後述の「正解セットへのアクセス制御の実態」を参照。

3. **モデルを準備する**

   ```bash
   ./bin/prepare.sh <model名>
   ```

   `fixture/.claude/settings.json`の`model`等を書き換え、そのモデル・コンテキスト長で
   `ollama serve`を起動し、ウォームアップと検証(100% GPUか等)まで行います。

4. **軸3・4のタスクを実行する**

   ```bash
   ./bin/run-tasks.sh
   ```

   `fixture/`で現在のモデルにタスク1〜3を`claude -p`で無人実行させ、回答をブラインドID
   のファイルとして`results/answers/`配下に自動保存します。対象タスクを絞りたい場合は
   `--tasks 1,2`のように指定できます。

   対話的に1件ずつ確認しながら進めたい場合は、代わりに以下の手順を使うこともできます。

   ```bash
   cd fixture && claude --setting-sources project
   ```

   タスクごとに以下を繰り返します。

   - `/clear`で会話をリセットする(前タスクの情報が残ると精度評価が歪むため)
   - `tasks/tasks.md`の該当タスクの文面をそのまま貼り付ける
   - エージェントの回答を得たら、別ターミナルで `./bin/record.sh <タスク番号>` を実行し、
     払い出されたファイルに回答を貼り付けて保存する(モデル名を伏せたファイル名になる)

5. **正解セットを復元する**

   ```bash
   ./bin/hide-answers.sh --restore
   ```

   採点には正解セットが必要なため、退避したままでは採点できません。

6. **全モデル終了後、採点する**

   `answers/answers.md`の正解セットと、`results/answers/`配下の回答ファイルを突き合わせて
   採点します。`results/mapping.tsv`(どのファイルがどのモデルかの対応表)は採点時には
   参照しないでください(ブラインド採点のため)。この作業は`benchmark-score` Skillに
   任せられます。採点結果は`./bin/score.sh <ブラインドID> --axis3 <0-5> --axis4 <0-5>`で
   `results/scores.tsv`に記録します(ブラインドIDのまま記録し、モデル名の解決はレポート
   生成時に行います)。

7. **レポートを作る**

   `./bin/new-report.sh <スラグ>`で`reports/`配下に日付入りのレポートファイルを生成し、
   `benchmark-report` Skillで`results/`の実測値とスコアを転記・分析します。
   詳細は`reports/README.md`を参照してください。

8. **片付ける**

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
揃わないと比較が成立しません)。`bin/prepare.sh`が書き換えるのは次の4キーだけで、
`permissions`と`sandbox`の他の項目には一切触れません。

| キー | 何に合わせるか |
|---|---|
| `model` | 引数で指定したモデル |
| `env.CLAUDE_CODE_MAX_CONTEXT_TOKENS` | そのモデルのコンテキスト長 |
| `env.CLAUDE_CODE_AUTO_COMPACT_WINDOW` | コンテキスト長から算出した値 |
| `sandbox.filesystem.denyRead` | リポジトリの実際の配置場所(後述の汚染防止) |

書き戻す前にJSONの妥当性・`permissions`と`sandbox`が失われていないこと・
`denyRead`に`answers/`が含まれていることを検証し、1つでも失敗したらバックアップから
復元して停止します。`--dry-run`で変更内容だけを確認できます。

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

### Skillを追加したら `skillOverrides` にも追加すること

**プロジェクトスコープのSkillは、起動ディレクトリからリポジトリルートまで遡って探索されます**
（公式に文書化された仕様）。`settings.json`や`CLAUDE.md`がカレントディレクトリ基準で解決される
のとは異なるため、`fixture/`で起動しても`llm-bench/.claude/skills/`のSkillが読み込まれます。

これは重大な問題を起こします。Skillの説明文には「正解セットと突き合わせて採点する」といった
記述があるため、**測定対象のモデルに「自分はベンチマークを受けている」「正解セットが存在する」
ことが漏れます**。正解を読まれれば測定は無意味になります。

そのため`fixture/.claude/settings.json`で個別に無効化しています。

```json
"skillOverrides": {
  "benchmark-score": "off",
  "benchmark-report": "off",
  "benchmark-run": "off"
}
```

**`.claude/skills/`にSkillを追加したら、必ずここにも`"off"`で追加してください。**
忘れると同じ漏れが再発します。

`--bare`や`--disable-slash-commands`でも止まりますが、**Built-inのSkillまで消えてしまい
測定条件が変わる**ため使いません。過去の測定はBuilt-in Skillが読み込まれた状態で行われています。

確認方法は`fixture/`で`/context`を実行し、`Skills`に`Project`セクションが**現れないこと**です。

## 正解セットへのアクセス制御の実態

**重要**: `permissions`/`sandbox`の設定だけでは`answers/`を技術的に完全に遮断できません。
実測で確認した制約を正確に把握しておいてください。

Claude Codeの2つの制御レイヤーは、対象が異なります。

| レイヤー | 制御対象 | `answers/`を塞げるか |
|---|---|---|
| `permissions.deny`の`Read(...)` | Readツール | **塞げない**（プロジェクト外のパスを表現できない） |
| `sandbox.filesystem.denyRead` | Bashサブプロセスのファイルアクセス（OSレベル） | **塞げる** |

`permissions.deny`に`Read(../**)`や`Read(**/answers/**)`と書いても、`fixture/`の外にある
ファイルにはマッチしません（実測で確認）。したがって**設定ファイルだけに頼る場合、
Readツール経由のアクセスは確認プロンプトが最後の砦**になります。

Bash経由は`sandbox.filesystem.denyRead`でOSレベルに遮断しています。

```json
"denyRead": ["~/.ssh", "~/.gnupg", "~/llm-bench/answers", ...]
```

この値にはリポジトリの配置場所が入ります。**`bin/prepare.sh`が実行のたびに実際の
配置場所から組み立て直すため、どこにcloneしても手で書き換える必要はありません。**

自動化しているのは、ここが古いままだと**エラーも警告も出ないまま汚染防止が無効になる**
ためです。`answers/`は`bin/hide-answers.sh`が物理退避するので守られますが、
`results/`（過去の回答）と`reports/`（採点済みの考察）は退避対象ではないため、
2回目以降の測定でモデルに読まれ得ます。

### 根本対処: `bin/hide-answers.sh`による物理的な退避

`permissions.deny`の限界を設定だけで埋めることはできないため、**`answers/`ディレクトリ
自体をリポジトリ外の到達不可能な場所へ物理的に移動する**という方法で根本的に解決します。

```bash
./bin/hide-answers.sh --hide      # answers/ を $HOME 配下の固定パスへ退避する
./bin/hide-answers.sh --status    # 退避中かどうかを確認する
./bin/hide-answers.sh --restore   # 退避先から元の位置へ戻す
```

退避中は`answers/`がリポジトリ内に一切存在しないため、Read経由・Bash経由を問わず
そもそも読みようがありません。設定ファイルの表現力の限界に依存しない、確実な対処です。
`benchmark-run` Skillは軸3・4の実行前に必ず`--hide`を、実行後に必ず`--restore`を行います。

### 無人実行（`claude -p`）を使う前提条件

**無人実行（`claude -p`等）では確認プロンプトが一切出ません。** 対話セッションで最後の
砦だった確認プロンプトが機能しないため、`answers/`が存在する状態で無人実行すると
モデルに読まれてしまう可能性があります。`bin/run-tasks.sh`はこれに対する安全装置として、
実行前に`bin/hide-answers.sh --status`で退避済みであることを確認し、退避されていなければ
エラーで停止します。**無人化と物理的な退避はセットで設計されています。**

さらに無人実行では、`permissions.allow`に無いコマンドは確認プロンプトではなく**失敗**に
なります(対話セッションのように「許可しますか?」と聞かれてYesを選ぶ、ということが
起きません)。そのためモデルがコード調査に使う読み取り専用コマンド
(`rg` / `fd` / `ls` / `cat` / `head` / `tail` / `wc` およびGrep/Globツール)を
`fixture/.claude/settings.json`の`permissions.allow`に明示的に許可しています。

**`Bash(find *)`と`Bash(grep *)`は意図的に許可していません。** `fixture/CLAUDE.md`には
「検索は`rg`に統一する、`grep`は使わない」「`fd`に統一する、`find`は使わない」という
ルールが書かれており、これを文書だけでなく技術層(許可リスト)でも強制する意図です。
文書によるルールがローカルLLMに守られなかった実測結果があるため、この二重化には意味が
あります。

## フィクスチャを公開しないこと

`fixture/`の合成コードと`answers/`の正解セットが公開範囲に出ると、いずれモデルの
学習データに取り込まれ、調査せず記憶で答えられるようになって測定が無意味になります。
**必ずprivateリポジトリで運用してください。**

## 各スクリプトの説明

| スクリプト | 説明 |
|---|---|
| `bin/prepare.sh` | モデル名の解決・存在確認・`fixture/.claude/settings.json`のパッチ・`ollama serve`の起動・ウォームアップと検証(100% GPUか等)までを1コマンドで行う |
| `bin/hide-answers.sh` | `answers/`をリポジトリ外の固定パスへ物理的に退避/復元する(`--hide` / `--restore` / `--status`) |
| `bin/run-tasks.sh` | `fixture/`で現在のモデルにタスクを`claude -p --output-format stream-json --verbose`で無人実行させ、最終回答を`results/answers/`へ、ツール呼び出しを含む全イベントを`results/traces/`へ、それぞれブラインドIDのファイルとして自動保存する(退避されていなければエラーで停止する安全装置つき) |
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
- タスクの型と採点基準の設計意図は `docs/spec.md` の「軸3・4共通: タスクの型」以降を参照してください。

## 実行環境についての注意

- `bin/prepare.sh` / `bin/restore.sh` / `bin/sweep.sh` / `bin/run-tasks.sh`は、
  **リポジトリのルートディレクトリ**で起動したClaude Codeセッション、または人間が
  通常のターミナルから直接実行する想定です。`ollama`コマンドを遮断するサンドボックス設定は
  `fixture/.claude/settings.json`にのみ入っているため、`fixture/`の**外**(ルート)で
  起動したセッションからはこれらのスクリプトが問題なく実行できます。逆に`fixture/`の
  **中**で起動したセッション(軸3・4のタスクを解かせているエージェント自身)からは、
  サンドボックスのlocalhost遮断により`ollama`コマンドが使えず動作しません。
- macOS標準の`/bin/bash`(3.2系)で動作します。
