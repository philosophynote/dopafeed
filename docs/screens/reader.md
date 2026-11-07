# Reader（Unit 5c #43、5d #50、要約 #85）

## 目的
「無限供給」と「報酬距離」を担う。記事のカードを 1 枚ずつ並べ、「記事を開く」で元サイトを見た目のままアプリ内ブラウザ（シート）に開く。閉じて戻るとその場で判定と XP の区切りを挟み、下に次の未読のカードを継ぎ足す。
閉じるまで読み続けられる流れにしつつ、区切りごとに XP と今日のゴールを見せて、止まり所（DailyGoal）を見失わせない。
モックには無い画面。nao の決定で足した（2026-11-03「情報元に遷移せずに無限スクロールで記事を読みたい」ADR 0010、2026-11-04「読みづらい。アプリ内ブラウザのように読みたい」ADR 0011）。

## 要素
上から順。出典: 固定 / DB / dopamine.yml の鍵。

1. ヘッダ（上に貼り付く）: 「閉じる」（→ Main）、「DopaFeed」ロゴ（固定）
2. 記事のカード（1 本ずつ白いカード）
   - OGP 画像（DB: image_url。あればカードの上端に 1.91:1 で全幅、無い・読めなければ出さない。#87、ADR 0016）
   - フィード名・相対時刻・見出し（DB）
   - 出目の帯「出目 掘り出し物 ×3 ・ 完読で +30 XP」（DB: readings.tier。倍率は `xp.tiers`、XP は `xp.base` × multiplier）
   - 「Claude の 3 行要約」（DB: summary）。本文は描かない。要約は「読む」を押してから作る（ADR 0015）ので、出来るまでは「要約を作成中…」、出来るとその欄だけ差し替わる（Turbo Stream）。失敗なら「要約できませんでした。記事を開いて読めます」、その日の上限（`claude.daily_call_limit`）なら「今日の要約の上限に達しました。記事を開いて読めます」
   - 「記事を開く」（橙の大きなボタン。元サイトを別窓で開く。iPhone のホーム画面アプリではシート）
3. 「読み終えた」ボタン。「記事を開く」を押すまで隠す（JS が無いときは最初から見える）。判定が済むと区切りに置き換わる
4. 区切り（判定）: 完読なら橙で「読了！ +N XP」「完読ボーナス +A ・ コンボ ×C +B」「滞在 X ・ n 本連続」（A = `xp.base` × 出目の倍率、N = A × C）、未完なら灰で「未完 ・ +0 XP」「滞在 X。S 秒未満なら XP なし」（S = `read.complete_after_seconds`）。どちらも「今日のゴール n / 5 ・ あと m 本で宝箱」（`daily_goal.articles`）。完読数がちょうど 5 本目の区切りには金色の「宝箱を開く」（→ DailyGoal。Unit 7 #55）
5. 次の記事のカード（2. と同じ形）。未読が尽きたら「全部読んだ。」と「閉じる」

## 遷移
- Main の「読む」→ Roulette（Turbo Stream のモーダル）→ 止まると Reader（`GET /articles/:id/read`、full page）
- Roulette → Jackpot → 「受け取って読む」→ Reader
- JS が無いとき: 「読む」の POST が直接 Reader へ redirect
- Reader の中: 「記事を開く」→ 元サイトが別窓（シート）で開き、Stimulus `sheet` が `POST /readings/:id/start` で開いた時刻を記録 → シートを閉じて戻る（`visibilitychange` で隠れた後に、見えるか `focus` が戻る。押した瞬間の blur → focus では送らない）か「読み終えた」を押す → `POST /readings/:id/advance` → Turbo Stream で「読み終えた」を区切りに replace、次のカードを `#reader` に append。JS が無ければ次の記事の Reader へ redirect
- Reader → Main（「閉じる」）。完読したカードは消える

