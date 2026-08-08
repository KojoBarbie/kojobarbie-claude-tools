# 紙芝居プロトタイプの雛形（showcase/lib/proto.tsx）

全アプリ共用の共通部品。**初回に1度だけこのファイルを作り、以後はアプリごとの
`app/apps/{slug}/mock/page.tsx` から使う**（毎回ゼロから書くと品質がぶれる）。

そのままコピーして `showcase/lib/proto.tsx` に置けば動く。

## lib/proto.tsx

```tsx
"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

export type Tone = {
  bg: string;        // 画面の背景
  surface: string;   // カード等の面
  text: string;      // 主テキスト
  muted: string;     // 副テキスト
  accent: string;    // 唯一の強調色
  radius: number;    // 基準の角丸
};

export type Screen = {
  id: string;
  label: string;                              // 画面下のチップに出る名前（例: "① 初回起動"）
  render: (go: (id: string) => void) => ReactNode;
};

const CSS = `
.pk-wrap { display:flex; flex-direction:column; align-items:center; gap:16px; }
.pk-phone {
  width:min(360px,90vw); aspect-ratio:393/852; position:relative; overflow:hidden;
  border:10px solid #1c1c1e; border-radius:52px; background:var(--pk-bg);
  box-shadow:0 24px 60px rgba(0,0,0,.18);
}
.pk-island {
  position:absolute; top:10px; left:50%; transform:translateX(-50%);
  width:104px; height:30px; border-radius:16px; background:#1c1c1e; z-index:5;
}
.pk-home {
  position:absolute; bottom:8px; left:50%; transform:translateX(-50%);
  width:132px; height:5px; border-radius:3px; background:var(--pk-text); opacity:.25; z-index:5;
}
.pk-screen {
  position:absolute; inset:0; padding:56px 20px 28px; overflow-y:auto;
  color:var(--pk-text); font-size:16px; line-height:1.5;
  animation:pk-in .3s cubic-bezier(.22,.61,.36,1) both;
}
@keyframes pk-in { from { opacity:0; transform:translateX(14px); } to { opacity:1; transform:none; } }
@keyframes pk-back { from { opacity:0; transform:translateX(-14px); } to { opacity:1; transform:none; } }
.pk-screen[data-dir="back"] { animation-name:pk-back; }

/* 押下フィードバック: 0.1秒以内に反応が返ることが体感品質を決める */
.pk-tap { cursor:pointer; transition:transform .12s ease, filter .12s ease; -webkit-tap-highlight-color:transparent; }
.pk-tap:active { transform:scale(.97); filter:brightness(.96); }

