# Onboarding & Tutorial Knowledge Base

79件の日英記事から統合した専門知識データベース。

## Table of Contents

1. [Critical Statistics](#1-critical-statistics)
2. [6 Design Patterns](#2-six-design-patterns)
3. [Anti-Patterns (12 Categories)](#3-anti-patterns)
4. [Case Studies](#4-case-studies)
5. [Timeline Framework](#5-timeline-framework)
6. [5 Cross-Cutting Principles](#6-five-cross-cutting-principles)
7. [Push vs Pull Model](#7-push-vs-pull-model)
8. [Progressive Disclosure](#8-progressive-disclosure)
9. [AI & Emerging Trends](#9-ai-and-emerging-trends)

---

## 1. Critical Statistics

### Abandonment

| Metric | Value | Source |
|--------|-------|--------|
| DAU loss within 3 days of install | **77%** | Andrew Chen |
| Churn within 24 hours | **70%** | AppsFlyer |
| User loss within 30 days | **90%** | AppsFlyer |
| Next-day retention (all apps avg) | **25-28%** | Statista / GetStream |
| 7-day retention (all apps avg) | **13-18%** | DesignRush / GetStream |
| 30-day retention (all apps avg) | **6-8%** | Statista / GetStream |
| Users who open once and never return | **25%** | Localytics |
| Users who skip tutorials | **70%** | i3design |
| Coach mark read rate (unoptimized) | **0/8** users | Livefront |
| Users who abandon if >3 registration screens | **3x more likely** | Multiple |

### Positive Impact

| Metric | Value | Source |
|--------|-------|--------|
| Retention improvement with good onboarding | up to **50%** | Multiple |
| Personalized onboarding retention improvement | **40-82%** | UserGuiding / Brandon Hall |
| Interactive tour feature adoption increase | **42%** | UserGuiding |
| Tooltip-driven retention improvement | **30%** | UserGuiding |
| Social login completion rate boost | **60%** | UserGuiding |
| Form field 11→4 conversion increase | **120%** | Eleken |
| Expedia single field removal annual revenue | **$12M** | Eleken |
| Activation 25% up → MRR increase | **34.3%** | Appcues |
| 5% retention increase → profit increase | **95%** | Custify |
| Gamification Day-1 retention boost | up to **60%** | StriveCloud |
| Progress bar completion rate boost | **+12%** | Chameleon (550M+ interactions) |
| Deferred deep link signup multiplier | **1.8x** | Branch |
| Session frequency with small celebrations | **+30%** | Multiple |
| In-app messaging apps retention multiplier | **3x** | Multiple |
| Apps with onboarding: 1-month retention | **~60%** | Repro |
| Apps without onboarding: 1-month retention | **39%** | Repro |
| Hands-on learning information retention | **75%** | Multiple |
| Reading-only information retention | **10%** | Multiple |
| AI personalization retention boost | up to **400%** | Userpilot |
| A/B test program improvement speed | **2.5x faster** | Multiple |
| Checklist completers → paying customer likelihood | **3x** | Multiple |
| "Quick win" onboarding user retention | **+80%** | Multiple |
| Personalized onboarding path completion rate | **+35%** | Multiple |
| Personalized welcome email Day-7 retention | **+33%** | Multiple |
| Microlearning module completion boost | **+45%** | Multiple |
| Without onboarding: support cost increase | **+47%** | Multiple |
| Engaged customers spend per transaction | **+60%** | Multiple |
| Users abandoning if too many onboarding steps | **72%** | Multiple |
| 90-day total churn rate | **71%** | Multiple |

### Time Thresholds

| Metric | Value |
|--------|-------|
| User impression formation time | **15 seconds** |
| Maximum acceptable loading time | **3 seconds** (43% won't tolerate more) |
| Onboarding frustration at 30s | **18%** of users |
| Onboarding frustration at 90s | **28%** of users |
| Maximum onboarding tolerance | **2 minutes** |

---

## 2. Six Design Patterns

### 2.1 Walkthrough (Swipe Slides)

- Most prevalent: **70%** of entertainment apps use it
- "Single screen" (login/register only) is **35%** — trend toward minimal explanation
- **Max 5 slides**; 10-20% drop between slide 1→2
- Best for: value proposition communication for unfamiliar apps
- Risk: forced display reduces user motivation

### 2.2 Coach Marks

- Overlay highlighting specific UI elements
- UI-Patterns calls it a "borderline anti-pattern"
- Unoptimized: **0/8** users read them (Livefront test)
- Optimized (sample data + scrim focus): **6/8** users read them
- **Max 3-4 items** per session
- Best for: complex UIs with non-obvious controls

### 2.3 Progressive Disclosure

- Luke Wroblewski (Google) concept
- Show information at the moment of need, not before
- NN/g: Pull-type >> Push-type effectiveness
- Figma example: text rendering tooltip only when text box is added
- **Max 7 steps** per flow (Miller's Law: 7±2 items in working memory)
- All tasks shown at once: **2%** completion. Phased: **58%** completion
- Best for: feature-rich apps, complex workflows

### 2.4 Tooltips

- Contextual, non-intrusive hints on specific elements
- Well-timed tooltips: **30% retention improvement**
- Interactive product tours: **42% feature adoption improvement**
- Best for: gradual feature discovery, advanced features

### 2.5 Empty States

- **90%** of entertainment apps use this pattern
- Show guidance when no content exists yet
- Notion: checklist + micro-video empty state
- Best for: content-creation apps, social apps, any app requiring user-generated content

### 2.6 Personalization Type

- **26%** of 120 analyzed apps adopt this
- Ask user interests/goals at first launch to optimize content
- Solves cold-start problem
- Retention improvement: **40-82%**
- Best for: content apps, learning apps, productivity tools

### Pattern Selection Matrix

| Scenario | Primary Pattern | Secondary |
|----------|----------------|-----------|
| Value unclear to new users | Walkthrough (2-3 slides) | Empty State |
| Complex UI, many features | Progressive Disclosure | Tooltips |
| Content/social app | Empty State | Personalization |
| Learning/fitness app | Personalization | Gamification + Progressive |
| E-commerce/utility | Minimal (single screen) | Contextual Tooltips |
| Already familiar concept | Skip onboarding entirely | Contextual help only |

---

## 3. Anti-Patterns

### Category A: Information Overload

| Anti-Pattern | Evidence |
|--------------|----------|
| Feature Parade (explain all features at once) | 70% skip tutorials; 30%+ of steps are unnecessary (Wes Bush) |
| Too many intro screens (>5) | 10-20% drop per slide transition |
| Excessive text/copy | Working memory overload (NN/g) |
| Max features to introduce | **3** |

### Category B: Poor Timing

| Anti-Pattern | Evidence |
|--------------|----------|
| Permission requests without context | Approval rate 30-40% → **75%** with benefit explanation |
| Push notification request at launch | Users haven't experienced value yet |
| Rating request before value delivery | Triggers negative reviews |
| Chase Bank: excitement walkthrough for fraud-worried users | Context mismatch |

### Category C: Lack of Freedom

| Anti-Pattern | Evidence |
|--------------|----------|
| Non-skippable tutorials | "Insulting and frustrating" for experienced users |
| One-way flow (no back button) | Users feel trapped |
| No tutorial re-access | Users want to revisit forgotten content |
| involve.me: fullscreen survey without progress indicator | "Trapped" feeling → mass dropout |

### Category D: Absent Value

| Anti-Pattern | Evidence |
|--------------|----------|
| Immediate paywall (VSCO pattern) | 80% leave if value not quickly perceived |
| Registration before value experience | Modern apps: try-before-signup is becoming standard |
| Feature listing instead of benefit demonstration | Boring, not compelling |
| Empty state without guidance | Users feel lost with no direction |

---

## 4. Case Studies

### Duolingo — "Play First, Profile Second"

- 7 personalization questions → complete a real lesson → then account creation
- Account creation: only 3 screens (name, email, password)
- Braingineers brain/eye-tracking: **zero negative emotions** throughout entire flow
- Only negative: "Where did you hear about Duolingo?" (irrelevant to user)
- XP, streaks, badges, leaderboards introduced gradually
- Duo mascot: intentional "baby schema effect" (large eyes, round body)
- Takeaway: Long flows work IF every step delivers value or engagement

### Slack — "Learn by Using"

- Different flows for workspace creators vs. invited members
- 3 personalization questions → workspace name → channel creation → team invite
- Slackbot as tutorial medium: using the platform IS the tutorial
- Evolved through 5 generations since 2014
- Multiple "Aha moments": topic organization, conversation search, tool integrations
- **70% reduction in support tickets** after onboarding improvement

### TikTok — "Content First"

- Browse core feed without registration
- Interest selection for feed personalization
- "The more you watch, the more the feed understands you" — user agency
- Registration only required for interaction (like, comment, post)
- Delayed registration after user is hooked

### Notion — "Use-Case Branching"

- Single question: "How do you plan to use Notion?"
- Branches to Personal / School / Team
- Team: asks role, company size → workspace setup
- Personal/School: immediate customized templates
- "Getting ready" loading message: Idleness Aversion technique

### Expedia — "$12M Form Field"

- Optional "Company" field confused users into entering bank name
- Led to wrong address → credit card verification failures
- **Removing one field = $12M/year revenue increase**

### Grammarly — Workflow Integration

- Personalization quiz about writing goals and preferences
- Interactive demo with immediate feedback on writing
- Seamless integration into existing workflows (browser extension)
- Quick setup followed by guided feature introduction
- Takeaway: Integrate onboarding into user's existing workflow, not a separate experience

### Spotify — Anti-Pattern Example

- Tooltip pointed at wrong UI element
- Product tour only 2 steps with minimal information
- Signup form crowded with non-essential fields
- No onboarding elements for new users

---

## 5. Timeline Framework

### Phase 1: First 10 Seconds (First Impression)

- Users form impression within **15 seconds**
- Loading time **<3 seconds** required (43% won't wait longer)
- Social login reduces friction **60%**
- Delay account creation: show value first (Duolingo, TikTok, DoorDash)
- Completion bias: users who've invested effort are more likely to register

### Phase 2: First 1 Minute (Immediate Value)

- Show **value, not features** — 80% leave if value isn't quickly perceived
- Wise: exchange rates before registration
- Calm: loading screen IS the relaxation experience
- Personalization questions with minimal user effort
- Progress bar for "goal gradient effect"

### Phase 3: First Session (Aha Moment)

- Guide user to core value via shortest path
- Identify app-specific "magic numbers" (Facebook: 10 friends in 7 days)
- Guide first action explicitly (PayPay missions, "Mitene" photo upload)
- Introduce gamification elements gradually
- Small celebrations → **30% session frequency increase**

### Phase 4: First Week (Habit Formation)

- Address the 25% who leave after first session
- Push notification permission: explain benefits early
- Contextual tooltips for gradual feature disclosure
- In-app messaging apps: **3x higher retention**
- Weekly progress reports (Duolingo model)

### Phase 5: Long-Term (Continuous Onboarding)

- Goodpatch: "mid-to-long-term onboarding" concept
- Onboarding = continuous lifecycle process, not one-time event
- New feature context help, undiscovered feature hotspots
- Behavior-based reactivation: re-engage **35%+** of inactive users
- Des Traynor (Intercom): "Onboarding is not a phase, it's the first date itself"

---

## 6. Five Cross-Cutting Principles

1. **Always Skippable** — Every step offers exit/skip; re-accessible from help section
2. **Minimize Steps** — Registration ≤3 steps, Tours ≤5 steps, Contextual flows ≤7 steps; remove steps with >20% drop-off
3. **Show, Don't Tell** — Interactive learning is 2-3x more effective than passive explanation; hands-on = 75% retention vs 10% reading
4. **Measure and Iterate** — Funnel analysis + cohort analysis + A/B testing; formal A/B programs achieve 2.5x faster improvement
5. **Optimize per User Type** — One-size-fits-all fails everyone; use-case branching (Notion), skill-level branching (Twilio)

---

## 7. Push vs Pull Model

### Push (System-Initiated) — Generally Anti-Pattern

- Provides help content not relevant to current user goal
- Interrupts user flow
- Not memorable; does not improve task performance
- Users perceive tasks as MORE difficult after tutorials
- Examples: forced walkthroughs, full-screen modals, feature parades

### Pull (User-Initiated) — Best Practice

- Help triggered when user signals they need it
- Contextual, relevant to current task
- More effective but harder to implement
- Examples: hover tooltips, contextual coach marks, help icons, search-based help
- NN/g research: Pull >> Push for learning effectiveness

---

## 8. Progressive Disclosure

### Core Concept

- Coined by Luke Wroblewski (Google)
- Show only essential information first; reveal more as needed
- Reduces cognitive load; respects Miller's Law (7±2 items)

### Implementation Patterns

| Pattern | Description | When to Use |
|---------|-------------|-------------|
| Staged reveal | Features unlock as user progresses | Gaming, learning apps |
| Contextual tooltips | Appear when user reaches relevant feature | Feature-rich apps |
| Expandable sections | User clicks to see more detail | Settings, preferences |
| Checklist | Guide user through setup tasks | Productivity tools |
| Level-based | Beginner → Intermediate → Advanced features | Professional tools |

### Key Metrics

- All tasks at once: **2%** completion
- Phased approach: **58%** completion
- Activation rate increase: **+25%**
- Max steps per flow: **7** (Miller's Law)
- User-triggered tours: **2-3x higher completion** than auto-launched
- Embedded guidance: **1.5x action rate** vs popup

---

## 9. AI and Emerging Trends

### 2025-2026 Trends

- **AI-driven adaptive flows**: Real-time adjustment based on behavior, role, device, signup source
- **Behavior-based triggers**: Push notifications and UI changes respond to intent
- **Conversational onboarding**: AI chatbots replacing static tutorials; answer 75% of questions instantly
- **Microlearning modules**: Short focused sessions; completion +45%
- **Personalization at scale**: 71% of consumers expect personalized content

### 2027 Outlook

- Multi-agent onboarding assistants guiding users like personal coaches
- Conversational onboarding instead of static tutorials
- AI agents tailoring the app interface itself for each user
- Real-time experiments optimizing flows for maximum retention

---

## Reference Sources (Selected)

### Japanese Sources
- UX MILK — ベストプラクティス (uxmilk.jp/74323)
- Repro Journal — オンボーディング Vol.1-2, 14事例, 16の失敗, 7つのコツ
- Fritz/Mercari — 120アプリ15パターン分類 (note.com/fmkpro1984)
- Goodpatch — 中長期オンボーディング, 初回体験設計, アンチパターン
- Pentagon — 7パターンUI解説
- U-Site / NN/g日本語版 — Push vs Pull
- i3design — チュートリアル未読70%
- Pantograph — 10アプリ×16施策定量調査

### English Sources
- NN/g — Push vs Pull, Contextual Help
- Toptal — Pattern Classification
- DesignerUp — 200+ Flows Study
- Eleken — Expedia $12M Case
- Appcues — Duolingo, Statistics
- UserGuiding — 100+ Statistics, Progressive Onboarding
- Userpilot — Progressive Disclosure, Mobile Strategies
- Chameleon — 550M+ Interactions Benchmark
- DECODE — Time-Based Frustration
- Branch — Deferred Deep Links
