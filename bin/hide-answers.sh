#!/usr/bin/env bash
#
# hide-answers.sh
#
# 測定中に正解セット(answers/)を物理的に到達不可能にするスクリプト。
#
# なぜこれが必要か:
#   `fixture/`のセッションから`answers/answers.md`をReadツールで読むことを技術的に
#   遮断する手段は無い(`permissions.deny`の`Read(...)`パターンはプロジェクトディレクトリの
#   外を表現できないため。`Read(../**)`も`Read(**/answers/**)`も効かないことを実測で確認済み)。
#   人間が対話的に実行する場合は「確認プロンプト」が最後の砦になるが、無人実行
#   (`claude -p`)では確認プロンプト自体が出ないため、この砦が機能しない。
#   ファイル自体をリポジトリ外の到達不可能な場所へ物理的に移動することが、
#   唯一確実な対処である。
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

readonly ANSWERS_DIR="${BENCH_ROOT}/answers"
readonly RESULTS_DIR="${BENCH_ROOT}/results"
readonly RECORD_FILE="${RESULTS_DIR}/.answers-hidden"

# 退避先はリポジトリ外の固定パスにする(呼び出しのたびに変えない)。固定パスにする
# ことで、record.shの記録が万一失われても、このスクリプト自身がパスを再導出でき、
# --status/--restoreが記録ファイルに依存せず独立して動作できるようにしている。
readonly HIDDEN_DIR="${TMPDIR:-/tmp}"
readonly HIDDEN_PATH="${HIDDEN_DIR%/}/llm-bench-answers-hidden"

# ============================================================
# 状態判定
# ============================================================

# 現在の状態を判定する。
#   NOT_HIDDEN    : answers/ がリポジトリ内にあり、退避先には無い(通常状態)
#   HIDDEN        : answers/ がリポジトリ内に無く、退避先にある(退避中)
#   INCONSISTENT  : 両方に存在する(手動での混入等、想定外の状態)
#   LOST          : どちらにも存在しない(正解セットの所在不明。重大な異常)
detect_state() {
  local local_exists="false" hidden_exists="false"
  [[ -d "${ANSWERS_DIR}" ]] && local_exists="true"
  [[ -d "${HIDDEN_PATH}" ]] && hidden_exists="true"

  if [[ "${local_exists}" == "true" && "${hidden_exists}" == "false" ]]; then
    echo "NOT_HIDDEN"
  elif [[ "${local_exists}" == "false" && "${hidden_exists}" == "true" ]]; then
    echo "HIDDEN"
  elif [[ "${local_exists}" == "true" && "${hidden_exists}" == "true" ]]; then
    echo "INCONSISTENT"
  else
    echo "LOST"
  fi
}

print_state_detail() {
  local state="$1"
  case "${state}" in
    NOT_HIDDEN)
      echo "状態: 退避していません(通常状態)"
      echo "  ${ANSWERS_DIR} に存在します。"
      ;;
    HIDDEN)
      echo "状態: 退避中です"
      echo "  退避先: ${HIDDEN_PATH}"
      if [[ -f "${RECORD_FILE}" ]]; then
        echo "  記録ファイル: ${RECORD_FILE}"
      else
        echo "  警告: 記録ファイル(${RECORD_FILE})がありません(前回の実行が"
        echo "        異常終了した可能性がありますが、退避先は固定パスのため"
        echo "        復元には影響しません)。"
      fi
      ;;
    INCONSISTENT)
      echo "状態: 不整合です(要手動確認)" >&2
      echo "  ${ANSWERS_DIR} と ${HIDDEN_PATH} の両方に存在します。" >&2
      echo "  どちらが最新か手動で確認し、片方を削除してから再実行してください。" >&2
      ;;
    LOST)
      echo "状態: 重大な異常です(要手動確認)" >&2
      echo "  ${ANSWERS_DIR} にも ${HIDDEN_PATH} にも存在しません。" >&2
      echo "  正解セットの所在が不明です。バックアップ(gitの履歴等)から復元してください。" >&2
      ;;
  esac
}

