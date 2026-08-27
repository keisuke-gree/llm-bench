#!/usr/bin/env bash
#
# run-tasks.sh
#
# fixture/ で指定モデルにタスクを解かせ、回答をブラインドIDのファイルとして
# 保存するスクリプト。軸3・4の「実行フェーズ」を人間の介在なしに完了させる。
#
# 前提:
#   - fixture/.claude/settings.json の .model が測定対象モデルに切り替わっていること
#     (bin/prepare.sh で切り替える)。
#   - answers/ が bin/hide-answers.sh --hide で退避済みであること(安全装置として
#     本スクリプトが起動時に必ず確認する。退避されていなければエラーで停止する)。
#
# 注意: `claude -p` は毎回新しいセッションとして起動されるため、`/clear`相当の
#      操作(会話のリセット)は不要である(セッションをまたいだ状態が残らないため)。
#
# 実行環境: bash 3.2.57 (macOS標準) 互換。
# 実行場所: このリポジトリのルートディレクトリ(相対パスはスクリプト自身の位置から解決する)。
#
set -euo pipefail

# ============================================================
# 設定値
# ============================================================

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly BENCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly FIXTURE_DIR="${BENCH_ROOT}/fixture"
readonly SETTINGS_JSON="${FIXTURE_DIR}/.claude/settings.json"
readonly TASKS_MD="${BENCH_ROOT}/tasks/tasks.md"
readonly HIDE_ANSWERS_SH="${SCRIPT_DIR}/hide-answers.sh"
readonly RECORD_SH="${SCRIPT_DIR}/record.sh"

readonly DEFAULT_TIMEOUT_SEC=900

# ============================================================
# ユーティリティ関数
# ============================================================

# answers/ が退避済みであることを確認する(安全装置)。
# 退避されていなければ、測定を汚染する前にエラーで停止する。
require_answers_hidden() {
  if "${HIDE_ANSWERS_SH}" --status >/dev/null 2>&1; then
    return 0
  fi
  echo "エラー: 正解セット(answers/)が退避されていません。" >&2
  echo "        無人実行では answers/ が存在するとモデルに読まれる恐れがあります。" >&2
  echo "        先に以下を実行してください:" >&2
  echo "          ./bin/hide-answers.sh --hide" >&2
  exit 1
}

# fixture/.claude/settings.json から現在のモデル名を読み取る(表示用)。
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

# tasks/tasks.md に存在する「## タスクN」見出しの番号一覧を出現順に返す。
detect_all_task_numbers() {
  grep -oE '^## タスク[0-9]+' "${TASKS_MD}" | grep -oE '[0-9]+'
}

