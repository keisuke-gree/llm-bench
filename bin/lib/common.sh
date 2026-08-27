#!/usr/bin/env bash
#
# lib/common.sh
#
# bin/配下のスクリプトが共有する定数と関数。
#
# 使い方: 各スクリプトの冒頭で source する。
#   source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"
#
# 【このファイルに置くもの】
#   - リポジトリ内のパス(1箇所で定義し、どのスクリプトからも同じ名前で参照する)
#   - 2つ以上のスクリプトが使う定数・関数
# 【置かないもの】
#   - 1つのスクリプトしか使わないもの(そのスクリプト側に置く)
#
# 実行環境:
#   - macOS(Darwin) / bin/bash 3.2.57 互換で書く(連想配列 declare -A は使わない)
#   - jq は /usr/bin/jq を想定
#

# 二重sourceされた場合、readonlyの再代入でエラー終了してしまうため防ぐ。
if [[ -n "${LLM_BENCH_COMMON_LOADED:-}" ]]; then
  return 0
fi
readonly LLM_BENCH_COMMON_LOADED=1

# ============================================================
# リポジトリ内のパス
# ============================================================

# このファイル自身の位置からリポジトリのルートを解決する。
# $0 ではなく BASH_SOURCE を使うのは、sourceする側のスクリプトの位置ではなく
# このライブラリの位置を基準にしたいため(bin/lib/ の1つ上の1つ上がルート)。
readonly BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BENCH_ROOT="$(cd "${BIN_DIR}/.." && pwd)"

# 測定される側のコードベースとその設定。
readonly FIXTURE_DIR="${BENCH_ROOT}/fixture"
readonly SETTINGS_JSON="${FIXTURE_DIR}/.claude/settings.json"

# 入力(タスク文面と正解セット)。
# ANSWER_KEY_DIR(正解セット)と後述の RESULT_ANSWERS_DIR(モデルの回答)は別物である。
# 両者を取り違えると測定が汚染されるため、名前で区別できるようにしている。
readonly TASKS_MD="${BENCH_ROOT}/tasks/tasks.md"
readonly ANSWER_KEY_DIR="${BENCH_ROOT}/answers"

# 出力。results/ は .gitignore 対象(環境固有のため共有しない)。
readonly RESULTS_DIR="${BENCH_ROOT}/results"
readonly RESULT_ANSWERS_DIR="${RESULTS_DIR}/answers"
readonly TRACES_DIR="${RESULTS_DIR}/traces"
readonly MAPPING_TSV="${RESULTS_DIR}/mapping.tsv"
readonly SCORES_TSV="${RESULTS_DIR}/scores.tsv"
readonly SERVE_LOG="${RESULTS_DIR}/ollama-serve.log"
readonly PID_FILE="${RESULTS_DIR}/.ollama.pid"

# レポート。
readonly REPORTS_DIR="${BENCH_ROOT}/reports"
readonly TEMPLATE_HTML="${REPORTS_DIR}/_template.html"

# ============================================================
# Ollamaサーバー
# ============================================================

readonly SERVER_HOST="127.0.0.1"
readonly SERVER_PORT="11434"
readonly SERVER_READY_TIMEOUT_SEC=90   # 起動待ちの最大秒数
readonly SERVER_STOP_TIMEOUT_SEC=30    # 停止待ちの最大秒数

# ============================================================
# モデルごとの設定値
# ============================================================

# モデル名 -> コンテキスト長(実機で確認済みの実測値)のテーブル。
# bash 3.2 (macOS標準)は連想配列(declare -A)を使えないため、
# 「モデル名の配列」と「コンテキスト長の配列」を対で持つ索引配列テーブルにしている。
#
# モデルを追加・変更する場合はここだけを直す。bin/sweep.sh の既定の測定対象も
# このテーブルから導出されるため、2箇所を揃える必要はない。
readonly MODEL_TABLE_NAMES=("gemma4:26b" "qwen3-coder:30b" "qwen3.8:27b")
readonly MODEL_TABLE_CONTEXTS=("262144" "131072" "131072")

# CLAUDE_CODE_AUTO_COMPACT_WINDOW をコンテキスト長から算出するための比率。
# コンテキスト長の87.7%でauto-compactを発火させ、上限に達する前に退避させる意図。
# 検算: 131072 * 0.877 ≈ 114950 -> 1000単位丸めで115000
#       262144 * 0.877 ≈ 229900 -> 1000単位丸めで230000
readonly AUTO_COMPACT_RATIO="0.877"

# テーブルからモデルのコンテキスト長を引く。見つからなければ 1 を返す。
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

# テーブルの全モデル名をカンマ区切りで返す(sweep.shの既定の測定対象に使う)。
model_names_csv() {
  local IFS=","
  echo "${MODEL_TABLE_NAMES[*]}"
}

# コンテキスト長から CLAUDE_CODE_AUTO_COMPACT_WINDOW を算出する(1000単位に丸める)。
calc_auto_compact_window() {
  local context_length="$1"
  awk -v cl="${context_length}" -v ratio="${AUTO_COMPACT_RATIO}" 'BEGIN {
    raw = cl * ratio
    rounded = int((raw + 500) / 1000) * 1000
    printf "%d", rounded
  }'
}

# ============================================================
# サーバーの状態確認
# ============================================================

# 指定ホスト:ポートでOllamaサーバーが応答可能かを確認する。
is_server_running() {
  curl -fsS "http://${SERVER_HOST}:${SERVER_PORT}/" >/dev/null 2>&1
}

# サーバーが応答するまで待つ。タイムアウトしたら 1 を返す。
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

# サーバーが応答しなくなるまで待つ。タイムアウトしたら 1 を返す。
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

# ============================================================
# 汎用ユーティリティ
# ============================================================

# コマンドをタイムアウト付きで実行する。
# macOS標準にはGNU timeoutが無いため自前で実装している。
# タイムアウトした場合はGNU timeoutと同じ終了コード124を返す。
run_with_timeout() {
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

# fixture/.claude/settings.json から現在のモデル名を読む。
# 読めない場合は、原因と次にやるべきことを示してエラー終了する。
read_current_model() {
  if [[ ! -f "${SETTINGS_JSON}" ]]; then
    echo "エラー: ${SETTINGS_JSON} が見つかりません。" >&2
    echo "        先に './bin/prepare.sh <モデル名>' を実行してください。" >&2
    exit 1
  fi
  local model
  model="$(jq -r '.model // empty' "${SETTINGS_JSON}")"
  if [[ -z "${model}" ]]; then
    echo "エラー: ${SETTINGS_JSON} から .model を読み取れませんでした。" >&2
    exit 1
  fi
  echo "${model}"
}

# ファイルをタイムスタンプ付きでバックアップし、バックアップ先のパスを返す。
# cp -p でパーミッションとタイムスタンプを保持する。
backup_file() {
  local file="$1"
  local ts backup
  ts="$(date +%Y%m%d-%H%M%S)"
  backup="${file}.bak.${ts}"
  cp -p "${file}" "${backup}"
  echo "${backup}"
}

# 絶対パスを、$HOME配下であれば "~/..." 形式に変換する(それ以外はそのまま返す)。
# settings.json の denyRead は "~/" 形式で記録する(絶対パスも有効だが、
# ホームディレクトリ配下であることが一目で分かる形式に揃えている)。
to_home_relative() {
  local path="$1"
  case "${path}" in
    "${HOME}")   echo "~" ;;
    "${HOME}"/*) echo "~/${path#"${HOME}"/}" ;;
    *)           echo "${path}" ;;
  esac
}
