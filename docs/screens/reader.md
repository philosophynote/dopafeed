# Reader（Unit 5c、#43）

## 目的
「無限供給」と「報酬距離」を担う。記事を情報元のサイトへ飛ばさず、アプリの中で本文を読ませ、末尾まで読むとその場で判定と XP の区切りを挟み、下に次の未読を継ぎ足す。
閉じるまで読み続けられる流れにしつつ、区切りごとに XP と今日のゴールを見せて、止まり所（DailyGoal）を見失わせない。
モックには無い画面。nao の決定（2026-11-03「情報元に遷移せずに無限スクロールで記事を読みたい」）で足した。ADR 0010。

## 要素
上から順。出典: 固定 / DB / dopamine.yml の鍵。

1. ヘッダ（上に貼り付く）: 「閉じる」（→ Main）、「DopaFeed」ロゴ（固定）
2. 記事（1 本ずつ白いカード）
   - フィード名・相対時刻・見出し（DB）
   - 出目の帯「出目 掘り出し物 ×3 ・ 完読で +30 XP」（DB: readings.tier。倍率は `xp.tiers`、XP は `xp.base` × multiplier）
   - 本文（DB: articles.content。readability で抜いた HTML を、取得時と同じ許可リストで描く直前に消毒し直す。相対 URL は記事の URL で解決、リンクは別タブ、画像は遅延読み込み）
   - 本文を取れなかった記事（取得前・`content_error` あり）は、本文の代わりに Claude の 3 行要約（DB: summary。無ければ「要約を準備中」）
   - 「元記事で読む」（別タブ。ここから先は判定しない）
3. 末尾の「読み終えた」ボタン。判定が済むと区切りに置き換わる
4. 区切り（判定）: 完読なら橙で「読了！ +N XP」「完読ボーナス +A ・ コンボ ×C +B」「滞在 X ・ n 本連続」（A = `xp.base` × 出目の倍率、N = A × C）、未完なら灰で「未完 ・ +0 XP」「滞在 X。S 秒未満なら XP なし」（S = `read.complete_after_seconds`）。どちらも「今日のゴール n / 5 ・ あと m 本で宝箱」（`daily_goal.articles`）
5. 次の記事（2. と同じ形）。未読が尽きたら「全部読んだ。」と「閉じる」

## 遷移
- Main の「読む」→ Roulette（Turbo Stream のモーダル）→ 止まると Reader（`GET /articles/:id/read`、full page）
- Roulette → Jackpot → 「受け取って読む」→ Reader
- JS が無いとき: 「読む」の POST が直接 Reader へ redirect
- Reader の中: 末尾の form がスクロールで画面に入る（Stimulus `reader`、IntersectionObserver）か「読み終えた」を押す → `POST /readings/:id/advance` → Turbo Stream で form を区切りに replace、次の記事を `#reader` に append。JS が無ければ次の記事の Reader へ redirect
- Reader → Main（「閉じる」）。完読したカードは消える

## 受け入れ条件（Given-When-Then）
- Given 「読む」を押した When 出目が止まる Then 記事の本文がアプリ内で開き、出目の帯が出る（情報元のサイトへは出ない）
- Given 本文に script・イベント属性・javascript: のリンク・iframe がある When Reader を開く Then それらは描かれない
- Given 本文に相対 URL のリンクと画像 When Reader を開く Then 記事の URL で解決され、リンクは別タブで開く
- Given 本文を取れなかった記事 When Reader を開く Then 3 行要約と「元記事で読む」が出る
- Given 記事を開いて complete_after_seconds 以上たった When 末尾までスクロールする Then 区切りに「読了！ +N XP」が出て、下に次の未読（published_at が古い方の 1 本）が継ぎ足される
- Given 記事を開いてすぐ末尾まで流した When 末尾が見える Then 区切りは「未完 ・ +0 XP」で、記事は Main に未読のまま残る（コンボは途切れる）
- Given 最初から末尾が見えている短い記事 When Reader を開く Then 自動では送らず、「読み終えた」を押すまで判定しない
- Given 古い方の未読が無い When 末尾まで読む Then 「全部読んだ。」と「閉じる」が出る
- Given 判定が済んだ記事 When Reader を再読込する Then ボタンの代わりに区切りが出て、二度判定しない
- Given 「読む」を押していない記事 When `/articles/:id/read` を開く Then Main へ戻る

## 使う設定の鍵
dopamine.yml: `read.complete_after_seconds`, `xp.base`, `xp.tiers`, `xp.combo_multiplier_step`, `xp.combo_max_multiplier`, `daily_goal.articles`
personas.yml: なし

## 外部 API
なし（本文は `FetchArticleContentJob`、要約は `Claude::SummarizeArticleJob` が事前に付ける。Reader は読むだけ。画像だけは元サイトから端末が直接読む）

## 未決
1. 滞在の上限（開いたまま放置して翌朝スクロールすると完読になる）。#41 の `read.max_dwell_seconds`
2. 未完で区切られた記事の「読み直す」ボタン（`Reading#reopen!` はある）
3. 2 本目以降のルーレット演出。今は出目の帯だけで、モーダルは Main の「読む」のときだけ
4. Main に戻って再び開いたときのスクロール位置、コードブロックの配色
5. 判定済みの記事を再読込すると区切りだけが出て、次の記事は継ぎ足されない（「閉じる」で Main に戻る）。次へ進む導線を置くか
6. Reader を閉じると、継ぎ足されたが読んでいない次の記事の行（判定前）が残る。Main からもう一度「読む」と開き直す（抽選は使い回す）ので害は無いが、#41 の滞在上限を入れるときに一緒に見る
