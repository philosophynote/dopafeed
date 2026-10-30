# Dopafeed SPEC（製品の芯）

> 画面モック（https://claude.ai/artifact/UF3JSQDBeEUGhESB3JvWyx）の設計メモから写し取り済み（Unit 1）。
> ここは「なぜ」と「全体」。個々の画面は docs/screens/（索引: docs/screens/README.md）に。

## 目的
一人用。SNS の中毒性（可変報酬・社会的報酬・FOMO）を技術記事読みに向け、読む習慣を作る。

## 7 つの報酬要素 × 画面
鍵の無い数字（7:30、21:00、1 日 2 件、3 時間前、3 本、0〜3 枚）はモック由来の提案で、config/dopamine.yml に入るまで確定ではない（docs/plans/unit-1.md「yml との差」）。

| 要素 | 画面 | 仕組み |
|---|---|---|
| 可変報酬 | Roulette / Jackpot | 「読む」1 タップで XP の出目が回る（0.5 秒）。レア 3 段階（common / rare / jackpot、確率と倍率は dopamine.yml `xp.tiers`）。ジャックポットは閉じられない全画面演出。段 4 では知識ガチャ（0〜3 枚）、コメントが付くか分からない、も同じ要素 |
| 報酬距離 | ReadDone（Main のコンボ表示） | 読了の直後に XP の内訳（完読ボーナス × コンボ）と効果音・CSS アニメーション。コンボは連続読了で +0.1 倍ずつ、上限 2.0（`xp.combo_*`）。タップから結果までを短く保つ |
| 無限供給 | Main / Swipe / ReadDone の「次の 1 本」 | 新着 + 発掘 1 本として見せ、読了画面の下に次の 1 本を置く（「閉じる」が次の「開く」）。古い未読は一掃して「もう一度読む」として再提示 |
| 止まり所 | DailyGoal | 1 日 5 本（`daily_goal.articles`）で宝箱が開き、満足して閉じられる。翌日 reset_hour（午前 4 時）でリセット。SNS と逆を行く |
| 社会的報酬 | Comments / Weekly | 著名人を模した架空 AI 8 人から 3 人（`comments.personas_shown`）がランダムにコメント（personas.yml）。はてブ数。週次レポートで過去の自分と比べ、画像で共有 |
| FOMO | ForYou / Push（Install） / Main の今日限定 | 今日限定カード（残り時間つき）、ストリーク消滅 3 時間前の警告、未読一掃。Claude が朝 7:30 に理由付きで 3 本選ぶ |
| 外部トリガー | Install（通知・バッジ） | Web Push の朝ダイジェスト（7:30）とストリーク警告（21:00）、1 日最大 2 件。アイコンのバッジに未読数（Badging API）。ホーム画面に追加した後だけ有効 |
| 個人最適化（8 つ目） | ForYou / Learning / Similar | フィード重みを Thompson サンプリングで学習（開封・読了・いいね・興味なし。ADR 未）。Claude には未読のタイトルと興味プロファイルだけを渡す。保存記事との内容類似は別軸（sqlite-vec か TF-IDF。ADR 未） |

## iOS PWA の制約と代替策
- 振動（ハプティクス）不可 → 効果音と CSS アニメーションを同じタイミングで鳴らす
- ホーム画面ウィジェット不可 → アイコンのバッジ（Badging API）に未読数、Web Push で朝のダイジェスト（web-push gem は Unit 0 で導入済み。鍵の管理と送信 Job は Unit 10 で ADR）
- Web Push とバッジは「ホーム画面に追加」した後だけ有効（iOS 16.4+）→ Install 画面で手順 3 段を出し、standalone で開いたときだけ「通知を許可する」を有効にする。Safari のタブのままでは出さない
- バッジは OS が永続化しない（再起動で消える）→ service worker の push / activate で setAppBadge を再実行する
- 記事は PWA 内のブラウザシートで開く → 読了判定は「記事を開いた時刻」と「アプリに戻ってきた時刻」の差（`read.complete_after_seconds`）。本文をアプリ内に描画しない
- バックグラウンド取得は iOS の制約を受けない → Solid Queue の定期ジョブがサーバーで RSS を取り、Claude で要約する
- Claude の API キーは Rails credentials に置き、画面には出さない。呼び出しは必ず Job 経由（AGENTS.md）

## 分担
iPhone で読む。Mac で検証・執筆する。
- iPhone: 読む → 発見 → Seed 化、1 文で答えるクエスト、予想を書く
- Mac: 検証（Claude Code）、結果を書く、執筆（Obsidian）、Polish、Zenn へ公開
- 受け渡しは GitHub 上の article-vault。Rails が GitHub API でネタを Markdown としてコミットし、Mac は git pull で受け取る（段 4）
- 読む側（興奮）と書く側（静か）でトーンを分ける。書く側にルーレットは出さない

## 画面の段
1. コアループ: Main, Swipe, Roulette, Jackpot, ReadDone, DailyGoal, Comments
2. 個人最適化: ForYou, Learning, Weekly, Install, Similar
3. 管理: AddFeed, Saved, Feeds, Login
4. アウトプット（第一の陣の対象外）: NetaBox, Quest, Garden, Gacha, Hypothesis, Suggest
