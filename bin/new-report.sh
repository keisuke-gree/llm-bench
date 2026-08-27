#!/usr/bin/env bash
#
# new-report.sh
#
# reports/_template.html から日付入りのレポートファイルを生成するスクリプト。
#
# ファイル名は「YYYY-MM-DD-<スラグ>.html」の命名規則に従う(reports/README.md参照)。
# 日付を先頭にすることで、ローカルLLMの更新に対して「いつ測ったか」が
# 一目で分かるようにするための規則。
#
# {{TITLE}} と {{DATE}} はこのスクリプトが自動で埋める。それ以外の測定値の
# プレースホルダ({{MODELS}} / {{AXIS12_TABLE}} / {{AXIS34_TABLE}} / {{WAITTIME_TABLE}})は
# あえて埋めない(benchmark-report Skillが results/ の実測値をもとに埋める)。
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

# スラグに許可する文字(英小文字・数字・ハイフンのみ)
readonly SLUG_PATTERN='^[a-z0-9]+(-[a-z0-9]+)*$'

# ============================================================
# ユーティリティ関数
# ============================================================

# スラグが英小文字・数字・ハイフンのみで構成されているかを検証する。
validate_slug() {
  local slug="$1"
  if [[ ! "${slug}" =~ ${SLUG_PATTERN} ]]; then
    echo "エラー: スラグ '${slug}' が不正です。英小文字・数字・ハイフンのみ使用できます。" >&2
    echo "        (先頭・末尾のハイフンや連続ハイフンも不可)" >&2
    echo "        命名例: initial-comparison / qwen3-vs-gemma4 / context-length-recheck" >&2
    exit 1
  fi
}

# ファイル中の {{PLACEHOLDER}} をリテラル文字列で置換する(正規表現の特殊文字を
# エスケープしてsedに渡す。タイトルに/や&が含まれても安全に動くようにするため)。
replace_placeholder() {
  local file="$1" placeholder="$2" value="$3"
  local escaped_value
  escaped_value="$(printf '%s' "${value}" | sed -e 's/[\/&]/\\&/g')"
  local tmp
  tmp="$(mktemp)"
  sed "s/{{${placeholder}}}/${escaped_value}/g" "${file}" > "${tmp}"
  mv "${tmp}" "${file}"
}

# results/ 配下に何が揃っているかを表示する(次にやることの判断材料)。
show_results_inventory() {
  local benchmark_count scores_lines mapping_lines

  benchmark_count="$(find "${RESULTS_DIR}" -maxdepth 1 -name 'benchmark-results-*.md' 2>/dev/null | wc -l | tr -d ' ')"

  if [[ -f "${SCORES_TSV}" ]]; then
    # ヘッダー行を除いた行数(データ行数)を数える
    scores_lines="$(($(wc -l < "${SCORES_TSV}" | tr -d ' ') - 1))"
  else
    scores_lines="0(未作成)"
  fi

  if [[ -f "${MAPPING_TSV}" ]]; then
    # 先頭の注意コメント2行とヘッダー1行を除いたデータ行数を数える
    mapping_lines="$(($(grep -vc '^#' "${MAPPING_TSV}") - 1))"
  else
    mapping_lines="0(未作成)"
  fi

  echo "=== results/ の状況 ==="
  echo "  軸1・2の測定結果(benchmark-results-*.md): ${benchmark_count}件"
  echo "  軸3・4のスコア(scores.tsv): ${scores_lines}行"
  echo "  ブラインドID対応表(mapping.tsv): ${mapping_lines}行"
}

print_usage() {
  cat <<EOF
使い方:
  $0 <スラグ> [--title "..."] [--help]

説明:
  reports/_template.html から reports/YYYY-MM-DD-<スラグ>.html を生成します。
  日付は実行日('date +%Y-%m-%d')です。{{TITLE}} と {{DATE}} は自動で埋めますが、
  測定値のプレースホルダ({{MODELS}} 等)はあえて埋めません(benchmark-report Skillが
  results/ の実測値をもとに埋めます)。

引数:
  <スラグ>                ファイル名に使うスラグ。英小文字・数字・ハイフンのみ。
                          (命名例: initial-comparison / qwen3-vs-gemma4)

オプション:
  --title "..."           レポートのタイトル({{TITLE}}に入る値)。
                          省略時はスラグをそのままタイトルとして使います。
  --help                  このヘルプを表示します。

異常系:
  - スラグに英小文字・数字・ハイフン以外の文字が含まれる場合はエラーで停止します。
  - 生成先のファイルが既に存在する場合は上書きせずエラーで停止します。

例:
  $0 initial-comparison
  $0 qwen3-vs-gemma4 --title "qwen3-coder:30b と gemma4:26b の比較"
EOF
}

main() {
  if [[ $# -eq 0 ]]; then
    print_usage
    exit 1
  fi

  local slug="" title=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        print_usage
        exit 0
        ;;
      --title)
        [[ $# -ge 2 ]] || { echo "エラー: --title には値が必要です。" >&2; exit 1; }
        title="$2"
        shift 2
        ;;
      --*)
        echo "エラー: 不明なオプション '$1' です。" >&2
        print_usage
        exit 1
        ;;
      *)
        if [[ -n "${slug}" ]]; then
          echo "エラー: スラグは1つだけ指定してください。" >&2
          exit 1
        fi
        slug="$1"
        shift
        ;;
    esac
  done

  if [[ -z "${slug}" ]]; then
    echo "エラー: スラグを指定してください。" >&2
    print_usage
    exit 1
  fi

  validate_slug "${slug}"

  if [[ -z "${title}" ]]; then
    title="${slug}"
  fi

  if [[ ! -f "${TEMPLATE_HTML}" ]]; then
    echo "エラー: 雛形 ${TEMPLATE_HTML} が見つかりません。" >&2
    exit 1
  fi

  local today
  today="$(date +%Y-%m-%d)"
  local report_file="${REPORTS_DIR}/${today}-${slug}.html"

  if [[ -f "${report_file}" ]]; then
    echo "エラー: ${report_file} は既に存在します。上書きを防ぐため停止します。" >&2
    echo "        別のスラグを指定するか、既存ファイルを編集してください。" >&2
    exit 1
  fi

  cp "${TEMPLATE_HTML}" "${report_file}"
  replace_placeholder "${report_file}" "TITLE" "${title}"
  replace_placeholder "${report_file}" "DATE" "${today}"

  echo "=== レポートを生成しました ==="
  echo "  ${report_file}"
  echo ""
  echo "  埋めたプレースホルダ: {{TITLE}} = ${title} / {{DATE}} = ${today}"
  echo "  残したプレースホルダ: {{MODELS}} / {{AXIS12_TABLE}} / {{AXIS34_TABLE}} / {{WAITTIME_TABLE}}"
  echo ""

  show_results_inventory

  echo ""
  echo "=== 次にやること ==="
  echo "  benchmark-report Skill を使って、results/ の実測値とスコアを"
  echo "  ${report_file} に反映してください。"
}

main "$@"
