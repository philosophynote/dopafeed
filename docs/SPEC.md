# Dopafeed SPEC（製品の芯）

> Unit 1 で画面モック（https://claude.ai/artifact/UF3JSQDBeEUGhESB3JvWyx）の設計メモから写し取る。
> ここは「なぜ」と「全体」。個々の画面は docs/screens/ に。

## 目的
一人用。SNS の中毒性（可変報酬・社会的報酬・FOMO）を技術記事読みに向け、読む習慣を作る。

## 7 つの報酬要素 × 画面（Unit 1 で埋める）
| 要素 | 画面 | 仕組み |
|---|---|---|
| 可変報酬 | Roulette / Jackpot | |
| 報酬距離 | DailyGoal | |
| 無限供給 | Main / Swipe | |
| 止まり所 | ReadDone | |
| 社会的報酬 | Comments / Weekly | |
| FOMO | ForYou / Push | |
| 外部トリガー | Install（通知・バッジ） | |

## iOS PWA の制約と代替策（Unit 1 で埋める）
- 振動不可 → 
- ウィジェット不可 → 
- Web Push の条件 → 

## 分担
iPhone で読む。Mac で検証・執筆する。

## 画面の段
1. コアループ: Main, Swipe, Roulette, Jackpot, ReadDone, DailyGoal, Comments
2. 個人最適化: ForYou, Learning, Weekly, Install, Similar
3. 管理: AddFeed, Saved, Feeds, Login
4. アウトプット（第一の陣の対象外）: NetaBox, Quest, Garden, Gacha, Hypothesis, Suggest
