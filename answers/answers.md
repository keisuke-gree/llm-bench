# ベンチマーク正解セット・採点用情報

このファイルは `fixture/` の**外**に置いています。`fixture/` 内には正解や
ベンチマークであることを示す情報は一切含まれていません。

対象リポジトリ: `fixture/`（PHP合成コードベース、90ファイル）

---

## タスク1: `RewardCalculator::applyBonusRate()` の呼び出し元

### 正解（6ファイル、各1箇所、合計6箇所）

| # | ファイル | 呼び出し箇所の特徴 |
|---|---|---|
| 1 | `src/Controller/QuestController.php` | `previewReward()` 内。`$this->rewardCalculator->applyBonusRate(...)` |
| 2 | `src/Controller/EventController.php` | `simulateBonus()` 内。`$this->rewardCalculator->applyBonusRate(...)` |
| 3 | `src/Logic/QuestClearLogic.php` | `clear()` 内。`$this->rewardCalculator->applyBonusRate(...)` |
| 4 | `src/Logic/EventRewardLogic.php` | `grantReward()` 内。`$this->rewardCalculator->applyBonusRate(...)` |
| 5 | `src/Model/UserRewardModel.php` | `confirm()` 内。**変数に代入したインスタンス経由**（`$calculator = new RewardCalculator(); ... $calculator->applyBonusRate(...)`）で、宣言と呼び出しが離れている |
| 6 | `src/Logic/Batch/DailyBonusBatch.php` | `run()` 内、`foreach` ループの中。`$this->rewardCalculator->applyBonusRate(...)` |

### 仕込んだデコイと、正解に含めてはいけない理由

- **`Bench\Logic\Legacy\LegacyRewardCalculator::applyBonusRate()`**（別クラスの同名メソッド）
  - 定義: `src/Logic/Legacy/LegacyRewardCalculator.php`
  - 呼び出し元（3ファイル、各1箇所）:
    - `src/Logic/Legacy/LegacyQuestLogic.php`
    - `src/Logic/Legacy/LegacyEventLogic.php`
    - `src/Logic/Legacy/LegacyBatchLogic.php`
  - これらは **別クラス**（`Bench\Logic\RewardCalculator` ではなく `Bench\Logic\Legacy\LegacyRewardCalculator`）のメソッドを呼んでいるため、正解に含めてはいけない。単純に文字列 `applyBonusRate` を grep すると、呼び出しだけで9箇所（6+3）ヒットする。
- **`src/Dao/RewardDao.php`**: クラスのPHPDocコメント（`@see` タグ）内に `applyBonusRate()` という文字列があるが、実際の呼び出しは存在しない。
- **`src/Model/AuditLogModel.php`**: `EVENT_APPLY_BONUS_RATE` 定数の値として文字列リテラル `'applyBonusRate'` があるが、これはログのイベント名であり、実際のメソッド呼び出しではない。

### 機械的な再確認コマンド

```bash
REPO=fixture

# 正解: RewardCalculator::applyBonusRate への実際の呼び出し（6箇所であるべき）
rg -n -- '->(rewardCalculator|calculator)->applyBonusRate\(' "$REPO"

# 呼び出しパターン全体（正解6 + Legacy 3 = 9箇所であるべき）
rg -c -- '->applyBonusRate\(' "$REPO" | awk -F: '{s+=$2} END{print s}'

# Legacy側の呼び出し（3箇所、正解6ファイルとは別ファイルであるべき）
rg -l -- '->legacyRewardCalculator->applyBonusRate\(' "$REPO"

# 文字列 "applyBonusRate" の全出現（呼び出し9 + 定義2 + コメント1 + 文字列リテラル1 = 13）
rg -c "applyBonusRate" "$REPO" | awk -F: '{s+=$2} END{print s}'
```

### 採点時の注意点

- 6件中いくつ正解できたか（Recall）に加え、**Legacy側の3件を誤って含めてしまったか（誤検出数）**、
  コメント・文字列リテラルの2件を誤って含めてしまったかを別途記録すること。
- 単純grep（`grep -rn applyBonusRate`）だけで済ませたエージェントは、Legacy 3件・コメント1件・
  文字列リテラル1件を含む最大13件相当を提示してしまう可能性が高い。呼び出し元クラスを区別できているかが
  「軸3: ツール呼び出し精度」の重要な観察点になる。
- `UserRewardModel.php` の1件（変数代入経由）を見つけられたかどうかは、単純な文字列一致ではなく
  データフローの追跡ができているかの指標になる。

---

## タスク2: `UserContext::$campaignId` を `?int` → `string` に変更した場合の影響範囲

