#!/usr/bin/env bash
#
# prepare.sh
#
# ローカルLLM(Ollama)ベンチマーク検証用に、モデルの切り替えからOllamaサーバーの
# 起動・ウォームアップ・検証までを1コマンドで行うスクリプト。
#
# 【最重要の設計方針: ~/.zshrc を一切書き換えない】
#   コンテキスト長(OLLAMA_CONTEXT_LENGTH)とOLLAMA_KEEP_ALIVEは、
#   `ollama serve` を起動する際に「プロセスの環境変数」として渡す
#   (`OLLAMA_CONTEXT_LENGTH=N OLLAMA_KEEP_ALIVE=DUR ollama serve` の形)。
#   ~/.zshrc のような永続設定ファイルを書き換えないことで、
#     - 書き換え事故(他の設定を巻き添えで壊す、書き戻し忘れ等)のリスクがゼロになる
#     - 検証後の「復元」作業が原理的に不要になる(そもそも何も変えていないため)
#   という2つの利点が得られる。bin/restore.sh もこの前提に立っている(復元処理が不要になる)。
#
# 実行環境:
#   - macOS(Darwin) / bin/bash 3.2.57 互換で書く(連想配列 declare -A は使わない)
#   - sed -i はBSD系のため使わない(このスクリプトではjqとcatでのみJSONを書き換える)
#   - jq は /usr/bin/jq を想定
#   - 人間が通常のターミナルから実行する想定。Claude Codeのエージェント経由では、
#     サンドボックスのlocalhost遮断によりollamaコマンドが使えないため動作しない。
#
# 実行場所: このリポジトリのルートディレクトリ(相対パスはスクリプト自身の位置から解決する)。
#
set -euo pipefail

# ============================================================
# 設定値(冒頭にまとめる。ハードコーディングを避けるため既定値はここでのみ定義)
# ============================================================

# スクリプト自身の位置からリポジトリのルートを解決する(実行時のカレントディレクトリに依存しないため)。
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly BENCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly SETTINGS_JSON="${BENCH_ROOT}/fixture/.claude/settings.json"
readonly RESULTS_DIR="${BENCH_ROOT}/results"
readonly SERVE_LOG="${RESULTS_DIR}/ollama-serve.log"
readonly PID_FILE="${RESULTS_DIR}/.ollama.pid"

# モデル名 -> コンテキスト長(実機で確認済みの実測値)のテーブル。
# bash 3.2 (macOS標準)は連想配列(declare -A)を使えないため、
# 「モデル名の配列」と「コンテキスト長の配列」を対で持つ索引配列テーブルにしている。
readonly MODEL_TABLE_NAMES=("gemma4:26b" "qwen3-coder:30b" "qwen3.8:27b")
readonly MODEL_TABLE_CONTEXTS=("262144" "131072" "131072")

# CLAUDE_CODE_AUTO_COMPACT_WINDOW をコンテキスト長から算出するための比率。
# 由来: 本番値 115000 / 131072 ≈ 0.877
# 検算: 131072 * 0.877 ≈ 114950 -> 1000単位丸めで115000(本番値と一致)
#       262144 * 0.877 ≈ 229900 -> 1000単位丸めで230000
readonly AUTO_COMPACT_RATIO="0.877"

# OLLAMA_KEEP_ALIVEの既定値。軸3・4のタスクは人間の確認待ちでアイドルが発生しやすく、
# Ollamaの既定値(5分)だとモデルがアンロードされて再ロード時間が発生し、
# モデル間の比較が不公平になるため30分にしている(詳細はヘルプ参照)。
readonly DEFAULT_KEEP_ALIVE="30m"

readonly SERVER_HOST="127.0.0.1"
readonly SERVER_PORT="11434"
readonly SERVER_READY_TIMEOUT_SEC=90   # サーバー起動待ちの最大秒数
readonly SERVER_STOP_TIMEOUT_SEC=30    # 既存サーバー停止待ちの最大秒数
readonly WARMUP_TIMEOUT_SEC=180        # ウォームアップの最大待ち秒数

# ============================================================
# ユーティリティ関数
# ============================================================

lookup_context_length() {
  local model="$1" i
  for i in "${!MODEL_TABLE_NAMES[@]}"; do
    if [[ "${MODEL_TABLE_NAMES[$i]}" == "${model}" ]]; then
      echo "${MODEL_TABLE_CONTEXTS[$i]}"
      return 0
    fi
  done
  return 1
}

