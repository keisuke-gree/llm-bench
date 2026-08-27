#!/usr/bin/env bash
#
# score.sh
#
# 軸3・4のスコアを記録するスクリプト。record.sh と対になる仕組み。
#
# 【最重要の設計方針: results/mapping.tsv を参照しない】
#   mapping.tsv はブラインドIDとモデル名の対応表であり、採点フェーズで参照すると
#   「どのモデルの回答か」を知った状態で採点してしまい、ブラインド採点の意味が
#   失われる。そのため本スクリプトはブラインドIDをそのまま records/scores.tsv に
#   記録するだけで、モデル名の解決は一切行わない(レポート生成時に行う)。
#
# 実行環境: bash 3.2.57 (macOS標準) 互換。人間またはSkill経由で実行する想定。
# 実行場所: このリポジトリのルートディレクトリ(相対パスはスクリプト自身の位置から解決する)。
#
set -euo pipefail

# ============================================================
# 設定値
# ============================================================

# 共有の定数・関数(パス)を読み込む。
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

readonly SCORE_MIN=0
readonly SCORE_MAX=5

# ============================================================
# ユーティリティ関数
# ============================================================

# スコアが0〜5の整数かどうかを検証する。不正なら理由を表示して終了する。
validate_score() {
  local label="$1" value="$2"
  case "${value}" in
    ''|*[!0-9]*)
      echo "エラー: --${label} には0〜5の整数を指定してください(指定値: '${value}')。" >&2
      exit 1
      ;;
  esac
  if [ "${value}" -lt "${SCORE_MIN}" ] || [ "${value}" -gt "${SCORE_MAX}" ]; then
    echo "エラー: --${label} は${SCORE_MIN}〜${SCORE_MAX}の範囲で指定してください(指定値: ${value})。" >&2
    exit 1
  fi
}

# 指定されたブラインドIDの回答ファイルが存在するか確認する。
# 無くても記録は続行する(IDの打ち間違いを検知するための警告のみ)。
warn_if_answer_missing() {
  local blind_id="$1"
  local answer_file="${RESULT_ANSWERS_DIR}/${blind_id}.md"
  if [[ ! -f "${answer_file}" ]]; then
    echo "警告: 回答ファイル ${answer_file} が見つかりません。" >&2
    echo "      ブラインドIDの打ち間違いの可能性があります。IDを確認してください。" >&2
  fi
}

# 同じブラインドIDが既に scores.tsv に記録済みでないか確認する。
# 記録済みならエラーで停止し、上書きしたい場合の対処を案内する。
error_if_already_scored() {
  local blind_id="$1"
  if [[ -f "${SCORES_TSV}" ]] && awk -F'\t' -v id="${blind_id}" 'NF > 0 && $1 == id { found = 1 } END { exit !found }' "${SCORES_TSV}"; then
    echo "エラー: ブラインドID '${blind_id}' は既に ${SCORES_TSV} に記録済みです。" >&2
    echo "        上書きしたい場合は、該当行をエディタで手動で削除してから再実行してください。" >&2
    exit 1
  fi
}

# scores.tsv に1行追記する。ファイルが無ければヘッダー行付きで作成する。
append_score_row() {
  local blind_id="$1" axis3="$2" axis4="$3" note="$4"
  local now
  now="$(date '+%Y-%m-%d %H:%M:%S')"

  if [[ ! -f "${SCORES_TSV}" ]]; then
    printf 'blind_id\taxis3\taxis4\tnote\trecorded_at\n' > "${SCORES_TSV}"
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "${blind_id}" "${axis3}" "${axis4}" "${note}" "${now}" >> "${SCORES_TSV}"
}

print_usage() {
  cat <<EOF
使い方:
  $0 <ブラインドID> --axis3 <0-5> --axis4 <0-5> [--note "..."] [--help]

説明:
  軸3(調査の過程)・軸4(結論の正しさ)のスコアを ${SCORES_TSV} に追記します。
  record.sh と対になる仕組みで、こちらもブラインドID(モデル名を伏せた状態)の
  ままスコアを記録します。results/mapping.tsv は絶対に参照しません
  (採点時にモデル名を知るとバイアスが入るため)。モデル名の解決はレポート
  生成時に行ってください。

引数:
  <ブラインドID>          record.sh が払い出したブラインドID(例: answer-01)。

オプション:
  --axis3 <0-5>           軸3(調査の過程)のスコア。0〜5の整数。
  --axis4 <0-5>           軸4(結論の正しさ)のスコア。0〜5の整数。
  --note "..."            採点理由・減点理由などの備考(任意)。
  --help                  このヘルプを表示します。

引数の異常系:
  - スコアが0〜5の整数以外の場合はエラーで停止します。
  - 指定したブラインドIDに対応する回答ファイル(results/answers/<ID>.md)が
    存在しない場合は警告を表示します(IDの打ち間違いを検知するため)。
  - 同じブラインドIDが既に記録済みの場合はエラーで停止します。上書きしたい
    場合は ${SCORES_TSV} の該当行を手動で削除してから再実行してください。

例:
  $0 answer-01 --axis3 5 --axis4 4
  $0 answer-02 --axis3 3 --axis4 2 --note "検索結果をheadで打ち切り、見落としあり"
EOF
}

main() {
  if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
  fi

  local blind_id="" axis3="" axis4="" note=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        print_usage
        exit 0
        ;;
      --axis3)
        [[ $# -ge 2 ]] || { echo "エラー: --axis3 には値が必要です。" >&2; exit 1; }
        axis3="$2"
        shift 2
        ;;
      --axis4)
        [[ $# -ge 2 ]] || { echo "エラー: --axis4 には値が必要です。" >&2; exit 1; }
        axis4="$2"
        shift 2
        ;;
      --note)
        [[ $# -ge 2 ]] || { echo "エラー: --note には値が必要です。" >&2; exit 1; }
        note="$2"
        shift 2
        ;;
      --*)
        echo "エラー: 不明なオプション '$1' です。" >&2
        print_usage
        exit 1
        ;;
      *)
        if [[ -n "${blind_id}" ]]; then
          echo "エラー: ブラインドIDは1つだけ指定してください。" >&2
          exit 1
        fi
        blind_id="$1"
        shift
        ;;
    esac
  done

  if [[ -z "${blind_id}" ]]; then
    echo "エラー: ブラインドIDを指定してください。" >&2
    print_usage
    exit 1
  fi
  if [[ -z "${axis3}" ]]; then
    echo "エラー: --axis3 を指定してください。" >&2
    exit 1
  fi
  if [[ -z "${axis4}" ]]; then
    echo "エラー: --axis4 を指定してください。" >&2
    exit 1
  fi

  validate_score "axis3" "${axis3}"
  validate_score "axis4" "${axis4}"

  mkdir -p "${RESULTS_DIR}"

  # --- 1. 回答ファイルの存在確認(警告のみ、記録は続行) ---
  warn_if_answer_missing "${blind_id}"

  # --- 2. 重複記録の確認(エラーで停止) ---
  error_if_already_scored "${blind_id}"

  # --- 3. scores.tsv に追記する ---
  append_score_row "${blind_id}" "${axis3}" "${axis4}" "${note}"

  # --- 4. 記録内容を表示する ---
  echo "=== スコアを記録しました ==="
  echo "  ブラインドID: ${blind_id}"
  echo "  軸3: ${axis3}"
  echo "  軸4: ${axis4}"
  if [[ -n "${note}" ]]; then
    echo "  備考: ${note}"
  fi
  echo "  記録先: ${SCORES_TSV}"
}

main "$@"