> 正解は**7ファイル**。`campaignId` を含む全12ファイルを A（正解）/ B（デコイ）/ C（対象外）に
> 断定的に分類してある。採点者の裁量に委ねる記述は一切設けていないため、
> 回答と機械的に突き合わせて採点できる。

### 検証方法

`campaignId` を含む全12ファイル（下記コマンドで確認）それぞれについてコードを読解し、
このうち型エラー／明らかな不正動作が生じると判定したケースは、`fixture` を一時ディレクトリに
コピー（本体は無変更）した上で `UserContext::$campaignId` の型を `?int` から `string`（デフォルト値
`null` は非nullable文字列に付与できないため削除し必須引数化）に変更し、実際に対象コードパスを
実行して `TypeError`（または想定した不正動作）が発生することを確認した（PHP 8.5.9）。
以下の表の「検証」列で **実証済み** / **読解による判定** を区別する。

### 正解（7ファイル、影響を受ける）

| # | ファイル | 影響を受ける理由 | 検証 |
|---|---|---|---|
| 1 | `src/Logic/CampaignResolver.php` | `resolve()` が `resolveCampaign(int $campaignId)`（`int` 型宣言のプライベートメソッド）に `$context->campaignId` を渡している。`string` を渡すと `TypeError`。 | 実証済み: `Bench\Logic\CampaignResolver::resolveCampaign(): Argument #1 ($campaignId) must be of type int, string given` |
| 2 | `src/Dao/CampaignDao.php` | `findGroupSummary()` 内で `intdiv($context->campaignId, 100)` を呼んでいる。`intdiv()` は `int` 引数を要求するため `TypeError`。 | 実証済み: `intdiv(): Argument #1 ($num1) must be of type int, string given` |
| 3 | `src/Controller/CampaignController.php` | `entry()` 内で `new CampaignEntryModel($context->campaignId, $context->userId)` を呼んでおり、`CampaignEntryModel` のコンストラクタ第1引数は `int` 型宣言。`string` を渡すと `TypeError`。 | 実証済み: `Bench\Model\CampaignEntryModel::__construct(): Argument #1 ($campaignId) must be of type int, string given` |
| 4 | `src/Logic/RewardCalculator.php` | `applyBonusRate()` が `$this->resolveBonusRate($context->campaignId)` を呼び、`resolveBonusRate(?int $campaignId): float` という `?int` 型宣言のプライベートメソッドに `string` を渡している。`TypeError`。 | 実証済み: `Bench\Logic\RewardCalculator::resolveBonusRate(): Argument #1 ($campaignId) must be of type ?int, string given` |
| 5 | `src/Logic/QuestClearLogic.php` | `clear()` 内で `$context->campaignId === self::SUMMER_CAMPAIGN_ID`（`int` 定数 `3`）と比較している。`===` は型不一致だと例外を出さず常に `false` を返すため、意図した分岐に絶対に入らなくなる（型エラーではなく明らかな不正動作）。なお `clear()` はこの比較の前に `applyBonusRate()`（#4）を呼ぶため、キャンペーン期間内（`isWithinPeriod()` が `true` になる場合）は実際には先に #4 の `TypeError` で処理が止まる。この比較の不正動作が単独で現れるのは、`campaignStartAt`/`campaignEndAt` が未設定などで `isWithinPeriod()` が `false` を返す場合のみ。 | 実証済み: `isWithinPeriod()` が `false` になる文脈で `clear()` を最後まで実行し、`'3' === 3` が `false` になることを確認（例外は出ないが分岐に入らない） |
| 6 | `tests/Logic/CampaignResolverTest.php` | `testResolveReturnsCampaignRecord()` が `new UserContext(..., campaignId: 101, ...)` のように `int` リテラルを渡して構築している。`string` 型になるとこの呼び出し自体が `TypeError`。また同ファイルの `testResolveReturnsNullWhenNoCampaign()` も `campaignId: null` を渡しており、`string`（非nullable）になると同様に `TypeError` になる。 | 実証済み: `Argument #3 ($campaignId) must be of type string, int given` / `..., null given` |
| 7 | `tests/Logic/QuestClearLogicTest.php` | `testClearDuringCampaignMidPeriodAppliesBonus()` と `testBonusAppliedOnCampaignLastDay()` がそれぞれ `new UserContext(..., campaignId: 1, ...)` のように `int` リテラルを渡して構築している。`string` 型になるとこの呼び出し自体が `TypeError`。 | 実証済み: `Argument #3 ($campaignId) must be of type string, int given` |

### 仕込んだデコイ（4ファイル、影響を受けない）