# コンテキスト長からCLAUDE_CODE_AUTO_COMPACT_WINDOWを算出する。
# awkで浮動小数点計算を行い、1000単位で四捨五入する(bash自体は整数演算しかできないため)。
calc_auto_compact_window() {
  local context_length="$1"
  awk -v cl="${context_length}" -v ratio="${AUTO_COMPACT_RATIO}" 'BEGIN {
    raw = cl * ratio
    rounded = int((raw + 500) / 1000) * 1000
    printf "%d", rounded
  }'
}

# 指定したモデル名がollamaにpull済みかどうかを`ollama list`で検証する。
# `ollama list`自体が失敗した場合(サーバー未起動、ollamaコマンドが無い等)は、
# サーバー停止中でも準備を進められるように警告のみで続行する。
check_model_exists() {
  local model="$1"
  local list_output
  if ! list_output="$(ollama list 2>/dev/null)"; then
    echo "警告: 'ollama list' の実行に失敗したため、モデル名の検証をスキップしました。" >&2
    echo "      ('ollama serve' が起動していない、または 'ollama' コマンドが見つからない可能性があります)" >&2
    return 0
  fi

  if ! echo "${list_output}" | awk 'NR>1 {print $1}' | grep -Fxq -- "${model}"; then
    echo "エラー: モデル '${model}' は 'ollama list' の一覧に見つかりませんでした。" >&2
    echo "        モデル名が正しいか確認してください。'ollama list' で確認できます。" >&2
    echo "        未取得の場合は 'ollama pull ${model}' で取得してください。" >&2
    exit 1
  fi
}

# ファイルのタイムスタンプ付きバックアップを作成し、バックアップパスを標準出力に返す。
backup_file() {
  local file="$1"
  local ts backup
  ts="$(date +%Y%m%d-%H%M%S)"
  backup="${file}.bak.${ts}"
  cp -p "${file}" "${backup}"
  echo "${backup}"
}

# fixture/.claude/settings.json をjqで3キーのみパッチする(dry-runの場合は表示のみ)。
# 他のキー(特にpermissions/sandbox)には一切触れない。
# 書き戻す前に、JSONとして妥当か・重要キーが失われていないか・意図した値になっているかを
# 事後検証し、1つでも失敗したら書き戻さずバックアップから復元してエラー終了する。
patch_settings_json() {
  local model="$1" max_tokens="$2" auto_compact="$3" dry_run="$4"
  local tmp old_model old_max old_auto settings_backup

  old_model="$(jq -r '.model // "null"' "${SETTINGS_JSON}")"
  old_max="$(jq -r '.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS // "null"' "${SETTINGS_JSON}")"
  old_auto="$(jq -r '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW // "null"' "${SETTINGS_JSON}")"

  if [[ "${dry_run}" == "true" ]]; then
    echo "  [dry-run] .model: ${old_model} -> ${model}"
    echo "  [dry-run] .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS: ${old_max} -> ${max_tokens}"
    echo "  [dry-run] .env.CLAUDE_CODE_AUTO_COMPACT_WINDOW: ${old_auto} -> ${auto_compact}"
    return 0
  fi

  # dry-runでない場合のみバックアップを作成する。
  settings_backup="$(backup_file "${SETTINGS_JSON}")"
  echo "  バックアップ: ${settings_backup}"

  tmp="$(mktemp)"
  jq \
    --arg model "${model}" \
    --arg max_tokens "${max_tokens}" \
    --arg auto_compact "${auto_compact}" \
    '.model = $model | .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS = $max_tokens | .env.CLAUDE_CODE_AUTO_COMPACT_WINDOW = $auto_compact' \
    "${SETTINGS_JSON}" > "${tmp}"

  local fail_reason=""
  if ! jq empty "${tmp}" 2>/dev/null; then
    fail_reason="パッチ後のJSONが不正です"
  elif [[ "$(jq 'has("permissions")' "${tmp}")" != "true" ]]; then
    fail_reason=".permissions キーが失われています"
  elif [[ "$(jq 'has("sandbox")' "${tmp}")" != "true" ]]; then
    fail_reason=".sandbox キーが失われています"
  elif [[ "$(jq -r '.model' "${tmp}")" != "${model}" ]]; then
    fail_reason=".model が意図した値になっていません"
  fi

  if [[ -n "${fail_reason}" ]]; then
    echo "エラー: ${fail_reason}。書き戻しを中止し、バックアップから復元します。" >&2
    cp -p "${settings_backup}" "${SETTINGS_JSON}"
    rm -f "${tmp}"
    exit 1
  fi

  # mvではなくcatでの上書きにより、既存settings.jsonのinode・パーミッションを保持する
  # (mktempが作るファイルはパーミッション600のため、mvだと権限が意図せず変わってしまう)。
  cat "${tmp}" > "${SETTINGS_JSON}"
  rm -f "${tmp}"
  echo "  .model: ${old_model} -> ${model}"
  echo "  .env.CLAUDE_CODE_MAX_CONTEXT_TOKENS: ${old_max} -> ${max_tokens}"
  echo "  .env.CLAUDE_CODE_AUTO_COMPACT_WINDOW: ${old_auto} -> ${auto_compact}"
}

