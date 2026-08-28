#!/usr/bin/env bash
#
# sweep.sh
#
# ローカルLLM(Ollama)のベンチマーク測定を全自動化するスクリプト。
#
# 【設計方針】
# - コンテキスト長の切り替えは `OLLAMA_CONTEXT_LENGTH=<N> ollama serve` という
#   「プロセス起動時の環境変数」で行う。~/.zshrc や .claude/settings.json は
#   一切書き換えない。これにより設定ファイルの書き換え事故のリスクをゼロにする。
# - OLLAMA_CONTEXT_LENGTH はサーバー全体に効く設定のため、コンテキスト長を
#   変えるにはサーバーの再起動が必要。そのため
#     外側ループ = コンテキスト長(4段階)
#     内側ループ = モデル(3種)
#   という構造にして、サーバー再起動を 12 回ではなく 4 回に抑える。
# - モデル間の相互汚染防止のため、OLLAMA_MAX_LOADED_MODELS=1 の自動アンロードに
#   加えて、各モデルの測定完了後に明示的に `ollama stop <model>` を実行する。
#   前のモデルが VRAM に残っていると、次のモデルが不当に CPU へ溢れて
#   測定値が汚染されるため。
# - bash 3.2 (macOS標準) 互換で書く。連想配列(declare -A)は使わず、
#   索引配列(RESULT_MODEL[] / RESULT_CONTEXT[] / ...)を並列に保持する
#   索引対応表として結果を管理する。
#
# 実行環境:
#   - macOS(Darwin) / bin/bash 3.2.57
#   - sed -i はBSD系のため使用しない(このスクリプトでは sed -i は使わない)
#   - jq は /usr/bin/jq を想定するが、本スクリプトでは jq を必須にしない
#
# 実行方法:
#   人間が通常のターミナルから直接実行するか、リポジトリのルートで起動した
#   Claude Codeのセッションから `benchmark-run` Skill経由で実行する。
#
# 注意: Claude Codeのセッションから実行する場合、`auto mode`(起動時に
#      `claude --permission-mode auto`、またはセッション内で Shift+Tab)が必要になる。
#      このスクリプトは `ollama serve` でポートをbind(listen)するが、
#      サンドボックスがbindを拒否するため(`bind: operation not permitted`)、
#      サンドボックス外での実行が必要になる。`sandbox.network.allowedDomains` は
#      外向きの接続にのみ適用され、bindには効かないことを実測で確認済み。
#      `auto mode` ならサンドボックス解除の確認が自動処理されて通る。

set -euo pipefail

# ===========================================================================
# 共有の定数・関数(パス、モデルテーブル、サーバー状態確認、run_with_timeout 等)
# ===========================================================================

source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

# ===========================================================================
# 定数(このスクリプト固有のものだけをここに置く)
# ===========================================================================

# 既定の測定対象モデルは lib/common.sh のモデルテーブルから導出する
# (モデルを追加する際に2箇所を揃える必要をなくすため)。
# 各モデルを候補に選んだ経緯は docs/spec.md を参照。
readonly DEFAULT_MODELS_CSV="$(model_names_csv)"
readonly DEFAULT_CONTEXTS_CSV="32768,65536,131072,262144"
readonly DEFAULT_RUNS=4

# 固定プロンプト: 200〜500トークン程度の生成を誘発し、eval rateを安定させるため
# あえてこの程度の分量のタスクを与える("test"等の短文だと生成トークン数が
# 少なすぎてeval rateが安定しない)。
readonly FIXED_PROMPT='PHPで、メールアドレスを検証するバリデータクラスを1つ書いてください。空文字・@の有無・ドメイン部の形式をそれぞれチェックし、異なるエラーメッセージを返すようにしてください。PHPDocコメントも付けてください。'

readonly MODEL_LOAD_TIMEOUT_SEC=180      # ウォームアップロードの最大待ち秒数
readonly RUN_TIMEOUT_SEC=180             # 1回の生成測定の最大待ち秒数

# ===========================================================================
# ユーティリティ関数
# ===========================================================================

