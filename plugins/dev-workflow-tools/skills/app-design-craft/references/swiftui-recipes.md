# SwiftUI レシピ：原則をコードに固定する

設計方針（→ `design-decisions.md`）を「守られるコード」にするためのパターン集。
方針を散文でなくトークン/モディファイア/共通Viewとして1か所に置くと、全画面が自動的に揃い、逸脱が起きにくい。

コードはあくまで出発点。プロジェクトの規約・最低OSに合わせて調整する。コード自体の良し悪し（API選択・パフォーマンス）は `swiftui-pro` の領域。

## 目次
1. デザイントークンを1か所に集約
2. スペーシングスケール
3. タイポの役割をテキストスタイル化
4. 唯一の強調装置（黒ピル／アクセントボタン）
5. 共通カード（グルーピング）
6. 状態（空・ローディング・エラー）を必ず用意
7. アクセシビリティの最低ライン

---

## 1. デザイントークンを1か所に集約

色・半径・影を散らさず一元管理。Asset Catalog に色を登録するとダーク対応も楽。

```swift
import SwiftUI

enum DS {                       // Design System
    // 色（Asset Catalog 推奨。ここでは例示）
    static let base   = Color("Base")        // オフホワイト
    static let ink    = Color("Ink")         // ほぼ黒
    static let grayHi = Color(.secondaryLabel)
    static let grayLo = Color(.tertiaryLabel)
    static let accent = Color("Accent")      // 意味のある1色だけ

    // 半径・影（揃える）
    static let radius: CGFloat = 16
    static let cardShadow = Color.black.opacity(0.04)
}
```

> アクセント色は「1つだけ」を物理的に守るため、`accent` を1定義に絞る。色を足したくなったら、まずサイズ・余白・太さで差をつけられないか検討する（→ design-decisions ①）。

---

## 2. スペーシングスケール

半端な数値を散らさない。名前付き段階だけ使う。

```swift
extension CGFloat {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48
}

// 使用例：画面余白は固定、要素間はスケールに乗せる
VStack(alignment: .leading, spacing: .s16) { /* … */ }
    .padding(.horizontal, .s24)
```

レビュー観点：`padding(.leading, 13)` のような直値リテラルが散っていたら、それは「雑」に見える元。スケールへ寄せる。

---

## 3. タイポの役割をテキストスタイル化

サイズをその場で書かず、役割名で呼ぶ。和文見出しと欧文ラベルを型として分ける。

```swift
extension Text {
    func dsDisplay() -> some View {            // 特大見出し（伝える主役）
        self.font(.system(size: 34, weight: .bold))
            .foregroundStyle(DS.ink)
            .lineSpacing(2)
    }
    func dsTitle() -> some View {
        self.font(.system(size: 22, weight: .semibold)).foregroundStyle(DS.ink)
    }
    func dsBody() -> some View {
        self.font(.system(size: 17)).foregroundStyle(DS.ink).lineSpacing(4)
    }
    func dsLabel() -> some View {              // 欧文・極小・キャプス（洗練）
        self.font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(DS.grayHi)
    }
}

// 例：数字を主役に（感情の重み＝サイズ）
VStack(spacing: .s4) {
    Text("15").font(.system(size: 44, weight: .bold)).foregroundStyle(DS.ink)
    Text("DAYS").dsLabel()
}
```

---

## 4. 唯一の強調装置

最重要情報だけが光る装置を1つ作り、それ以外で強調しない。

```swift
// 塗りつぶし黒ピル：締切・残数など時限/最重要を1画面1回だけ
struct EmphasisPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.base)
            .padding(.horizontal, .s12).padding(.vertical, .s8)
            .background(DS.ink, in: Capsule())
    }
}

// アクセント色は「主CTA」だけに使う
struct PrimaryButton: View {
    let title: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, .s16)
        }
        .foregroundStyle(.white)
        .background(DS.accent, in: RoundedRectangle(cornerRadius: DS.radius))
    }
}
```

レビュー観点：1画面に強調（塗りピル＋色付きボタン＋太字バッジ…）が3つ以上あったら、強調が無効化している。1〜2に絞る。

---

## 5. 共通カード（グルーピング）

関連要素を「塊」にして理解速度を上げる。角丸・影を全カードで統一。

```swift
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.s16)
            .background(DS.base)
            .clipShape(RoundedRectangle(cornerRadius: DS.radius))
            .overlay(RoundedRectangle(cornerRadius: DS.radius)
                .stroke(DS.grayLo.opacity(0.4), lineWidth: 0.5))
            .shadow(color: DS.cardShadow, radius: 8, y: 2)   // 極薄
    }
}
```

影は「気づかれない強さ」に。濃い影・バラバラの半径は世界観を壊す（→ rubric: Craft）。

---

## 6. 状態を必ず用意

空・ローディング・エラーが白画面のまま、はブランドの説得力を最も削ぐ。世界観のある空状態を設計する。

```swift
struct EmptyStateView: View {
    let message: String
    var body: some View {
        VStack(spacing: .s12) {
            Image(systemName: "tray")           // 線アイコンで軽やかに
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DS.grayLo)
            Text(message).dsBody().foregroundStyle(DS.grayHi)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.s32)
    }
}
```

空状態の言葉もボイス（→ design-decisions ⑤）に従う。「データがありません」で済ませない。

---

## 7. アクセシビリティの最低ライン

静けさ・余白の設計は元々アクセシブルと相性が良い。最低限これを守る。

- タップ領域は44pt四方以上（`.frame(minHeight: 44)` / `.contentShape`）。
- 文字色と背景のコントラスト比を確保（薄グレー文字を背景に乗せすぎない）。
- Dynamic Type を壊さない（固定サイズの多用に注意。重要テキストは `.font(.title)` 等の相対指定も検討）。
- 色だけで状態を伝えない（選択を色＋形/チェックで示す）。

レビュー観点：「静か＝薄い文字」になりすぎてコントラスト不足、はよくある罠。静けさは余白で出し、可読性は守る。
