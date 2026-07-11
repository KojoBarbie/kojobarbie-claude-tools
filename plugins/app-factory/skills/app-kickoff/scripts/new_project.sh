#!/bin/bash
# 新規iOSアプリプロジェクトの雛形を生成する（XcodeGenベース）
# Usage: new_project.sh <AppName> [dest_dir]
#   AppName: PascalCaseの英語名（例: SleepStreak）。structやターゲット名に使うため英数字のみ
#   dest_dir: 省略時は ~/dev/swift/<AppName>
set -euo pipefail

APP_NAME="${1:?アプリ名（PascalCase英数字）を指定してください}"
DEST="${2:-$HOME/dev/swift/$APP_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/../assets"

if [[ ! "$APP_NAME" =~ ^[A-Za-z][A-Za-z0-9]*$ ]]; then
  echo "ERROR: アプリ名は英字始まりの英数字のみにしてください（Swiftの型名・ターゲット名に使用）" >&2
  exit 1
fi
if [[ -e "$DEST" ]]; then
  echo "ERROR: $DEST は既に存在します" >&2
  exit 1
fi

BUNDLE_SLUG="$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]')"

mkdir -p "$DEST/$APP_NAME" "$DEST/${APP_NAME}Tests" "$DEST/docs"

# --- project.yml ---
# Apple Developer Team ID は公開リポジトリに置かないため環境変数から注入する
# （claude-cron の .env に APPLE_TEAM_ID=XXXXXXXXXX を定義しておく）
if [ -z "${APPLE_TEAM_ID:-}" ]; then
  echo "ERROR: APPLE_TEAM_ID が未設定です。~/dev/others/claude-cron/.env に追加してください" >&2
  exit 1
fi
sed -e "s/__APP_NAME__/$APP_NAME/g" -e "s/__BUNDLE_SLUG__/$BUNDLE_SLUG/g" \
  -e "s/__TEAM_ID__/$APPLE_TEAM_ID/g" \
  "$ASSETS_DIR/project.yml.template" > "$DEST/project.yml"

# --- Swift sources ---
cat > "$DEST/$APP_NAME/${APP_NAME}App.swift" <<EOF
import SwiftUI

@main
struct ${APP_NAME}App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
EOF

cat > "$DEST/$APP_NAME/ContentView.swift" <<EOF
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("$APP_NAME")
    }
}

#Preview {
    ContentView()
}
EOF

cat > "$DEST/${APP_NAME}Tests/${APP_NAME}Tests.swift" <<EOF
import Testing
@testable import $APP_NAME

struct ${APP_NAME}Tests {
    @Test func placeholder() {
        #expect(true)
    }
}
EOF

# --- Assets.xcassets ---
XCASSETS="$DEST/$APP_NAME/Assets.xcassets"
mkdir -p "$XCASSETS/AppIcon.appiconset" "$XCASSETS/AccentColor.colorset"
cat > "$XCASSETS/Contents.json" <<'EOF'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
cat > "$XCASSETS/AppIcon.appiconset/Contents.json" <<'EOF'
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
cat > "$XCASSETS/AccentColor.colorset/Contents.json" <<'EOF'
{
  "colors" : [
    { "color" : { "platform" : "universal", "reference" : "systemBlueColor" }, "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

# --- .gitignore ---
cp "$ASSETS_DIR/gitignore.template" "$DEST/.gitignore"

# --- xcodegen ---
cd "$DEST"
xcodegen generate

echo "OK: $DEST に ${APP_NAME}.xcodeproj を生成しました"