- **`src/Model/CampaignBannerModel.php`**: `buildImagePath()` / `buildTitleKey()` で
  `"assets/campaign/banner_{$this->context->campaignId}.png"` のように**文字列補間の中でのみ**
  使用している。文字列補間はどんな型でも `string` に変換されるため、`string` になっても
  型エラーは発生しない（挙動もほぼ変わらない）。（実証済み: エラーなし）
- **`src/Logic/CampaignNotifier.php`**: `buildNotificationKey()` / `buildLogMessage()` で
  同様に文字列補間の中でのみ使用している。影響なし。（実証済み: エラーなし）
- **`src/Logic/CampaignLogger.php`**: `record()` が `$context->campaignId` を
  `append(string $key, mixed $value)` の `mixed` 型引数にそのまま渡しているだけ。`mixed` は
  どの型でも受け付けるため型エラーにならない。（実証済み: エラーなし）
- **`src/Model/CampaignEntryModel.php`**: コンストラクタの `int $campaignId` は自身が定義する
  独立したパラメータであり、`UserContext` を `use` すらしておらず `$context->campaignId` を
  直接参照するコードは一切ない。型変更が実際にエラーとして表面化するのは呼び出し元の
  `src/Controller/CampaignController.php`（正解#3）であり、`CampaignEntryModel.php` 自身のコードは
  変更前後で完全に同一のまま動作する（有効な `int` を直接渡して構築してもエラーは発生しない）。
  **このファイルを回答に含めた場合は誤り（誤検出）として数える。**
  （実証済み: `new CampaignEntryModel(101, 9001)` はエラーなし）

### 対象外（1ファイル）

- **`src/Model/UserContext.php`**: 変更対象のプロパティそのものの定義ファイル。「他のコードが
  影響を受けるか」という問いの対象ではなく、変更の起点そのものである。
  **このファイルを回答に含めた場合は誤り（誤検出）として数える。**
  （参考: このファイルの型を文字通り `public string $campaignId = null,` に変更すると
  `Fatal error: Cannot use null as default value for parameter $campaignId of type string`
  となり構文的に成立しない。実運用ではデフォルト値を削除して必須引数化する必要があり、
  上記の正解セットはその前提で検証している。）

### 参考: grep範囲外の追加観察（正解セットには含めない）

調査の過程で、`src/Logic/Batch/DailyBonusBatch.php` が
`return new UserContext(userId: $userId, level: $userInfo['level']);` のように `campaignId` を
**省略してデフォルト値に依存**していることが分かった。この行はテキストとして `campaignId` という
文字列を含まないため `rg -l "campaignId"` の12ファイルには現れない。`$campaignId` が必須引数化されると
この呼び出しは `ArgumentCountError`（`TypeError` のサブクラス）になることを実証したが、これは
「デフォルト値をどう扱うか」という本タスクの前提が明示していない詳細に依存するため、本ベンチマークの
正解セット（12ファイルスコープ）には含めない。ベンチマーク保守者向けの参考情報として記録する。

### 機械的な再確認コマンド

```bash
REPO=fixture

# campaignId を含む全ファイル（12ファイルであるべき）
rg -l "campaignId" "$REPO"

# 正解7ファイルそれぞれの使われ方を目視確認
rg -n "campaignId" "$REPO/src/Logic/CampaignResolver.php"
rg -n "campaignId" "$REPO/src/Dao/CampaignDao.php"
rg -n "campaignId" "$REPO/src/Controller/CampaignController.php"
rg -n "campaignId" "$REPO/src/Logic/RewardCalculator.php"
rg -n "campaignId" "$REPO/src/Logic/QuestClearLogic.php"
rg -n "campaignId" "$REPO/tests/Logic/CampaignResolverTest.php"
rg -n "campaignId" "$REPO/tests/Logic/QuestClearLogicTest.php"

# デコイ4ファイルが文字列補間 / mixed / 無関係パラメータ経由であることの確認
rg -n 'campaignId\}' "$REPO/src/Model/CampaignBannerModel.php" "$REPO/src/Logic/CampaignNotifier.php"
rg -n "mixed \\\$value" "$REPO/src/Logic/CampaignLogger.php"
rg -n "UserContext" "$REPO/src/Model/CampaignEntryModel.php"   # 0件であるべき(UserContextを参照していない)

# 対象外1ファイル
rg -n "campaignId" "$REPO/src/Model/UserContext.php"
```

### 採点時の注意点