## 受け入れ条件（Given-When-Then）
- Given 「読む」を押した When 出目が止まる Then Reader に記事のカード（見出し・出目の帯・3 行要約・「記事を開く」）が出る。本文は描かれない
- Given Reader のカード When 「記事を開く」を押す Then 元サイトが別窓（iPhone のホーム画面アプリではシート）で開き、滞在はこの時刻から数える
- Given 記事を開いて complete_after_seconds 以上たった When Reader に戻る Then 区切りに「読了！ +N XP」が出て、下に次の未読（published_at が古い方の 1 本）のカードが継ぎ足される
- Given 記事を開いてすぐ戻った When Reader に戻る Then 区切りは「未完 ・ +0 XP」で、記事は Main に未読のまま残る（コンボは途切れる）
- Given 戻りの合図が来ない端末 When 記事を開いた後に「読み終えた」を押す Then 同じ判定になる
- Given 「記事を開く」を押していない When Reader を見る Then 「読み終えた」は出ていない
- Given 古い方の未読が無い When 記事を開いて戻る Then 「全部読んだ。」と「閉じる」が出る
- Given 判定が済んだ記事 When Reader を再読込する Then ボタンの代わりに区切りが出て、二度判定しない
- Given 判定が済んだ記事 When もう一度「記事を開く」を押す Then 滞在は書き換わらない
- Given 「読む」を押していない記事 When `/articles/:id/read` を開く Then Main へ戻る
- Given 記事に OGP 画像がある When Reader のカードを見る Then カードの上端に横長の画像が出る
- Given 要約の無い記事 When 「読む」を押す Then 要約の Job が積まれ、カードに「要約を作成中…」が出る。Job が書き終えると、再読込せずに要約が出る
- Given 要約の無い次の記事 When 読み終えて次のカードが継ぎ足される Then その記事の要約の Job も積まれる
- Given 要約済みの記事 When もう一度「読む」を押す Then Job は積まれず、保存済みの要約が出る（払うのは 1 回）
- Given 要約に失敗した記事・その日の上限 When カードを見る Then その旨が出て、「記事を開く」はそのまま使える
- Given 本文取得がまだの記事 When 「読む」を押す Then 「作成中」のまま待ち、本文取得を試し終えたら要約の Job が積まれる
- Given 「読む」を押していない記事 When 新しい記事が取り込まれる Then 要約は作られない（API を呼ばない）

## 使う設定の鍵
dopamine.yml: `read.complete_after_seconds`, `claude.daily_call_limit`, `xp.base`, `xp.tiers`, `xp.combo_multiplier_step`, `xp.combo_max_multiplier`, `daily_goal.articles`
personas.yml: なし

## 外部 API
Claude（要約。「読む」と継ぎ足しのときに `Claude::SummarizeArticleJob` を積み、画面は待つだけ。ADR 0015）。元サイトは端末のブラウザが直接開く

## 未決
1. 滞在の上限（シートを開いたまま放置して翌朝戻ると完読になる）。#41 の `read.max_dwell_seconds`
2. iPhone 実機（2026-11-05、nao）: ホーム画面アプリ（「Webアプリとして開く」をオン）では「記事を開く」がシートで開き、閉じると `visibilitychange` の visible と `focus` が来ることは確かめた。押した瞬間の blur → focus で早く判定する不具合を直し、直した後の通し（シートで 30 秒読んで閉じる → 読了 +10 XP、滞在 30 秒、次のカード）も 2026-11-05 に確かめた。Safari のタブで開くと記事は別タブになる
3. 未完で区切られた記事の「読み直す」ボタン（`Reading#reopen!` はある）
4. 2 本目以降のルーレット演出。今は出目の帯だけで、モーダルは Main の「読む」のときだけ
5. 判定済みの記事を再読込すると区切りだけが出て、次の記事は継ぎ足されない（「閉じる」で Main に戻る）。次へ進む導線を置くか
6. 判定前のカードで「記事を開く」を押し直すと、滞在はその時刻から測り直しになる（戻りの合図が来ない端末で、読み終えた後に開き直すと未完になり得る）。手押しの「読み終えた」を先に押してもらうか、測り直さない形にするか
7. Reader を閉じると、継ぎ足されたが開いていない次の記事の行（判定前）が残る。Main からもう一度「読む」と開き直す（抽選は使い回す）ので害は無いが、#41 の滞在上限を入れるときに一緒に見る