.pk-chips { display:flex; flex-wrap:wrap; gap:6px; justify-content:center; max-width:min(360px,90vw); }
.pk-chip {
  font-size:12px; padding:6px 11px; border-radius:999px; border:1px solid #e2e2e6;
  background:#fff; color:#6b6b70; cursor:pointer; transition:all .15s ease;
}
.pk-chip[data-on="1"] { background:#1c1c1e; border-color:#1c1c1e; color:#fff; }
.pk-note { font-size:12px; color:#8a8a8f; text-align:center; max-width:min(360px,90vw); }

/* 達成の演出。0.4〜0.8秒で終わらせる（毎日見るものが長いとノイズになる） */
.pk-confetti { position:absolute; inset:0; pointer-events:none; overflow:hidden; z-index:4; }
.pk-confetti i {
  position:absolute; top:-12px; width:8px; height:12px; border-radius:2px;
  animation:pk-fall .9s ease-in forwards;
}
@keyframes pk-fall {
  to { transform:translateY(560px) rotate(540deg); opacity:0; }
}
.pk-pop { animation:pk-pop .45s cubic-bezier(.2,1.4,.4,1) both; }
@keyframes pk-pop { from { transform:scale(.6); opacity:0; } to { transform:none; opacity:1; } }
`;

/** 紙芝居本体。screens の最初の画面から始まり、go(id) で遷移する。 */
export function Prototype({ screens, tone, note }: { screens: Screen[]; tone: Tone; note?: string }) {
  const [current, setCurrent] = useState(screens[0].id);
  const [dir, setDir] = useState<"fwd" | "back">("fwd");
  const order = useRef(screens.map((s) => s.id));

  const go = (id: string) => {
    const from = order.current.indexOf(current);
    const to = order.current.indexOf(id);
    setDir(to < from ? "back" : "fwd");
    setCurrent(id);
  };

  const screen = screens.find((s) => s.id === current) ?? screens[0];
  const vars = {
    "--pk-bg": tone.bg, "--pk-surface": tone.surface, "--pk-text": tone.text,
    "--pk-muted": tone.muted, "--pk-accent": tone.accent, "--pk-radius": `${tone.radius}px`,
  } as React.CSSProperties;

  return (
    <div className="pk-wrap" style={vars}>
      <style dangerouslySetInnerHTML={{ __html: CSS }} />
      <div className="pk-phone">
        <div className="pk-island" />
        {/* key を変えて遷移アニメを再生させる */}
        <div className="pk-screen" data-dir={dir} key={screen.id}>
          {screen.render(go)}
        </div>
        <div className="pk-home" />
      </div>
      <div className="pk-chips">
        {screens.map((s) => (
          <button key={s.id} className="pk-chip" data-on={s.id === current ? "1" : "0"}
                  onClick={() => go(s.id)}>{s.label}</button>
        ))}
      </div>
      <p className="pk-note">{note ?? "画面内のボタンを実際に押せます。チップで直接移動もできます。"}</p>
    </div>
  );
}

/** 押せる要素。押下フィードバック付き。 */
export function Tap({ onTap, children, style }:
  { onTap: () => void; children: ReactNode; style?: React.CSSProperties }) {
  return <div className="pk-tap" style={style} onClick={onTap} role="button" tabIndex={0}
              onKeyDown={(e) => e.key === "Enter" && onTap()}>{children}</div>;
}

/** 主ボタン（唯一の強調装置）。1画面に1つまで。 */
export function PrimaryButton({ label, onTap }: { label: string; onTap: () => void }) {
  return (
    <Tap onTap={onTap} style={{
      background: "var(--pk-accent)", color: "#fff", textAlign: "center",
      padding: "16px 20px", borderRadius: 999, fontWeight: 600, fontSize: 17,
    }}>{label}</Tap>
  );
}

export function Card({ children, style }: { children: ReactNode; style?: React.CSSProperties }) {
  return <div style={{
    background: "var(--pk-surface)", borderRadius: "var(--pk-radius)", padding: 20,
    boxShadow: "0 1px 3px rgba(0,0,0,.04)", ...style,
  }}>{children}</div>;
}

/** 達成の瞬間の紙吹雪。マウント時に一度だけ降り、0.9秒で消える。 */
export function Confetti({ colors }: { colors: string[] }) {
  return (
    <div className="pk-confetti" aria-hidden>
      {Array.from({ length: 18 }, (_, i) => (
        <i key={i} style={{
          left: `${(i * 37) % 100}%`,
          background: colors[i % colors.length],
          animationDelay: `${(i % 6) * 0.06}s`,
        }} />
      ))}
    </div>
  );
}

/** 成果の数字をカウントアップさせる。感情のフックは数字の大きさと動きで作る。 */
export function CountUp({ to, suffix = "", duration = 700 }:
  { to: number; suffix?: string; duration?: number }) {
  const [n, setN] = useState(0);
  useEffect(() => {
    const start = performance.now();
    let raf = 0;
    const tick = (now: number) => {
      const p = Math.min(1, (now - start) / duration);
      setN(Math.round(to * (1 - Math.pow(1 - p, 3)))); // ease-out
      if (p < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [to, duration]);
  return <span>{n}{suffix}</span>;
}
```

## 使い方（app/apps/{slug}/mock/page.tsx）

> **モックページには必ず `"use client"` を付ける。** `screens` の `render` は関数なので、
> Server Component から Client Component へは渡せない（`Functions cannot be passed directly to
> Client Components` でビルドが落ちる）。静的エクスポートでも Client Component は
> ビルド時にプリレンダされるので、これで問題ない。
> **tone / prd ページは Server Component のまま**でよい（prd ページは fs を使うので Server 必須）。

```tsx
"use client";

import { Prototype, Tap, PrimaryButton, Card, Confetti, CountUp, type Tone } from "../../../../lib/proto";

// tone ページで推した案の値をそのまま持ってくる
const tone: Tone = {
  bg: "#FBF9F4", surface: "#FFFFFF", text: "#1A1A1A",
  muted: "#8E8E93", accent: "#E1483B", radius: 18,
};

export default function Page() {
  return (
    <main style={{ padding: "24px 0 48px" }}>
      <h1 style={{ textAlign: "center", fontSize: 20, marginBottom: 4 }}>Sleep Streak — モック</h1>
      <p style={{ textAlign: "center", color: "#8a8a8f", fontSize: 13, marginBottom: 20 }}>
        A案（静謐ミニマル）で作成
      </p>
      <Prototype tone={tone} screens={[
        {
          id: "first", label: "① 初回起動",
          render: (go) => (
            <>
              <h2 style={{ fontSize: 30, lineHeight: 1.35, marginTop: 40 }}>
                眠った時間を、<br />ただ置いていく。
              </h2>
              <p style={{ color: "var(--pk-muted)", marginTop: 12, marginBottom: 40 }}>
                記録は1タップ。分析も採点もしません。
              </p>
              <PrimaryButton label="はじめる" onTap={() => go("empty")} />
            </>
          ),
        },
        {
          id: "empty", label: "② 空の状態",
          render: (go) => (
            <>
              {/* 空状態は「次の一歩」を必ず示す。イラストと励ましだけで終わらせない */}
              <div style={{ marginTop: 120, textAlign: "center" }}>
                <div style={{ fontSize: 40, opacity: .25 }}>◯</div>
                <p style={{ marginTop: 20, color: "var(--pk-muted)" }}>
                  まだ記録がありません。<br />今朝の睡眠から始めましょう。
                </p>
              </div>
              <div style={{ marginTop: 40 }}>
                <PrimaryButton label="昨夜の睡眠を記録" onTap={() => go("record")} />
              </div>
            </>
          ),
        },
        {
          id: "record", label: "③ 記録（コア行動）",
          render: (go) => (
            <>
              <h2 style={{ fontSize: 20, marginTop: 24 }}>昨夜はどうでしたか</h2>
              <div style={{ display: "grid", gap: 10, marginTop: 20 }}>
                {["ぐっすり眠れた", "まあまあ", "あまり眠れなかった"].map((label) => (
                  <Tap key={label} onTap={() => go("done")}>
                    <Card><span>{label}</span></Card>
                  </Tap>
                ))}
              </div>
            </>
          ),
        },
        {
          id: "done", label: "④ 完了（山場）",
          render: (go) => (
            <>
              <Confetti colors={["#E1483B", "#F5C26B", "#1A1A1A"]} />
              <div className="pk-pop" style={{ textAlign: "center", marginTop: 130 }}>
                <div style={{ fontSize: 64, fontWeight: 700, letterSpacing: -2 }}>
                  <CountUp to={7} />日
                </div>
                <p style={{ color: "var(--pk-muted)", marginTop: 8 }}>連続で記録できました</p>
              </div>
              <div style={{ marginTop: 60 }}>
                <PrimaryButton label="今日を終える" onTap={() => go("home")} />
              </div>
            </>
          ),
        },
        {
          id: "home", label: "⑤ 溜まった状態",
          render: () => (
            <>
              <h2 style={{ fontSize: 20, marginTop: 24, marginBottom: 16 }}>今月</h2>
              <Card style={{ marginBottom: 12 }}>
                <div style={{ fontSize: 40, fontWeight: 700 }}>7<span style={{ fontSize: 16, fontWeight: 400 }}>日連続</span></div>
              </Card>
              {/* リアルなデータを入れる。「サンプル1」ではレイアウトの検証にならない */}
              {[["3/12（火）", "ぐっすり"], ["3/11（月）", "まあまあ"], ["3/10（日）", "ぐっすり"]].map(([d, v]) => (
                <div key={d} style={{ display: "flex", justifyContent: "space-between", padding: "14px 4px", borderBottom: "1px solid rgba(0,0,0,.06)" }}>
                  <span style={{ color: "var(--pk-muted)" }}>{d}</span><span>{v}</span>
                </div>
              ))}
            </>
          ),
        },
      ]} />
    </main>
  );
}
```

## 品質のチェック（作った後に自分で見る）

- [ ] 4〜6画面あり、**初回 / コア行動 / 完了の瞬間 / 空状態**が含まれている
- [ ] 実際にボタンを押して最後まで辿れる（行き止まりの画面がない）
- [ ] 完了の瞬間に演出がある。かつ **1秒以内で終わる**
- [ ] コピーが全部実物（「テキスト」「サンプル」が1つも無い）
- [ ] データがリアル（日付・数値・文言がありそうな値）
- [ ] 強調装置（PrimaryButton）が1画面に1つまで
- [ ] `npx next build` が通る