# 使い方(--help)を表示する
show_help() {
  cat <<'EOF'
使い方:
  ./sweep.sh [オプション]

概要:
  ローカルLLM(Ollama)のベンチマークを全自動で測定する。
  「3モデル × 4段階のコンテキスト長」の全組について、生成速度(tokens/sec)と
  100% GPUを維持できる実用的なコンテキスト上限を測定し、Markdownの結果表を
  生成する。

オプション:
  --models "a,b,c"    測定対象モデルをカンマ区切りで指定する(既定: 3モデル全部)
  --contexts "N,N"     測定対象コンテキスト長をカンマ区切りで指定する(既定: 4段階全部)
  --runs N              1組あたりの測定回数(既定4。1回目は必ず破棄するため2以上を指定)
  --output PATH         結果ファイルの出力先(既定: results/benchmark-results-<日時>.md)
  --think <値>          ollama run に渡す --think の値(false/true/low/medium/high)。
                         省略時は --think フラグを一切付けず、Ollamaの既定動作
                         (対応モデルはthinkingが既定で有効)に任せる。
                         【使い分けの指針】
                         eval rate(1トークンあたりの生成速度)はthinkingの有無で
                         ほとんど変わらないが、生成トークン数(eval count)は
                         thinkingが有効だと大きく増える。実際の待ち時間は
                         「生成トークン数 ÷ eval rate」で決まるため、thinkingの
                         有無で体感速度は大きく変わる。false/low/medium/high を
                         使い分けて、この影響を切り分けて測定したい場合に使う。
                         注意: thinkingに対応していないモデルに --think を渡すと
                         ollama run がエラーになる可能性がある。対応状況はモデル
                         ごとに異なるため、--models と組み合わせて使う際は
                         対応モデルだけを指定するなど使い分けが必要。
  --force               既存のollama serveを停止してから続行する
  --dry-run              実際には測定せず、何を何組測定するかの計画だけ表示する
  --help                 この使い方を表示する

既定のモデル:
  gemma4:26b, qwen3-coder:30b, qwen3.8:27b

既定のコンテキスト長:
  32768, 65536, 131072, 262144

注意:
  - 本スクリプトは ~/.zshrc や .claude/settings.json を一切書き換えない。
    コンテキスト長は OLLAMA_CONTEXT_LENGTH 環境変数でプロセス起動時に切り替える。
  - 別ターミナルで手動起動中の ollama serve がある場合は、エラーで停止する。
    --force を付けるとそれを停止してから続行する。
  - 終了時(正常終了・異常終了・Ctrl+Cのいずれでも)、本スクリプトが自分で
    起動したollama serveプロセスは確実に停止する。
EOF
}

# サーバーの状態確認(is_server_running / wait_for_server_ready /
# wait_for_server_stopped)と run_with_timeout は lib/common.sh にある。