# 指定ホスト:ポートでOllamaサーバーが応答可能かを確認する
is_server_running() {
  curl -fsS "http://${SERVER_HOST}:${SERVER_PORT}/" >/dev/null 2>&1
}

wait_for_server_ready() {
  local waited=0
  while [ "${waited}" -lt "${SERVER_READY_TIMEOUT_SEC}" ]; do
    if is_server_running; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

wait_for_server_stopped() {
  local waited=0
  while [ "${waited}" -lt "${SERVER_STOP_TIMEOUT_SEC}" ]; do
    if ! is_server_running; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

# 既存の`ollama serve`を停止する。ユーザーが手動起動しているサーバーを止めることに
# なるため、--forceが無い場合はエラーで停止して確認を促す。
stop_existing_server_if_any() {
  local force="$1"
  if ! is_server_running; then
    return 0
  fi

  if [[ "${force}" != "true" ]]; then
    echo "エラー: 既存の 'ollama serve' が動作中です。" >&2
    echo "        このスクリプトは新しいコンテキスト長でサーバーを再起動する必要がありますが、" >&2
    echo "        既存のサーバー(手動起動を含む)を停止してよいか確認できません。" >&2
    echo "        停止してよい場合は --force を付けて再実行してください。" >&2
    exit 1
  fi

  echo "既存の 'ollama serve' を検出しました。--force が指定されているため停止します。"
  pkill -f "ollama serve" || true
  if ! wait_for_server_stopped; then
    echo "エラー: 既存の 'ollama serve' の停止がタイムアウトしました。手動で停止してから再実行してください。" >&2
    exit 1
  fi
}

# ============================================================
# メイン処理
# ============================================================

do_prepare() {
  local model="$1" context_length_arg="$2" keep_alive="$3" force="$4" dry_run="$5"

  # --- 1. モデル名の解決 ---
  local context_length
  if [[ -n "${context_length_arg}" ]]; then
    context_length="${context_length_arg}"
  elif context_length="$(lookup_context_length "${model}")"; then
    : # テーブルから解決できた
  else
    echo "エラー: モデル '${model}' は設定テーブルに存在しないため、コンテキスト長が不明です。" >&2
    echo "        --context-length <値> を指定して明示的に設定してください。" >&2
    echo "        例: $0 ${model} --context-length 131072" >&2
    exit 1
  fi

  if ! [[ "${context_length}" =~ ^[0-9]+$ ]]; then
    echo "エラー: コンテキスト長 '${context_length}' が数値ではありません。" >&2
    exit 1
  fi

  local auto_compact_window
  auto_compact_window="$(calc_auto_compact_window "${context_length}")"

  echo "=== [1/7] モデル名の解決 ==="
  echo "  モデル: ${model}"
  echo "  コンテキスト長: ${context_length}"
  echo "  CLAUDE_CODE_AUTO_COMPACT_WINDOW: ${auto_compact_window}"
  echo ""

  # --- 2. モデルの存在確認 ---
  echo "=== [2/7] モデルの存在確認 ==="
  check_model_exists "${model}"
  echo "  OK"
  echo ""

  # --- 3. settings.json のパッチ ---
  echo "=== [3/7] ${SETTINGS_JSON} のパッチ ==="
  patch_settings_json "${model}" "${context_length}" "${auto_compact_window}" "${dry_run}"
  echo ""

  if [[ "${dry_run}" == "true" ]]; then
    echo "[dry-run] ここまでの内容のみ表示し、サーバーの起動やウォームアップは行いません。"
    echo "[dry-run] ファイルへの書き込み・バックアップ作成は一切行っていません。"
    return 0
  fi

  # --- 4. 既存のollama serveの停止 ---
  echo "=== [4/7] 既存の 'ollama serve' の確認 ==="
  stop_existing_server_if_any "${force}"
  echo "  OK"
  echo ""

  # --- 5. サーバーの起動 ---
  echo "=== [5/7] Ollamaサーバーの起動 ==="
  mkdir -p "${RESULTS_DIR}"
  # OLLAMA_CONTEXT_LENGTH / OLLAMA_KEEP_ALIVE はプロセス環境変数として渡す
  # (スクリプト冒頭の設計方針コメントを参照。~/.zshrcは一切書き換えない)。
  OLLAMA_CONTEXT_LENGTH="${context_length}" OLLAMA_KEEP_ALIVE="${keep_alive}" \
    nohup ollama serve >"${SERVE_LOG}" 2>&1 &
  local server_pid=$!
  echo "${server_pid}" > "${PID_FILE}"
  echo "  PID: ${server_pid} (${PID_FILE} に記録)"
  echo "  ログ: ${SERVE_LOG}"
  echo ""

  # --- 6. 起動待ち ---
  echo "=== [6/7] サーバー起動待ち ==="
  if ! wait_for_server_ready; then
    echo "エラー: サーバー起動がタイムアウトしました(ログ: ${SERVE_LOG})" >&2
    exit 1
  fi
  echo "  OK(応答可能になりました)"
  echo ""

  # --- 7. ウォームアップと検証 ---
  echo "=== [7/7] ウォームアップと検証 ==="
  if ! timeout_run "${WARMUP_TIMEOUT_SEC}" ollama run "${model}" "warmup" >/dev/null 2>&1; then
    echo "エラー: ウォームアップ('ollama run ${model} \"warmup\"')に失敗またはタイムアウトしました。" >&2
    exit 1
  fi

  local ps_output ps_line
  ps_output="$(ollama ps 2>/dev/null || true)"
  ps_line="$(echo "${ps_output}" | grep -F -- "${model}" | head -n1 || true)"

  if [[ -z "${ps_line}" ]]; then
    echo "エラー: 'ollama ps' に ${model} が表示されません。ロード直後にアンロードされた可能性があります。" >&2
    exit 1
  fi

  local actual_name actual_context actual_processor
  actual_name="$(echo "${ps_line}" | awk '{print $1}')"
  actual_processor="$(parse_processor "${ps_line}")"
  actual_context="$(parse_context "${ps_line}")"

  echo "  NAME: ${actual_name}"
  echo "  CONTEXT: ${actual_context}"
  echo "  PROCESSOR: ${actual_processor}"
  echo ""

  local ok="true"
  if [[ "${actual_name}" != "${model}" ]]; then
    echo "警告: NAME が指定したモデル(${model})と一致しません(実際: ${actual_name})。" >&2
    ok="false"
  fi
  if [[ "${actual_context}" != "${context_length}" ]]; then
    echo "警告: CONTEXT が指定した値(${context_length})と一致しません(実際: ${actual_context})。" >&2
    ok="false"
  fi
  if [[ "${actual_processor}" != "100% GPU" ]]; then
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
    echo "!! 警告: PROCESSOR が '100% GPU' ではありません(実際: ${actual_processor})       " >&2
    echo "!! CPUに溢れているため測定結果が信頼できません。                              " >&2
    echo "!! コンテキスト長を下げて再実行してください。                                  " >&2
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" >&2
    echo ""
    ok="false"
  fi

  if [[ "${ok}" == "true" ]]; then
    echo "検証OK: モデル・コンテキスト長・PROCESSORすべて期待通りです。"
  fi
  echo ""

  echo "=== 次の手順 ==="
  echo "  cd fixture && claude --setting-sources project"
}

# コマンドをタイムアウト付きで実行する(macOS標準にはGNU timeoutが無いための自前実装)。
timeout_run() {
  local timeout_sec="$1"
  shift
  "$@" &
  local pid=$!
  local waited=0
  local rc=0
  while kill -0 "${pid}" 2>/dev/null; do
    if [ "${waited}" -ge "${timeout_sec}" ]; then
      kill -9 "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "${pid}" || rc=$?
  return "${rc}"
}

# `ollama ps` の1行から PROCESSOR 列を取り出す。
# 実機の列構成: NAME ID SIZE(数値) SIZE(単位) PROCESSOR(可変語数) CONTEXT UNTIL(可変語数)
# CONTEXT列が「素の整数」である性質を手がかりに、SIZE単位より後で最初に現れる
# 整数トークンをCONTEXT列とみなし、その手前($5以降)をすべてPROCESSOR列として連結する
# (PROCESSORが"100% GPU"や"12%/88% CPU/GPU"のように語数可変でも対応できる実装)。
parse_processor() {
  local line="$1"
  echo "${line}" | awk '{
    ctx_idx = 0
    for (i = 5; i <= NF; i++) {
      if ($i ~ /^[0-9]+$/) { ctx_idx = i; break }
    }
    if (ctx_idx == 0) { print "-"; next }
    proc = ""
    for (i = 5; i < ctx_idx; i++) {
      proc = proc (proc == "" ? "" : " ") $i
    }
    print proc
  }'
}

# `ollama ps` の1行から CONTEXT 列(素の整数)を取り出す。
parse_context() {
  local line="$1"
  echo "${line}" | awk '{
    for (i = 5; i <= NF; i++) {
      if ($i ~ /^[0-9]+$/) { print $i; exit }
    }
    print "-"
  }'
}