# ============================================================
# サブコマンド
# ============================================================

do_hide() {
  local state
  state="$(detect_state)"

  case "${state}" in
    HIDDEN)
      echo "警告: 既に退避中です。何もしません(冪等)。" >&2
      print_state_detail "${state}"
      exit 0
      ;;
    INCONSISTENT|LOST)
      print_state_detail "${state}"
      exit 1
      ;;
    NOT_HIDDEN)
      ;;
  esac

  mkdir -p "${RESULTS_DIR}"
  mv "${ANSWERS_DIR}" "${HIDDEN_PATH}"

  {
    echo "# このファイルは bin/hide-answers.sh --hide が自動生成したものです。"
    echo "# 採点時に参照してはいけません(正解セットの退避先を示すだけの記録です)。"
    echo "hidden_path=${HIDDEN_PATH}"
    echo "hidden_at=$(date '+%Y-%m-%d %H:%M:%S')"
  } > "${RECORD_FILE}"

  echo "=== 正解セットを退避しました ==="
  echo "  ${ANSWERS_DIR} -> ${HIDDEN_PATH}"
  echo ""
  echo "測定終了後は必ず './bin/hide-answers.sh --restore' を実行してください。"
}

do_restore() {
  local state
  state="$(detect_state)"

  case "${state}" in
    NOT_HIDDEN)
      echo "警告: 退避されていません。何もしません(冪等)。" >&2
      print_state_detail "${state}"
      exit 0
      ;;
    INCONSISTENT|LOST)
      print_state_detail "${state}"
      exit 1
      ;;
    HIDDEN)
      ;;
  esac

  mv "${HIDDEN_PATH}" "${ANSWERS_DIR}"
  rm -f "${RECORD_FILE}"

  echo "=== 正解セットを復元しました ==="
  echo "  ${HIDDEN_PATH} -> ${ANSWERS_DIR}"
}

do_status() {
  local state
  state="$(detect_state)"
  print_state_detail "${state}"

  case "${state}" in
    HIDDEN)
      exit 0
      ;;
    NOT_HIDDEN)
      exit 1
      ;;
    *)
      exit 2
      ;;
  esac
}

print_usage() {
  cat <<EOF
使い方:
  $0 --hide | --restore | --status | --help

説明:
  測定中に正解セット(${ANSWERS_DIR})を、リポジトリ外の固定パス
  (${HIDDEN_PATH})へ物理的に退避/復元するスクリプトです。

  無人実行(claude -p)では確認プロンプトが出ないため、answers/ が存在すると
  モデルがReadツールで読めてしまいます。ファイル自体を到達不可能な場所へ
  移すのが唯一確実な対処です。

オプション:
  --hide      answers/ を退避先へ移動します。既に退避中の場合は警告のみで
              何もしません(冪等)。
  --restore   退避先から answers/ を元の位置へ戻します。退避されていない
              場合は警告のみで何もしません(冪等)。
  --status    現在の状態を表示します。終了コード: 0=退避中 / 1=未退避 /
              2=不整合または重大な異常。
  --help      このヘルプを表示します。

異常終了への耐性:
  --hide した状態でスクリプト自身や他の処理が異常終了しても、退避先は
  リポジトリ外の固定パスであるため、--status と --restore は記録ファイル
  (${RECORD_FILE})に依存せず、ファイルシステムの実際の状態から
  独立して正しく判定・復旧できます。

例:
  $0 --hide
  $0 --status
  $0 --restore
EOF
}

main() {
  if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
  fi

  case "$1" in
    --hide)
      do_hide
      ;;
    --restore)
      do_restore
      ;;
    --status)
      do_status
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      echo "エラー: 不明なオプション '$1' です。" >&2
      print_usage
      exit 1
      ;;
  esac
}

main "$@"
