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
# モデルの取得済み確認(自動pullの防止)
# ============================================================

# Ollamaのモデル格納ディレクトリ。OLLAMA_MODELS が設定されていればそれに従う。
readonly OLLAMA_MODELS_DIR="${OLLAMA_MODELS:-${HOME}/.ollama/models}"

# モデルがローカルに取得済みかを、ディスク上のマニフェストの有無で判定する。
#
# `ollama list` はサーバーが起動していないと失敗するため、サーバー起動前でも
# 判定できる手段が必要になる。マニフェストのパスは
#   <models>/manifests/<レジストリ>/<名前空間>/<モデル名>/<タグ>
# という構成で、公式ライブラリのモデルは名前空間が library になる。
model_is_pulled_on_disk() {
  local model="$1" name tag manifest
  name="${model%%:*}"
  tag="${model##*:}"
  # タグを省略した場合のOllamaの既定は latest
  [[ "${tag}" == "${model}" ]] && tag="latest"

  if [[ "${name}" == */* ]]; then
    # user/model のように名前空間が明示されている場合
    manifest="${OLLAMA_MODELS_DIR}/manifests/registry.ollama.ai/${name}/${tag}"
  else
    manifest="${OLLAMA_MODELS_DIR}/manifests/registry.ollama.ai/library/${name}/${tag}"
  fi
  [[ -f "${manifest}" ]]
}

# 指定した全モデルが取得済みであることを確認する。1つでも未取得ならエラー終了する。
#
# 【なぜこの確認が必須か】
#   `ollama run <model>` は未取得のモデルを自動でネットワークから取得する。
#   無人実行の途中で人間の確認を経ずにモデルがダウンロードされることになるため、
#   すべての `ollama run` より前にここで弾く。
#
# 【二段で確認する理由】
#   一次: ディスク上のマニフェスト。サーバー起動前でも効き、コストがゼロ。
#   二次: `ollama list`。サーバーが応答する場合のみ実施し、公式インタフェースで
#         裏を取る。一次がOllamaの内部構成変更で誤判定しても、こちらが捕まえる。
#   一次が「取得済みなのに未取得」と誤る方向に転んだ場合は余計に停止するだけで、
#   勝手にpullが走る経路は残らない。
#
# bash 3.2 では set -u 下で空配列の展開が失敗するため、未取得リストは
# 空白区切りの文字列で持つ(モデル名に空白は含まれない)。
require_models_pulled() {
  local missing="" model list_output
  for model in "$@"; do
    if ! model_is_pulled_on_disk "${model}"; then
      missing="${missing} ${model}"
    fi
  done

  if [[ -z "${missing}" ]] && is_server_running; then
    if list_output="$(ollama list 2>/dev/null)"; then
      for model in "$@"; do
        if ! echo "${list_output}" | awk 'NR>1 {print $1}' | grep -Fxq -- "${model}"; then
          missing="${missing} ${model}"
        fi
      done
    fi
  fi

  [[ -z "${missing}" ]] && return 0

  echo "エラー: 以下のモデルが取得されていません。測定を開始しません。" >&2
  for model in ${missing}; do
    echo "        - ${model}" >&2
  done
  echo "" >&2
  echo "        'ollama run' は未取得のモデルを自動でダウンロードします。" >&2
  echo "        人間の確認を経ないネットワークアクセスを避けるため、ここで停止します。" >&2
  echo "        取得する場合は、人間が別ターミナルで以下を実行してください:" >&2
  for model in ${missing}; do
    echo "          ollama pull ${model}" >&2
  done
  exit 1
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

# サーバー起動がタイムアウトした際に、原因の切り分け材料を標準エラーへ出す。
#
# is_server_running() は curl でlocalhostに接続して判定するため、localhost宛の通信が
# 遮断された環境(auto modeでないClaude Codeのセッション等)では、サーバーが動いていても
# 「停止中」と誤判定する。この状態では既存サーバーの事前チェックが素通りし、
# 使用中のポートに起動しようとして「起動タイムアウト」という原因の分かりにくい
# エラーになる。lsof はポートの使用状況を直接見るため、この誤判定の影響を受けない。
diagnose_server_start_failure() {
  local listeners
  listeners="$(lsof -nP -iTCP:"${SERVER_PORT}" -sTCP:LISTEN -t 2>/dev/null || true)"

  if [[ -n "${listeners}" ]]; then
    echo "        ポート ${SERVER_PORT} は既に使用されています(PID: ${listeners})。" >&2
    echo "        別の 'ollama serve' が動作中の可能性が高いです。停止してから再実行するか、" >&2
    echo "        --force を付けて自動停止させてください。" >&2
    echo "        (このスクリプトはサーバーの起動確認に localhost への接続を使うため、" >&2
    echo "         localhost が遮断された環境では動作中のサーバーを検出できません。" >&2
    echo "         Claude Code から実行している場合は auto mode で起動しているか確認してください)" >&2
  else
    echo "        ポート ${SERVER_PORT} を待ち受けているプロセスはありません。" >&2
    echo "        ログを確認してください(モデルのロードに時間がかかっている、" >&2
    echo "        VRAM不足で失敗している等の可能性があります)。" >&2
  fi
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