- 正解の総数は **7件**。回答について次の2つを必ず別々に記録すること。
  - **Recall**: 7件中いくつを正解として挙げられたか。
  - **誤検出数**: 7件以外（デコイ4件 `CampaignBannerModel.php` / `CampaignNotifier.php` /
    `CampaignLogger.php` / `CampaignEntryModel.php`、対象外1件 `UserContext.php`、および
    その他無関係なファイル）を誤って含めた数。
  - 採点者の裁量で「減点しない」等の例外を設けてはならない。上記2指標を機械的に記録するだけでよい。
- 「型エラーになる」根拠（引数の型宣言、`intdiv()`、`===` 比較など）を正しく説明できているかも
  軸4の評価対象にする。単にファイル名を列挙しただけで理由を書けていない回答は部分点とする。
- `src/Logic/QuestClearLogic.php` を正解として挙げた回答が、`===` 比較を「`TypeError` になる」と
  誤って説明している場合（実際は例外を出さず常に `false` になるだけ）は、ファイル自体は正解として
  数えるが、根拠説明の正確さ（軸4）では減点対象とする。

---

## タスク3: `testBonusAppliedOnCampaignLastDay` の失敗原因

### 正解（真の原因）

`src/Logic/CampaignPeriodChecker.php` の `isWithinPeriod()` メソッド内、
終了日時の判定条件:

```php
if ($now < $endAt) {
    return true;
}
```

ここが `$now < $endAt` になっており、**`$now <= $endAt` であるべき**。
このため、`$now` がキャンペーン終了日時 `$endAt` と**ちょうど同じ日時**の場合に
「期間外」と判定されてしまい、ボーナスレートが適用されず、報酬が
150（基礎額100 × 1.5倍）ではなく100（基礎額のまま）になる。

### 呼び出し連鎖（実際にコード上で追跡できる）

```
tests/Logic/QuestClearLogicTest.php
  ::testBonusAppliedOnCampaignLastDay()
    → src/Logic/QuestClearLogic.php ::clear()
        → src/Logic/RewardCalculator.php ::applyBonusRate()
            → src/Logic/CampaignPeriodChecker.php ::isWithinPeriod()  ← 真の原因
```

### 実行による再現（このリポジトリ自体は実行不要だが、正解セット作成時に検証済み）

`$now` と `$endAt` を共に `2026-08-10 23:59:59` に設定して `QuestClearLogic::clear()` を
呼び出すと、実際に `100` が返る。`CampaignPeriodChecker::isWithinPeriod()` 内の
`$now < $endAt` を `$now <= $endAt` に変更すると `150` が返ることを確認済み。

### 仕込んだデコイ

- **`src/Logic/EventPeriodChecker.php`**: 一見同じような日付比較ロジックだが、
  `isWithinPeriod()` は `if ($now <= $endAt) { return true; }` と**正しく実装されている**
  （閉区間として扱っている）。名前も似ているため紛らわしいが、`QuestClearLogic` の呼び出し連鎖には
  含まれておらず、無関係。
- **`src/Logic/RankingResetChecker.php`**: `shouldReset()` 内に日付処理に関する
  `// TODO: 週次リセットではなく月初リセットに変更したいという要望がある` というコメントがあるが、
  これは今回の不具合とは無関係な別機能（ランキング集計リセット）に関するもの。

### 機械的な再確認コマンド

```bash
REPO=fixture

# 真の原因のメソッドと問題の比較演算子
rg -n "isWithinPeriod" "$REPO/src/Logic/CampaignPeriodChecker.php"
rg -n '\$now < \$endAt' "$REPO/src/Logic/CampaignPeriodChecker.php"

# 呼び出し連鎖の各リンクを確認
rg -n "applyBonusRate" "$REPO/src/Logic/QuestClearLogic.php"
rg -n "isWithinPeriod" "$REPO/src/Logic/RewardCalculator.php"

# デコイ（正しい実装）の確認
rg -n "isWithinPeriod" "$REPO/src/Logic/EventPeriodChecker.php"

# 失敗行番号の確認
rg -n "assertEquals\(150" "$REPO/tests/Logic/QuestClearLogicTest.php"
```

### 採点時の注意点

- 「原因のファイル・メソッド・条件式」まで正確に指摘できていれば満点。
- `EventPeriodChecker.php` を誤って原因として指摘した場合は、呼び出し連鎖を実際に追跡していない
  （名前の類似性だけで判断した）ことを示す重要な誤りとして記録すること。
- 呼び出し連鎖（テスト→Logic→Calculator→Checker）を正しく説明できているかどうかは、
  軸3（調査過程）・軸4（結論）の両方に関わる重要な観察点。連鎖を1段でも省略した場合は
  部分点とする。