# 文字列の前後の空白を除去して標準出力に返す
trim() {
  echo "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# ===========================================================================
# サーバーライフサイクル管理
# ===========================================================================

# 自分が起動したサーバーを停止する。既に起動していない場合は何もしない。
stop_server() {
  if [ -n "${SERVER_PID:-}" ] && [ "${STARTED_BY_SCRIPT:-0}" -eq 1 ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
    STARTED_BY_SCRIPT=0
  fi
}

# スクリプト終了時(正常終了・異常終了・Ctrl+Cのいずれでも)に必ず呼ばれるクリーンアップ。
# trapで登録して使う。
cleanup_and_exit() {
  stop_server
  echo ""
  echo "本番設定でOllamaを使うには、別ターミナルで \`source ~/.zshrc && ollama serve\` を実行してください。"
}

# 指定したコンテキスト長でOllamaサーバーをバックグラウンド起動し、応答可能になるまで待つ
start_server() {
  local ctx="$1"
  local logfile="$2"
  OLLAMA_CONTEXT_LENGTH="$ctx" ollama serve >"$logfile" 2>&1 &
  SERVER_PID=$!
  STARTED_BY_SCRIPT=1
  if ! wait_for_server_ready; then
    echo "エラー: コンテキスト長 ${ctx} でのサーバー起動がタイムアウトしました(ログ: ${logfile})" >&2
    diagnose_server_start_failure
    return 1
  fi
  return 0
}

# 既存のollama serveとの衝突を回避するための事前チェック。
# 動いていれば --force 無しはエラー終了、--force 有りなら停止してから続行する。
preflight_check_existing_server() {
  if is_server_running; then
    if [ "$FORCE" -eq 1 ]; then
      echo "既存の ollama serve を検出しました。--force が指定されているため停止します。"
      pkill -f "ollama serve" || true
      if ! wait_for_server_stopped; then
        echo "エラー: 既存の ollama serve の停止がタイムアウトしました。手動で停止してから再実行してください。" >&2
        exit 1
      fi
    else
      echo "エラー: 既存の ollama serve が動作中です。" >&2
      echo "別ターミナルで動いている ollama serve を Ctrl+C で停止してから再実行してください。" >&2
      echo "(既存プロセスを自動停止して続行したい場合は --force を付けてください)" >&2
      exit 1
    fi
  fi
}

# ===========================================================================
# 測定処理
# ===========================================================================

# `ollama ps` の該当行から SIZE / PROCESSOR / CONTEXT を抽出する。
# 出力形式: "SIZE|PROCESSOR|CONTEXT" (該当なしはすべて "-")
#
# 実機の `ollama ps` の列構成は以下の通り(NAMEの次に12桁程度の16進数のID列がある):
#   NAME  ID  SIZE(数値)  SIZE(単位)  PROCESSOR(可変語数)  CONTEXT  UNTIL(可変語数)
#   例: gemma4:26b 5571076f3d70 17 GB 100% GPU 32768 4 minutes from now
#   例: qwen3-coder:30b 06c1097efce0 32 GB 12%/88% CPU/GPU 262144 4 minutes from now
#
# ID列の存在を前提に、$1=NAME, $2=ID, $3=SIZE数値, $4=SIZE単位(GB/MB等)は
# 固定位置として確定させる。PROCESSOR列は "100% GPU"(2語) や
# "12%/88% CPU/GPU"(2語)のように語数がケースによって変わり得るため、
# 「CONTEXT列は素の整数(%記号も単位も付かない)」という性質を手がかりに、
# SIZE単位より後で最初に現れる「純粋な整数トークン」をCONTEXT列とみなし、
# その手前($5以降)をすべてPROCESSOR列として連結する(GPU/CPUの語数に
# 依存しない実装)。UNTIL列の先頭も"4 minutes..."のように整数から始まる
# ことがあるが、CONTEXT列より手前で先に整数トークンにマッチするため
# 誤って先に検出されることはない。
parse_ps_line() {
  local line="$1"
  echo "$line" | awk '{
    size = $3 " " $4
    ctx_idx = 0
    for (i = 5; i <= NF; i++) {
      if ($i ~ /^[0-9]+$/) { ctx_idx = i; break }
    }
    if (ctx_idx == 0) {
      print size "|-|-"
      next
    }
    proc = ""
    for (i = 5; i < ctx_idx; i++) {
      proc = proc (proc == "" ? "" : " ") $i
    }
    context = $ctx_idx
    print size "|" proc "|" context
  }'
}

# `ollama run --verbose` の出力(stdout+stderrを結合したファイル)から eval rate を抽出する。
# "prompt eval rate:" に誤マッチしないよう、行頭が "eval rate:" のものだけを取る。
extract_eval_rate() {
  local outfile="$1"
  grep -E '^eval rate:' "$outfile" 2>/dev/null | awk '{print $3}' | head -n1 || true
}

# `ollama run --verbose` の出力から eval count(生成トークン数)を抽出する。
# 「eval rate」(1トークンあたりの生成速度)と「eval count」(生成した総トークン数)は
# 別の指標であり、実際の待ち時間は両者を掛け合わせないと分からない(thinkingモードは
# eval rateにはほとんど影響しないが、eval countを大きく増やすため)。
# "prompt eval count:" に誤マッチしないよう、行頭が "eval count:" のものだけを取る。
# 値は "29 token(s)" の形式なので、単位を除いた数値部分(第3フィールド)のみ取る。
extract_eval_count() {
  local outfile="$1"
  grep -E '^eval count:' "$outfile" 2>/dev/null | awk '{print $3}' | head -n1 || true
}

# RESULT_* 配列(索引対応表)へ1件追加する
append_result() {
  RESULT_MODEL+=("$1")
  RESULT_CONTEXT+=("$2")
  RESULT_STATUS+=("$3")
  RESULT_SIZE+=("$4")
  RESULT_PROCESSOR+=("$5")
  RESULT_TOKPS+=("$6")
  RESULT_TOKCOUNT+=("$7")
  RESULT_REASON+=("$8")
}

# thinkingモード(--think)の指定有無に応じて `ollama run` の warmup 実行を行う。
# --think が未指定の場合はフラグを一切付けず、Ollamaの既定動作(対応モデルは
# thinking有効)に任せる。既存の測定条件を変えないため、これは必須の分岐。
run_ollama_warmup() {
  local model="$1"
  if [ -n "$THINK_MODE" ]; then
    run_with_timeout "$MODEL_LOAD_TIMEOUT_SEC" ollama run "$model" "--think=${THINK_MODE}" "warmup" >/dev/null 2>&1
  else
    run_with_timeout "$MODEL_LOAD_TIMEOUT_SEC" ollama run "$model" "warmup" >/dev/null 2>&1
  fi
}

# thinkingモード(--think)の指定有無に応じて `ollama run --verbose` の測定実行を行う。
# 出力は $tmpfile に書き出す(呼び出し側で eval rate / eval count を抽出する)。
run_ollama_measure() {
  local model="$1"
  local tmpfile="$2"
  if [ -n "$THINK_MODE" ]; then
    run_with_timeout "$RUN_TIMEOUT_SEC" ollama run "$model" "--think=${THINK_MODE}" "$FIXED_PROMPT" --verbose >"$tmpfile" 2>&1
  else
    run_with_timeout "$RUN_TIMEOUT_SEC" ollama run "$model" "$FIXED_PROMPT" --verbose >"$tmpfile" 2>&1
  fi
}

# 1組(モデル×コンテキスト長)の測定を行い、RESULT_*配列へ結果を追加する。
# 成功時0、失敗時1を返す(スクリプト全体は止めない)。
measure_one() {
  local model="$1"
  local ctx="$2"

  # --- 1. モデルをロードする(ウォームアップ) ---
  if ! run_ollama_warmup "$model"; then
    local warmup_reason="モデルのロードに失敗(warmup実行エラーまたはタイムアウト)"
    # --think指定時は、対象モデルがthinking非対応で ollama run 自体がエラーに
    # なった可能性があるため、原因調査の手がかりとしてその旨を付記する。
    if [ -n "$THINK_MODE" ]; then
      warmup_reason="${warmup_reason}(--think=${THINK_MODE} 指定が原因の可能性あり。このモデルがthinkingオプションに非対応の場合、ollama runがエラーになることがある)"
    fi
    append_result "$model" "$ctx" "fail" "-" "-" "-" "-" "$warmup_reason"
    return 1
  fi

  # --- 2. `ollama ps` からSIZE/PROCESSOR/CONTEXTを抽出する ---
  local ps_line
  ps_line="$(ollama ps 2>/dev/null | grep -F -- "$model" | head -n1 || true)"
  if [ -z "$ps_line" ]; then
    ollama stop "$model" >/dev/null 2>&1 || true
    append_result "$model" "$ctx" "fail" "-" "-" "-" "-" "ollama ps に該当モデルが表示されない(ロード直後にアンロードされた可能性)"
    return 1
  fi

  local parsed size processor
  parsed="$(parse_ps_line "$ps_line")"
  size="$(echo "$parsed" | cut -d'|' -f1)"
  processor="$(echo "$parsed" | cut -d'|' -f2)"

  # --- 3. 固定プロンプトで RUNS 回実行し、eval rate と eval count を収集する(1回目は破棄) ---
  # eval rate(1トークンあたりの生成速度)と eval count(生成した総トークン数)は
  # 別の指標であるため、両方を同じ実行から対で収集する(rates/countsは常に同じ長さになる)。
  local rates=()
  local counts=()
  local i=1
  while [ "$i" -le "$RUNS" ]; do
    local tmpfile
    tmpfile="$(mktemp "${TMPDIR:-/tmp}/ollama_run.XXXXXX")"
    if run_ollama_measure "$model" "$tmpfile"; then
      local rate count_val
      rate="$(extract_eval_rate "$tmpfile")"
      count_val="$(extract_eval_count "$tmpfile")"
      if [ -n "$rate" ] && [ -n "$count_val" ] && [ "$i" -gt 1 ]; then
        rates+=("$rate")
        counts+=("$count_val")
      fi
    fi
    rm -f "$tmpfile" 2>/dev/null || true
    i=$((i + 1))
  done

  # --- 5. モデルをアンロードする(次モデルへの汚染防止のため明示的に実行) ---
  ollama stop "$model" >/dev/null 2>&1 || true

  # --- 4. 1回目を除いた平均を算出する ---
  local count=${#rates[@]}
  if [ "$count" -eq 0 ]; then
    local fail_reason="eval rate/eval countを取得できず(生成失敗・タイムアウト、または出力形式不一致)"
    if [ -n "$THINK_MODE" ]; then
      fail_reason="${fail_reason}(--think=${THINK_MODE} 指定が原因の可能性あり。このモデルがthinkingオプションに非対応の場合、ollama runがエラーになることがある)"
    fi
    append_result "$model" "$ctx" "fail" "$size" "$processor" "-" "-" "$fail_reason"
    return 1
  fi

  local sum=0
  local j=0
  while [ "$j" -lt "$count" ]; do
    sum="$(awk -v a="$sum" -v b="${rates[$j]}" 'BEGIN { printf "%.6f", a + b }')"
    j=$((j + 1))
  done
  local avg
  avg="$(awk -v s="$sum" -v c="$count" 'BEGIN { printf "%.2f", s / c }')"

  # eval countの平均(整数のトークン数として丸める)
  local tok_sum=0
  j=0
  while [ "$j" -lt "$count" ]; do
    tok_sum="$(awk -v a="$tok_sum" -v b="${counts[$j]}" 'BEGIN { printf "%.6f", a + b }')"
    j=$((j + 1))
  done
  local avg_tokcount
  avg_tokcount="$(awk -v s="$tok_sum" -v c="$count" 'BEGIN { printf "%.0f", s / c }')"

  append_result "$model" "$ctx" "ok" "$size" "$processor" "$avg" "$avg_tokcount" "-"
  return 0
}

# ===========================================================================
# 結果検索・レポート生成
# ===========================================================================

# RESULT_*配列からモデル+コンテキスト長に該当する索引を探す(無ければ-1)
find_result_index() {
  local m="$1"
  local c="$2"
  local n=${#RESULT_MODEL[@]}
  local i=0
  while [ "$i" -lt "$n" ]; do
    if [ "${RESULT_MODEL[$i]}" = "$m" ] && [ "${RESULT_CONTEXT[$i]}" = "$c" ]; then
      echo "$i"
      return 0
    fi
    i=$((i + 1))
  done
  echo "-1"
}

# 測定結果をMarkdownファイルに書き出す
generate_report() {
  local out="$1"

  {
    echo "# Ollamaベンチマーク測定結果"
    echo ""
    echo "- 実行日時: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "- 測定回数(1組あたり): ${RUNS}回 (1回目はモデルロード直後でload durationが大きく不公平なため破棄し、残り$((RUNS - 1))回の平均を採用)"
    # thinkingモード設定を明記する。条件の異なる結果ファイルを後で見比べる際に
    # 混同しないため(thinkingの有無でeval rateはほぼ変わらないが生成トークン数が
    # 大きく変わり、実際の待ち時間に直結するため必須の記載)。
    if [ -n "$THINK_MODE" ]; then
      echo "- thinkingモード(--think): ${THINK_MODE} (\`--think=${THINK_MODE}\` を明示的に指定)"
    else
      echo "- thinkingモード(--think): 未指定(Ollamaの既定動作に従う。対応モデルはthinkingが既定で有効)"
    fi
    echo "- 固定プロンプト:"
    echo ""
    echo '```'
    echo "$FIXED_PROMPT"
    echo '```'
    echo ""

    echo "## モデル × コンテキスト長 マトリクス"
    echo ""
    echo "各セルは \`PROCESSOR / SIZE / tokens/sec / 生成トークン数\` の形式。測定失敗は「失敗」と表示。"
    echo "(生成トークン数は eval count の1回目を除いた平均。thinkingが有効なモデルはこの値が"
    echo "大きくなり、eval rateが同程度でも実際の待ち時間は長くなる。詳細は下記セクション参照)"
    echo ""

    # ヘッダ行
    local header="| モデル |"
    local ctx
    for ctx in "${CONTEXTS[@]}"; do
      header="${header} ${ctx} |"
    done
    echo "$header"

    local sep="|---|"
    local ci=0
    while [ "$ci" -lt "${#CONTEXTS[@]}" ]; do
      sep="${sep}---|"
      ci=$((ci + 1))
    done
    echo "$sep"

    local model
    for model in "${MODELS[@]}"; do
      local row="| ${model} |"
      for ctx in "${CONTEXTS[@]}"; do
        local idx
        idx="$(find_result_index "$model" "$ctx")"
        if [ "$idx" -lt 0 ]; then
          row="${row} (未測定) |"
        elif [ "${RESULT_STATUS[$idx]}" = "ok" ]; then
          row="${row} ${RESULT_PROCESSOR[$idx]} / ${RESULT_SIZE[$idx]} / ${RESULT_TOKPS[$idx]} tok/s / ${RESULT_TOKCOUNT[$idx]} tok |"
        else
          row="${row} 失敗 |"
        fi
      done
      echo "$row"
    done
    echo ""

    echo "## 実際の待ち時間の比較(生成トークン数 ÷ eval rate)"
    echo ""
    echo "\`eval rate\`は「1トークンあたりの生成速度」であり、thinkingモードの有無で"
    echo "ほとんど変化しない。一方でthinkingは「生成するトークンの総量」(\`eval count\`)を"
    echo "増やすため、\`eval rate\`だけを見ていても実際の待ち時間の悪化はわからない。"
    echo "実際の待ち時間は「生成トークン数 ÷ eval rate」で決まり、これが体感速度に"
    echo "直結する指標である。以下は測定に成功した組についてこれを算出したもの。"
    echo ""
    echo "| モデル | コンテキスト長 | 生成トークン数 | eval rate (tok/s) | 実際の待ち時間(秒) |"
    echo "|---|---|---|---|---|"
    for model in "${MODELS[@]}"; do
      for ctx in "${CONTEXTS[@]}"; do
        local idx
        idx="$(find_result_index "$model" "$ctx")"
        if [ "$idx" -ge 0 ] && [ "${RESULT_STATUS[$idx]}" = "ok" ]; then
          local seconds
          seconds="$(awk -v c="${RESULT_TOKCOUNT[$idx]}" -v r="${RESULT_TOKPS[$idx]}" \
            'BEGIN { if (r + 0 > 0) { printf "%.2f", c / r } else { print "-" } }')"
          echo "| ${model} | ${ctx} | ${RESULT_TOKCOUNT[$idx]} | ${RESULT_TOKPS[$idx]} | ${seconds} |"
        fi
      done
    done
    echo ""

    echo "## 実用的なコンテキスト上限のサマリ(モデル別)"
    echo ""
    echo "「100% GPU」を維持できた最大のコンテキスト長と、そのときの速度・SIZE。"
    echo "(CPUへのオフロードが少しでも発生している場合は「100% GPU」とはみなさない)"
    echo ""
    echo "| モデル | 100%GPU維持できた最大コンテキスト長 | そのときのtokens/sec | そのときのSIZE |"
    echo "|---|---|---|---|"
    for model in "${MODELS[@]}"; do
      local best_ctx="-"
      local best_tokps="-"
      local best_size="-"
      for ctx in "${CONTEXTS[@]}"; do
        local idx
        idx="$(find_result_index "$model" "$ctx")"
        if [ "$idx" -ge 0 ] && [ "${RESULT_STATUS[$idx]}" = "ok" ]; then
          case "${RESULT_PROCESSOR[$idx]}" in
            *CPU*)
              : # CPUへのオフロードがあるため100%GPUとはみなさない
              ;;
            *GPU*)
              if [ "$best_ctx" = "-" ] || [ "$ctx" -gt "$best_ctx" ]; then
                best_ctx="$ctx"
                best_tokps="${RESULT_TOKPS[$idx]}"
                best_size="${RESULT_SIZE[$idx]}"
              fi
              ;;
          esac
        fi
      done
      echo "| ${model} | ${best_ctx} | ${best_tokps} | ${best_size} |"
    done
    echo ""

    echo "## SIZE一覧(オーケストレーション構成検討用)"
    echo ""
    echo "「このモデルとこのモデルを同時に載せられるか」を判断する材料として、"
    echo "測定に成功した組のSIZEを一覧にする。"
    echo ""
    echo "| モデル | コンテキスト長 | SIZE |"
    echo "|---|---|---|"
    for model in "${MODELS[@]}"; do
      for ctx in "${CONTEXTS[@]}"; do
        local idx
        idx="$(find_result_index "$model" "$ctx")"
        if [ "$idx" -ge 0 ] && [ "${RESULT_STATUS[$idx]}" = "ok" ]; then
          echo "| ${model} | ${ctx} | ${RESULT_SIZE[$idx]} |"
        fi
      done
    done
    echo ""

    echo "## 測定失敗一覧"
    echo ""
    echo "| モデル | コンテキスト長 | 理由 |"
    echo "|---|---|---|"
    local has_failure=0
    local n=${#RESULT_MODEL[@]}
    local i=0
    while [ "$i" -lt "$n" ]; do
      if [ "${RESULT_STATUS[$i]}" = "fail" ]; then
        echo "| ${RESULT_MODEL[$i]} | ${RESULT_CONTEXT[$i]} | ${RESULT_REASON[$i]} |"
        has_failure=1
      fi
      i=$((i + 1))
    done
    if [ "$has_failure" -eq 0 ]; then
      echo "| (なし) | - | - |"
    fi
  } >"$out"
}

# --dry-run時の実行計画表示
print_dry_run_plan() {
  echo "=== ドライラン: 実行計画 ==="
  echo "対象モデル: ${MODELS[*]}"
  echo "対象コンテキスト長: ${CONTEXTS[*]}"
  echo "1組あたりの測定回数: ${RUNS}回 (1回目は破棄)"
  if [ -n "$THINK_MODE" ]; then
    echo "thinkingモード(--think): ${THINK_MODE} (--think=${THINK_MODE} を指定)"
  else
    echo "thinkingモード(--think): 未指定(Ollama既定動作)"
  fi
  local total=$((${#MODELS[@]} * ${#CONTEXTS[@]}))
  echo "総組数: ${total}"
  echo "サーバー再起動回数: ${#CONTEXTS[@]}回(コンテキスト長ごとに1回)"
  echo ""
  local n=0
  local ctx model
  for ctx in "${CONTEXTS[@]}"; do
    echo "-- コンテキスト長 ${ctx} でサーバー起動 --"
    for model in "${MODELS[@]}"; do
      n=$((n + 1))
      echo "  [${n}/${total}] ${model} @ ${ctx}"
    done
  done
  echo ""
  echo "出力先: ${OUTPUT}"
}

# ===========================================================================
# 測定本体(全組のスイープ)
# ===========================================================================

run_sweep() {
  local total=$((${#MODELS[@]} * ${#CONTEXTS[@]}))
  local n=0
  local ctx model

  for ctx in "${CONTEXTS[@]}"; do
    echo "=== コンテキスト長 ${ctx} でサーバーを起動します ==="
    local logfile
    logfile="$(mktemp "${TMPDIR:-/tmp}/ollama_serve_${ctx}.XXXXXX")"

    if ! start_server "$ctx" "$logfile"; then
      # このコンテキスト長は全モデル失敗として記録し、次のコンテキスト長へ進む
      for model in "${MODELS[@]}"; do
        n=$((n + 1))
        append_result "$model" "$ctx" "fail" "-" "-" "-" "-" "サーバー起動失敗(コンテキスト長 ${ctx})"
        echo "[${n}/${total}] ${model} @ ${ctx} ... サーバー起動失敗"
      done
      stop_server
      continue
    fi

    for model in "${MODELS[@]}"; do
      n=$((n + 1))
      printf '[%d/%d] %s @ %s ... ' "$n" "$total" "$model" "$ctx"
      if measure_one "$model" "$ctx"; then
        local last=$((${#RESULT_TOKPS[@]} - 1))
        echo "${RESULT_PROCESSOR[$last]} / ${RESULT_SIZE[$last]} / ${RESULT_TOKPS[$last]} tok/s / ${RESULT_TOKCOUNT[$last]} tok"
      else
        local last=$((${#RESULT_REASON[@]} - 1))
        echo "測定失敗 (${RESULT_REASON[$last]})"
      fi
    done

    echo "=== コンテキスト長 ${ctx} のサーバーを停止します ==="
    stop_server
  done
}

# ===========================================================================
# 引数解析
# ===========================================================================

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --models)
        [ $# -ge 2 ] || { echo "エラー: --models には値が必要です" >&2; exit 1; }
        MODELS_CSV="$2"
        shift 2
        ;;
      --contexts)
        [ $# -ge 2 ] || { echo "エラー: --contexts には値が必要です" >&2; exit 1; }
        CONTEXTS_CSV="$2"
        shift 2
        ;;
      --runs)
        [ $# -ge 2 ] || { echo "エラー: --runs には値が必要です" >&2; exit 1; }
        RUNS="$2"
        shift 2
        ;;
      --output)
        [ $# -ge 2 ] || { echo "エラー: --output には値が必要です" >&2; exit 1; }
        OUTPUT="$2"
        shift 2
        ;;
      --think)
        [ $# -ge 2 ] || { echo "エラー: --think には値が必要です" >&2; exit 1; }
        THINK_MODE="$2"
        shift 2
        ;;
      --force)
        FORCE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        echo "エラー: 不明なオプション: $1" >&2
        show_help
        exit 1
        ;;
    esac
  done
}

# 入力値の検証とCSVから配列への変換
validate_and_build_arrays() {
  IFS=',' read -ra MODELS <<<"$MODELS_CSV"
  IFS=',' read -ra CONTEXTS <<<"$CONTEXTS_CSV"

  local i=0
  while [ "$i" -lt "${#MODELS[@]}" ]; do
    MODELS[$i]="$(trim "${MODELS[$i]}")"
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "${#CONTEXTS[@]}" ]; do
    CONTEXTS[$i]="$(trim "${CONTEXTS[$i]}")"
    i=$((i + 1))
  done

  if [ "${#MODELS[@]}" -eq 0 ] || [ -z "${MODELS[0]}" ]; then
    echo "エラー: --models に有効なモデルが指定されていません" >&2
    exit 1
  fi
  if [ "${#CONTEXTS[@]}" -eq 0 ] || [ -z "${CONTEXTS[0]}" ]; then
    echo "エラー: --contexts に有効なコンテキスト長が指定されていません" >&2
    exit 1
  fi

  i=0
  while [ "$i" -lt "${#CONTEXTS[@]}" ]; do
    case "${CONTEXTS[$i]}" in
      ''|*[!0-9]*)
        echo "エラー: コンテキスト長は正整数で指定してください: ${CONTEXTS[$i]}" >&2
        exit 1
        ;;
    esac
    i=$((i + 1))
  done

  case "$RUNS" in
    ''|*[!0-9]*)
      echo "エラー: --runs は正整数で指定してください" >&2
      exit 1
      ;;
  esac
  if [ "$RUNS" -lt 2 ]; then
    echo "エラー: --runs は2以上を指定してください(1回目は必ず破棄するため)" >&2
    exit 1
  fi

  # --think は未指定(空文字、既定動作に任せる)、または以下の5値のみ許可する。
  # Ollama公式ドキュメントで確認済みの --think の受理値。
  case "$THINK_MODE" in
    ""|false|true|low|medium|high)
      ;;
    *)
      echo "エラー: --think には false/true/low/medium/high のいずれかを指定してください: ${THINK_MODE}" >&2
      exit 1
      ;;
  esac
}

# ===========================================================================
# メイン処理
# ===========================================================================

main() {
  MODELS_CSV="$DEFAULT_MODELS_CSV"
  CONTEXTS_CSV="$DEFAULT_CONTEXTS_CSV"
  RUNS="$DEFAULT_RUNS"
  mkdir -p "${RESULTS_DIR}"
  OUTPUT="${RESULTS_DIR}/benchmark-results-$(date +%Y%m%d-%H%M%S).md"
  FORCE=0
  DRY_RUN=0
  # --think未指定時は空文字。この場合 run_ollama_warmup/run_ollama_measure は
  # --think フラグを一切付けず、Ollamaの既定動作(現行の測定と同条件)を維持する。
  THINK_MODE=""
  SERVER_PID=""
  STARTED_BY_SCRIPT=0

  RESULT_MODEL=()
  RESULT_CONTEXT=()
  RESULT_STATUS=()
  RESULT_SIZE=()
  RESULT_PROCESSOR=()
  RESULT_TOKPS=()
  RESULT_TOKCOUNT=()
  RESULT_REASON=()

  parse_args "$@"
  validate_and_build_arrays

  if [ "$DRY_RUN" -eq 1 ]; then
    print_dry_run_plan
    exit 0
  fi

  # 測定対象がすべて取得済みであることを確認する。1つでも未取得なら停止する。
  # このスクリプトは各モデルに対して `ollama run` を実行するが、`ollama run` は
  # 未取得のモデルを自動でネットワークから取得してしまう。人間の確認を経ない
  # ダウンロードを避けるため、測定を1件も開始する前にここで弾く。
  require_models_pulled "${MODELS[@]}"

  # 終了時(正常・異常・Ctrl+Cのいずれでも)に自分が起動したサーバーを確実に停止する
  trap cleanup_and_exit EXIT INT TERM

  preflight_check_existing_server

  run_sweep

  generate_report "$OUTPUT"
  echo ""
  echo "結果を出力しました: ${OUTPUT}"
}

main "$@"