print_usage() {
  cat <<EOF
使い方:
  $0 <モデル名> [--context-length N] [--keep-alive DUR] [--force] [--dry-run]
  $0 --help

説明:
  ローカルLLM(Ollama)ベンチマーク検証用に、モデルの切り替えから
  Ollamaサーバーの起動・ウォームアップ・検証までを1コマンドで行います。

  最重要の設計方針: ~/.zshrc は一切書き換えません。コンテキスト長と
  OLLAMA_KEEP_ALIVE は 'ollama serve' 起動時のプロセス環境変数として渡します
  (OLLAMA_CONTEXT_LENGTH=N OLLAMA_KEEP_ALIVE=DUR ollama serve の形)。
  これにより設定ファイルの書き換え事故が無くなり、検証後の復元(bin/restore.sh)も
  サーバープロセスを止めるだけで済みます。

引数:
  <モデル名>              切り替え先のモデル名。設定テーブルにあるモデルは
                          コンテキスト長を自動解決します。テーブルに無いモデルは
                          --context-length が必須です。'ollama list' に存在するか
                          検証します(ollama serve停止中は警告のみで続行します)。

オプション:
  --context-length N      使用するコンテキスト長を明示指定します(テーブルの値を上書き)。
  --keep-alive DUR        OLLAMA_KEEP_ALIVE を指定します(既定: ${DEFAULT_KEEP_ALIVE})。
                          軸3・4のタスクは人間の確認待ちや多段階のツール呼び出しで
                          アイドルが発生しやすく、既定の5分だとモデルが自動アンロード
                          されて再ロード時間の分だけ不公平になるため、既定を30分にしています。
  --force                 動作中の既存 'ollama serve' を停止してから続行します。
                          付けない場合、ユーザーが手動起動したサーバーを誤って
                          止めてしまわないよう、エラーで停止して確認を促します。
  --dry-run               settings.json の変更内容のみ表示し、実際の書き込み・
                          サーバー起動は一切行いません。バックアップも作成しません。
  --help                  このヘルプを表示します。

設定テーブル(モデル -> コンテキスト長):
EOF
  local i
  for i in "${!MODEL_TABLE_NAMES[@]}"; do
    echo "  ${MODEL_TABLE_NAMES[$i]} -> ${MODEL_TABLE_CONTEXTS[$i]}"
  done
  cat <<EOF

例:
  $0 qwen3-coder:30b
  $0 gemma4:26b --force
  $0 qwen3.8:27b --context-length 131072 --keep-alive 30m --force
  $0 gemma4:26b --dry-run
EOF
}

