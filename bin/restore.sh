#!/usr/bin/env bash
#
# restore.sh
#
# 検証環境を片付けるスクリプト。bin/prepare.sh が起動した `ollama serve` を停止する。
#
# ~/.zshrc は prepare.sh が元々一切書き換えていないため、このスクリプトでも
# 復元作業は不要である(そもそも何も変えていないため、戻すものが無い)。
#
# fixture/.claude/settings.json はあえて元に戻さない。次回 bin/prepare.sh を実行すれば
# どうせ上書きされる値であり、ここで戻すための「正しい値」を本スクリプトが
# 決め打ちで持つこと自体が、将来テーブルの値が変わった際の食い違いの温床になるため。
#
# 実行環境: bash 3.2.57 (macOS標準) 互換。人間が通常のターミナルから実行する想定。
# 実行場所: このリポジトリのルートディレクトリ(相対パスはスクリプト自身の位置から解決する)。
#
set -euo pipefail

# ============================================================
# 設定値
# ============================================================

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly BENCH_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

readonly RESULTS_DIR="${BENCH_ROOT}/results"
readonly PID_FILE="${RESULTS_DIR}/.ollama.pid"

readonly STOP_TIMEOUT_SEC=30
readonly SERVER_PORT="11434"   # Ollamaが待ち受けるポート

# ============================================================
# メイン処理
# ============================================================

do_restore() {
  if [[ ! -f "${PID_FILE}" ]]; then
    echo "PIDファイル(${PID_FILE})が見つかりません。"
    echo "bin/prepare.sh が起動したサーバーが無い(または既に停止済み)と判断し、何もしません。"
  else
    local pid
    pid="$(cat "${PID_FILE}")"

    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      echo "=== ollama serve (PID: ${pid}) を停止します ==="
      kill "${pid}" 2>/dev/null || true

      local waited=0
      while kill -0 "${pid}" 2>/dev/null; do
        if [ "${waited}" -ge "${STOP_TIMEOUT_SEC}" ]; then
          echo "警告: 通常停止がタイムアウトしたため強制終了(kill -9)します。" >&2
          kill -9 "${pid}" 2>/dev/null || true
          break
        fi
        sleep 1
        waited=$((waited + 1))
      done
      echo "  停止しました。"
    else
      echo "PID ${pid} のプロセスは既に存在しません(既に停止済みと判断します)。"
    fi

    rm -f "${PID_FILE}"
    echo "  ${PID_FILE} を削除しました。"
  fi

  # PIDファイルに記録されていないサーバーが残っていないか確認する。
  #
  # なぜこの確認が必要か:
  #   bin/prepare.sh が起動したサーバーはPIDが記録されるが、それ以外の経路で
  #   起動されたサーバー(手で `ollama serve` を叩いた、エージェントが即興で
  #   起動した等)は記録されないため、PIDファイルだけを見ていると取りこぼす。
  #   実際に記録外のサーバーが残り、次回の測定に干渉しかけた事例がある。
  #   このスクリプトの目的は「ベンチマーク用のサーバーを一つも残さないこと」
  #   なので、ポートを直接見て確認する。
  echo ""
  echo "=== 記録外のサーバーが残っていないか確認します ==="
  local stray_pids
  stray_pids="$(lsof -nP -iTCP:"${SERVER_PORT}" -sTCP:LISTEN -t 2>/dev/null || true)"

  if [[ -z "${stray_pids}" ]]; then
    echo "  ポート ${SERVER_PORT} を待ち受けているプロセスはありません。"
  else
    echo "  ポート ${SERVER_PORT} を待ち受けているプロセスが残っています: ${stray_pids}"
    echo "  bin/prepare.sh 以外の経路で起動されたサーバーと判断し、停止します。"
    local p
    for p in ${stray_pids}; do
      kill "${p}" 2>/dev/null || true
    done

    local waited=0
    while [[ -n "$(lsof -nP -iTCP:"${SERVER_PORT}" -sTCP:LISTEN -t 2>/dev/null || true)" ]]; do
      if [ "${waited}" -ge "${STOP_TIMEOUT_SEC}" ]; then
        echo "警告: 停止がタイムアウトしました。手動で確認してください:" >&2
        echo "         lsof -nP -iTCP:${SERVER_PORT} -sTCP:LISTEN" >&2
        break
      fi
      sleep 1
      waited=$((waited + 1))
    done
    echo "  停止しました。"
  fi

  echo ""
  echo "=== ~/.zshrc について ==="
  echo "bin/prepare.sh は ~/.zshrc を元々一切書き換えていないため、復元作業は不要です。"
  echo "通常の運用に戻すには、いつも通り以下を実行してください:"
  echo ""
  echo "  source ~/.zshrc && ollama serve"
  echo ""
  echo "=== fixture/.claude/settings.json について ==="
  echo "このスクリプトでは意図的に元に戻していません。次回 './bin/prepare.sh <モデル名>' を"
  echo "実行すれば、その時点で指定したモデル用の値に上書きされます。"
}

print_usage() {
  cat <<EOF
使い方:
  $0 [--help]

説明:
  bin/prepare.sh が起動した 'ollama serve' を停止し、検証環境を片付けます。
  results/.ollama.pid を参照して対象プロセスを停止し、PIDファイルを削除します。

  ~/.zshrc は prepare.sh が元々書き換えていないため、本スクリプトでも
  何も書き換えません(復元作業そのものが不要)。

  fixture/.claude/settings.json はあえて元に戻しません。次回 bin/prepare.sh を
  実行すれば上書きされるためです。

オプション:
  --help                  このヘルプを表示します。
EOF
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        echo "エラー: 不明な引数 '$1' です。" >&2
        print_usage
        exit 1
        ;;
    esac
  done

  do_restore
}

main "$@"
