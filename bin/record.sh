#!/usr/bin/env bash
#
# record.sh
#
# ブラインド採点用の回答ファイルを払い出すスクリプト。
# 軸3・4のタスク回答を、どのモデルのものか分からないファイル名で保存するための仕組み。
#
# なぜランダムなIDを使うか:
#   連番(answer-01, answer-02, ...)で払い出すと、「01〜03が1モデル目」のように
#   実施順序から中身が推測できてしまい、ブラインドの意味が失われる。
#   そのため answer-01 〜 answer-99 の中から未使用のものをランダムに1つ選ぶ。
#
# 実行環境: bash 3.2.57 (macOS標準) 互換。
# 実行者: 通常は bin/run-tasks.sh が内部で呼び出す(タスクごとにブラインドIDを払い出す)。
#        人間が単体で実行することもできる。
# 実行場所: このリポジトリのルートディレクトリ(相対パスはスクリプト自身の位置から解決する)。
#
set -euo pipefail

# ============================================================
# 設定値
# ============================================================

# 共有の定数・関数(パス、read_current_model 等)を読み込む。
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

readonly BLIND_ID_MIN=1
readonly BLIND_ID_MAX=99

# ============================================================
# ユーティリティ関数
# ============================================================

# モデル名は read_current_model()(lib/common.sh)で settings.json から読み取る。
# ユーザーがモデル名を打ち直す必要をなくし、転記ミスを防ぐため。

# fixture/.claude/settings.json から現在のコンテキスト長を読み取る(記録用)。
read_current_context() {
  jq -r '.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS // "unknown"' "${SETTINGS_JSON}"
}

# answer-01〜answer-99のうち、results/answers/ にまだ存在しないIDから
# ランダムに1つ選ぶ($RANDOMを使用。連番で払い出さないため)。
pick_blind_id() {
  local candidates=()
  local n padded
  n="${BLIND_ID_MIN}"
  while [ "${n}" -le "${BLIND_ID_MAX}" ]; do
    padded="$(printf 'answer-%02d' "${n}")"
    if [[ ! -f "${RESULT_ANSWERS_DIR}/${padded}.md" ]]; then
      candidates+=("${padded}")
    fi
    n=$((n + 1))
  done

  local count=${#candidates[@]}
  if [ "${count}" -eq 0 ]; then
    echo "エラー: answer-01〜answer-99 がすべて使用済みです。不要なファイルを整理してください。" >&2
    exit 1
  fi

  # $RANDOM % 候補数 で候補配列からランダムに1つ選ぶ(連番回避のための乱数選択)。
  local idx="$((RANDOM % count))"
  echo "${candidates[$idx]}"
}

# mapping.tsv に1行追記する。ファイルが無ければヘッダー行付きで作成する。
append_mapping_row() {
  local blind_id="$1" model="$2" context="$3" task_no="$4"
  local now
  now="$(date '+%Y-%m-%d %H:%M:%S')"

  if [[ ! -f "${MAPPING_TSV}" ]]; then
    {
      echo "# 注意: このファイルは採点時に参照してはいけない対応表です(ブラインド採点のため)。"
      echo "# 採点フェーズでは results/answers/ 配下の回答ファイルのみを参照してください。"
      printf 'blind_id\tmodel\tcontext_length\ttask_no\trecorded_at\n'
    } > "${MAPPING_TSV}"
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "${blind_id}" "${model}" "${context}" "${task_no}" "${now}" >> "${MAPPING_TSV}"
}

print_usage() {
  cat <<EOF
使い方:
  $0 <タスク番号> [--help]

説明:
  軸3・4の回答を、どのモデルのものか分からないブラインドなファイル名で
  results/answers/ 配下に払い出します。モデル名は fixture/.claude/settings.json から
  自動で読み取るため、手入力による転記ミスは発生しません。

  払い出したブラインドID・モデル名・コンテキスト長・タスク番号・記録日時の対応表は
  results/mapping.tsv に追記されます。このファイルは採点時には絶対に参照しないこと
  (ブラインド採点の対応表のため)。

引数:
  <タスク番号>            実施するタスクの番号(例: 1, 2, 3)。tasks/tasks.md のタスク番号と
                          対応させてください。

オプション:
  --help                  このヘルプを表示します。

例:
  $0 1
  $0 2
EOF
}

main() {
  if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
  fi

  local task_no=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        print_usage
        exit 0
        ;;
      --*)
        echo "エラー: 不明なオプション '$1' です。" >&2
        print_usage
        exit 1
        ;;
      *)
        if [[ -n "${task_no}" ]]; then
          echo "エラー: タスク番号は1つだけ指定してください。" >&2
          exit 1
        fi
        task_no="$1"
        shift
        ;;
    esac
  done

  if [[ -z "${task_no}" ]]; then
    echo "エラー: タスク番号を指定してください。" >&2
    print_usage
    exit 1
  fi

  mkdir -p "${RESULT_ANSWERS_DIR}"

  # --- 1. 現在のモデルを読み取る ---
  local model context
  model="$(read_current_model)"
  context="$(read_current_context)"

  # --- 2. 未使用のブラインドIDをランダムに払い出す ---
  local blind_id
  blind_id="$(pick_blind_id)"

  # --- 3. 対応表に追記する ---
  append_mapping_row "${blind_id}" "${model}" "${context}" "${task_no}"

  # --- 4. 空の回答ファイルを作成する(モデル名は絶対に書かない) ---
  local answer_file="${RESULT_ANSWERS_DIR}/${blind_id}.md"
  {
    echo "# タスク${task_no}"
    echo ""
    echo "(ここにエージェントの回答を貼り付けてください)"
  } > "${answer_file}"

  # --- 5. 保存先のパスを表示する ---
  echo "=== ブラインドIDを払い出しました ==="
  echo "  タスク番号: ${task_no}"
  echo "  ブラインドID: ${blind_id}"
  echo "  回答ファイル: ${answer_file}"
  echo ""
  echo "このファイルにエージェントの回答を貼り付けてください。"
  echo ""
  echo "注意: 対応表 ${MAPPING_TSV} は採点時に参照してはいけません(ブラインド採点のため)。"
}

main "$@"