main() {
  local model="" context_length_arg="" keep_alive="${DEFAULT_KEEP_ALIVE}" force="false" dry_run="false"

  if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        print_usage
        exit 0
        ;;
      --context-length)
        [[ $# -ge 2 ]] || { echo "エラー: --context-length には値が必要です。" >&2; exit 1; }
        context_length_arg="$2"
        shift 2
        ;;
      --keep-alive)
        [[ $# -ge 2 ]] || { echo "エラー: --keep-alive には値が必要です。" >&2; exit 1; }
        keep_alive="$2"
        shift 2
        ;;
      --force)
        force="true"
        shift
        ;;
      --dry-run)
        dry_run="true"
        shift
        ;;
      --*)
        echo "エラー: 不明なオプション '$1' です。" >&2
        print_usage
        exit 1
        ;;
      *)
        if [[ -n "${model}" ]]; then
          echo "エラー: モデル名は1つだけ指定してください(既に '${model}' が指定されています)。" >&2
          exit 1
        fi
        model="$1"
        shift
        ;;
    esac
  done

  if [[ -z "${model}" ]]; then
    echo "エラー: モデル名を指定してください。" >&2
    print_usage
    exit 1
  fi

  do_prepare "${model}" "${context_length_arg}" "${keep_alive}" "${force}" "${dry_run}"
}

main "$@"
