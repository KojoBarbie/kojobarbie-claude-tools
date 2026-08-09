#!/usr/bin/env bash
# アプリの公開バージョン（MARKETING_VERSION / pubspec version）をリポジトリ内の
# 全定義箇所で揃えて更新する。
#
#   bump_marketing_version.sh <repo_path> [new_version] [--dry-run]
#
# new_version 省略時はパッチを1つ上げる（1.0.0 → 1.0.1、"1.0" のような2要素は 1.0 → 1.0.1）。
#
# 版数の定義箇所はリポジトリごとに違う（xcconfig / project.yml / pbxproj / pubspec.yaml）ため、
# 現行版を検出してから「現行版と完全一致する箇所だけ」を置換する。テストターゲットに
# 残った 1.0 のような無関係な値を巻き込まないための決め方であり、ここを緩めてはいけない。
#
# 標準出力に "<old> -> <new>" と更新したファイルを出す。更新不要（既に new と同じ）なら
# 何も書き換えず exit 0（冪等）。
set -euo pipefail

REPO="${1:?usage: bump_marketing_version.sh <repo_path> [new_version] [--dry-run]}"
NEW=""
DRY_RUN=0
shift
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) NEW="$arg" ;;
  esac
done

cd "$REPO"

# 版数を持ちうるファイルを集める（Pods / 作業用 worktree は除く）。
# macOS 標準の bash 3.2 でも動くよう mapfile は使わない。
FILES=()
while IFS= read -r line; do
  [ -n "$line" ] && FILES+=("$line")
done < <(git ls-files -- '*.xcconfig' '*/project.pbxproj' 'project.yml' 'pubspec.yaml' 2>/dev/null \
           | grep -v -E '(^|/)(Pods|\.claude)/' || true)
[ "${#FILES[@]}" -gt 0 ] || { echo "版数の定義ファイルが見つからない: $REPO" >&2; exit 1; }

# 現行版の検出。真実源になりうる順（xcconfig > project.yml > pubspec.yaml）で先に見つかったものを採り、
# どれも無ければ pbxproj の中で最も高い semver を現行版とみなす。
extract() { # <file> → その file が持つ版数（1行1つ）
  case "$1" in
    *.xcconfig)      sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([0-9][0-9.]*).*/\1/p' "$1" ;;
    project.yml)     sed -nE 's/.*MARKETING_VERSION:[[:space:]]*"?([0-9][0-9.]*)"?.*/\1/p' "$1" ;;
    pubspec.yaml)    sed -nE 's/^version:[[:space:]]*([0-9][0-9.]*).*/\1/p' "$1" ;;
    */project.pbxproj) sed -nE 's/.*MARKETING_VERSION = ([0-9][0-9.]*);.*/\1/p' "$1" ;;
  esac
}

CURRENT=""
for pat in '*.xcconfig' 'project.yml' 'pubspec.yaml'; do
  for f in "${FILES[@]}"; do
    case "$f" in $pat) ;; *) continue ;; esac
    v="$(extract "$f" | head -1)"
    [ -n "$v" ] && { CURRENT="$v"; break 2; }
  done
done
if [ -z "$CURRENT" ]; then
  CURRENT="$(for f in "${FILES[@]}"; do extract "$f"; done | sort -uV | tail -1)"
fi
[ -n "$CURRENT" ] || { echo "現行バージョンを検出できない: $REPO" >&2; exit 1; }

if [ -z "$NEW" ]; then
  # パッチ+1。2要素（1.0）は 1.0.1 に伸ばす
  case "$CURRENT" in
    *.*.*) NEW="$(echo "$CURRENT" | awk -F. '{printf "%s.%s.%d", $1, $2, $3+1}')" ;;
    *.*)   NEW="$CURRENT.1" ;;
    *)     echo "版数の形式が扱えない: $CURRENT" >&2; exit 1 ;;
  esac
fi

if [ "$CURRENT" = "$NEW" ]; then
  echo "$CURRENT -> $NEW (変更なし)"
  exit 0
fi

echo "$CURRENT -> $NEW"
for f in "${FILES[@]}"; do
  case "$f" in
    pubspec.yaml)
      # version: 1.2.1+18 → ビルド番号(+N)は温存して版数だけ差し替える
      grep -qE "^version:[[:space:]]*${CURRENT}([+ ]|$)" "$f" || continue
      [ "$DRY_RUN" = 1 ] || perl -pi -e "s/^version:(\s*)\Q${CURRENT}\E(?=[+\s]|$)/version:\${1}${NEW}/" "$f"
      ;;
    *.xcconfig|project.yml|*/project.pbxproj)
      grep -q "MARKETING_VERSION" "$f" || continue
      extract "$f" | grep -qx "$CURRENT" || continue
      [ "$DRY_RUN" = 1 ] || perl -pi -e "s/(MARKETING_VERSION\s*[:=]\s*\"?)\Q${CURRENT}\E(\"?\s*;?)\$/\${1}${NEW}\${2}/" "$f"
      ;;
    *) continue ;;
  esac
  echo "  updated: $f"
done