# tasks/tasks.md から指定タスク番号の本文を抽出する。
#
# tasks.md の構造(実物を確認して判断した仕様):
#   "## タスクN" という見出しの後、そのタスクに関する説明文が続くことがあるが、
#   実際にClaude Codeへ貼り付ける本文は、見出し後で最初に現れる```〜```の
#   フェンスコードブロックの中身である(見出し直後に説明文がある場合、その
#   説明文はタスクの前提を人間に伝えるための注記であり、本文はフェンスの
#   中に完結した形で再掲されている。実際にtasks/tasks.mdのタスク1〜3すべてを
#   確認し、この構造で一貫していることを確認済み)。
#
# 次の「## タスクN」見出しが来た時点で対象区間を抜ける(見出し行のパターン
# マッチのたびに対象区間かどうかを判定し直すため、区間の終端を別途計算する
# 必要がない)。
extract_task_body() {
  local task_no="$1"
  awk -v tn="${task_no}" '
    BEGIN { target = "## タスク" tn; in_target = 0; fence = 0 }
    /^## タスク[0-9]+/ {
      in_target = ($0 == target) ? 1 : 0
      fence = 0
      next
    }
    in_target && /^```/ {
      fence++
      next
    }
    in_target && fence == 1 { print }
  ' "${TASKS_MD}"
}

# コマンドをタイムアウト付きで実行する(macOS標準にはGNU timeoutが無いための自前実装。
# bin/prepare.sh・bin/sweep.shの同名処理と同じ考え方)。
# 呼び出し側でリダイレクト(> file 2>&1 等)を付けて呼ぶことを想定している。
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

# record.sh の出力から「ブラインドID:」「回答ファイル:」の値を取り出す。
parse_record_field() {
  local output="$1" label="$2"
  echo "${output}" | sed -n "s/^ *${label}: *//p" | head -n1
}

# ============================================================
# タスク実行本体
# ============================================================

# 1タスクを実行する。summary用の行(タブ区切り: task_no, blind_id, status, elapsed)を
# 標準出力へ返す。
run_one_task() {
  local task_no="$1" timeout_sec="$2"

  echo "=== タスク${task_no} ===" >&2

  local task_body
  task_body="$(extract_task_body "${task_no}")"
  if [[ -z "${task_body}" ]]; then
    echo "エラー: タスク${task_no}の本文を tasks/tasks.md から抽出できませんでした。" >&2
    printf '%s\t%s\t%s\t%s\n' "${task_no}" "-" "失敗(本文抽出エラー)" "-"
    return 0
  fi

  # --- 1. record.sh でブラインドIDと保存先ファイルパスを取得する ---
  local record_output blind_id answer_file
  if ! record_output="$("${RECORD_SH}" "${task_no}")"; then
    echo "エラー: record.sh の実行に失敗しました(タスク${task_no})。" >&2
    printf '%s\t%s\t%s\t%s\n' "${task_no}" "-" "失敗(ブラインドID払い出しエラー)" "-"
    return 0
  fi
  blind_id="$(parse_record_field "${record_output}" "ブラインドID")"
  answer_file="$(parse_record_field "${record_output}" "回答ファイル")"

  if [[ -z "${blind_id}" || -z "${answer_file}" ]]; then
    echo "エラー: record.sh の出力からブラインドID/回答ファイルを読み取れませんでした。" >&2
    printf '%s\t%s\t%s\t%s\n' "${task_no}" "-" "失敗(record.sh出力の解析エラー)" "-"
    return 0
  fi
  echo "  ブラインドID: ${blind_id}" >&2

  # --- 2. claude -p でタスクを実行する(所要時間を計測) ---
  local out_tmp err_tmp start_ts end_ts elapsed rc
  out_tmp="$(mktemp "${TMPDIR:-/tmp}/run_tasks_out.XXXXXX")"
  err_tmp="$(mktemp "${TMPDIR:-/tmp}/run_tasks_err.XXXXXX")"

  start_ts="$(date +%s)"
  rc=0
  run_with_timeout "${timeout_sec}" \
    bash -c 'cd "$1" || exit 1; exec claude -p "$2" --setting-sources project' \
    _ "${FIXTURE_DIR}" "${task_body}" \
    >"${out_tmp}" 2>"${err_tmp}" || rc=$?
  end_ts="$(date +%s)"
  elapsed=$((end_ts - start_ts))

  local status
  if [ "${rc}" -eq 124 ]; then
    status="失敗(タイムアウト ${timeout_sec}秒超過)"
    echo "  結果: ${status}(${elapsed}秒経過)" >&2
    {
      echo "# タスク${task_no}"
      echo ""
      echo "所要時間: ${elapsed}秒"
      echo ""
      echo "(回答なし: タイムアウト ${timeout_sec}秒を超過したため強制終了しました)"
    } > "${answer_file}"
  elif [ "${rc}" -ne 0 ]; then
    status="失敗(claude -p が終了コード${rc}で失敗)"
    echo "  結果: ${status}(${elapsed}秒経過)" >&2
    echo "  --- エラー出力(末尾) ---" >&2
    tail -n 20 "${err_tmp}" >&2 || true
    {
      echo "# タスク${task_no}"
      echo ""
      echo "所要時間: ${elapsed}秒"
      echo ""
      echo "(回答なし: claude -p が終了コード${rc}で失敗しました。詳細は運用者が別途確認してください)"
    } > "${answer_file}"
  else
    status="成功"
    echo "  結果: ${status}(${elapsed}秒)" >&2
    {
      echo "# タスク${task_no}"
      echo ""
      echo "所要時間: ${elapsed}秒"
      echo ""
      cat "${out_tmp}"
    } > "${answer_file}"
  fi

  rm -f "${out_tmp}" "${err_tmp}"

  printf '%s\t%s\t%s\t%s\n' "${task_no}" "${blind_id}" "${status}" "${elapsed}"
}

# ============================================================
# 使い方
# ============================================================

print_usage() {
  cat <<EOF
使い方:
  $0 [--tasks 1,2,3] [--timeout SEC] [--help]

説明:
  fixture/ で現在設定されているモデルにタスクを解かせ、回答をブラインドIDの
  ファイルとして results/answers/ 配下に保存します。record.sh でのブラインドID
  払い出しから claude -p での実行、回答の保存までを自動化します。

  安全装置: answers/ が bin/hide-answers.sh --hide で退避されていない場合、
  測定を汚染する前にエラーで停止します。

オプション:
  --tasks "1,2,3"   実施するタスク番号をカンマ区切りで指定します。
                     省略時は tasks/tasks.md に存在する全タスクを実施します。
  --timeout SEC      1タスクあたりのタイムアウト秒数(既定: ${DEFAULT_TIMEOUT_SEC}秒)。
                     超過した場合はそのタスクを失敗として記録し、次のタスクへ
                     進みます。
  --help             このヘルプを表示します。

注意:
  claude -p は毎回新しいセッションとして起動されるため、/clear相当の操作は
  不要です(前タスクの情報が引き継がれることはありません)。

例:
  $0
  $0 --tasks 1,3 --timeout 600
EOF
}

# ============================================================
# メイン処理
# ============================================================

main() {
  local tasks_csv="" timeout_sec="${DEFAULT_TIMEOUT_SEC}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        print_usage
        exit 0
        ;;
      --tasks)
        [[ $# -ge 2 ]] || { echo "エラー: --tasks には値が必要です。" >&2; exit 1; }
        tasks_csv="$2"
        shift 2
        ;;
      --timeout)
        [[ $# -ge 2 ]] || { echo "エラー: --timeout には値が必要です。" >&2; exit 1; }
        timeout_sec="$2"
        shift 2
        ;;
      --*)
        echo "エラー: 不明なオプション '$1' です。" >&2
        print_usage
        exit 1
        ;;
      *)
        echo "エラー: 不明な引数 '$1' です。" >&2
        print_usage
        exit 1
        ;;
    esac
  done

  case "${timeout_sec}" in
    ''|*[!0-9]*)
      echo "エラー: --timeout は正整数で指定してください(指定値: '${timeout_sec}')。" >&2
      exit 1
      ;;
  esac

  if ! command -v claude >/dev/null 2>&1; then
    echo "エラー: claude コマンドが見つかりません。" >&2
    exit 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "エラー: jq コマンドが見つかりません。" >&2
    exit 1
  fi

  # --- 1. answers/ の退避状態を確認する(安全装置) ---
  require_answers_hidden

  # --- 2. 現在のモデル名を表示する ---
  local model
  model="$(read_current_model)"
  echo "対象モデル: ${model}"

  # --- 3. 実施するタスク番号一覧を決定する ---
  local tasks=()
  if [[ -n "${tasks_csv}" ]]; then
    IFS=',' read -ra tasks <<<"${tasks_csv}"
    local i
    for i in "${!tasks[@]}"; do
      tasks[$i]="$(echo "${tasks[$i]}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      case "${tasks[$i]}" in
        ''|*[!0-9]*)
          echo "エラー: --tasks のタスク番号は正整数で指定してください(指定値: '${tasks[$i]}')。" >&2
          exit 1
          ;;
      esac
    done
  else
    while IFS= read -r n; do
      tasks+=("${n}")
    done < <(detect_all_task_numbers)
  fi

  if [ "${#tasks[@]}" -eq 0 ]; then
    echo "エラー: 実施するタスクが1つもありません(tasks/tasks.md を確認してください)。" >&2
    exit 1
  fi

  echo "実施タスク: ${tasks[*]}"
  echo "タイムアウト: ${timeout_sec}秒/タスク"
  echo ""

  # --- 4. タスクごとに実行する ---
  local summary=()
  local task_no
  for task_no in "${tasks[@]}"; do
    local line
    line="$(run_one_task "${task_no}" "${timeout_sec}")"
    summary+=("${line}")
    echo "" >&2
  done

  # --- 5. 結果一覧を表示する ---
  echo "=== 結果一覧 ==="
  printf '%-8s %-14s %-34s %s\n' "タスク" "ブラインドID" "結果" "所要時間(秒)"
  local row task_col blind_col status_col elapsed_col
  for row in "${summary[@]}"; do
    IFS=$'\t' read -r task_col blind_col status_col elapsed_col <<<"${row}"
    printf '%-8s %-14s %-34s %s\n' "${task_col}" "${blind_col}" "${status_col}" "${elapsed_col}"
  done
}

main "$@"
