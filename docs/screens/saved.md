# Saved（Unit 20、#95。20a = 記録と一覧、20b = 右スワイプ）

## 目的
「あとで読む」の取り置き。Main で今は読まない記事を右へ引いて退かせ、ここから読む。読み終えても残し、読み返す置き場も兼ねる（ADR 0018）。保存記事との類似（Similar）の起点にもなる（第二の陣）。

## 要素
1. 「保存 (5)」（DB: 保存数 = `Article.bookmarked`）
2. 保存記事の一覧（保存した新しい順）: 見出し、フィード名 ・ 相対時刻（published_at）、右のサムネイル。Main の行と同じ見た目。読み終えた記事には「読んだ」の印
3. 空状態「まだ保存した記事はありません。」「フィードで記事を右へ引くと、ここに取り置けます。」
4. タブバー（保存が選択）

モックにある「保存した記事に似ている未読 3 件」カード（→ Similar）と「似た未読 1」バッジは出さない（Similar の Unit で）。

## 遷移
- タブバー「保存」→ Saved（full page、`GET /saved`）
- Main の行を右へ引いて離す → 行の中の隠れた「保存」の form を送る → `POST /articles/:id/bookmark` → Turbo Stream で行を「「見出し」を保存した ・ 元に戻す」の帯に替え、未読数を合わせる（スワイプは 20b）
- 「元に戻す」→ `DELETE /articles/:id/bookmark` → 帯が行に戻る（保存した後に読み終えていたら帯だけ消える）。帯は Main を開き直すと出ない
- Saved の未読の行 → 「読む」（Roulette → Reader。Main と同じ POST、XP も普段どおり）
- Saved の読んだ行 → Reader（抽選し直さず XP も付かない）

## 受け入れ条件（Given-When-Then）
- Given 保存 2 本・いいねだけ 1 本・未保存 1 本 When Saved を開く Then 「保存 (2)」で 2 本が保存日時の新しい順
- Given 保存が 0 本 When Saved を開く Then 空状態の文言
- Given Main の未読の行 When 保存する Then 行が「元に戻す」の帯に替わり、未読数が 1 減り、`articles.bookmarked_at` が入る。XP・読了・今日のゴールは変わらない
- Given 保存した記事 When Main を開き直す Then 行にも未読数にも出ず、Reader の「次の 1 本」にも継ぎ足されない
- Given 保存した帯 When 「元に戻す」を押す Then 行が戻り、未読数が 1 増え、`bookmarked_at` が nil になる
- Given Saved の未読の行 When 押す Then ルーレットが回り Reader へ進む
- Given Saved の読んだ行 When 押す Then 抽選せずに Reader が開く
- Given 保存を解除 When 一覧 Then Turbo Stream でその行が消える（Saved の行を左へ引く。20b）

## 使う設定の鍵
dopamine.yml: `swipe.dismiss_threshold_ratio`、`swipe.submit_timeout_seconds`（右スワイプも左と同じ値。20b）
personas.yml: なし

## 外部 API
なし

## 未決
1. いいねとブックマークの違い（学習への寄与が違う？ 表示は同じ？）。Unit 2 で列を決めるときに要る
   → **決定（Unit 2、ADR 0006）**: 別の列 `articles.liked_at` / `articles.bookmarked_at`。表示は `Article.saved` で束ねる。学習への寄与の違いは第二の陣
   → **改め（Unit 20、ADR 0018）**: Saved の一覧は保存（`bookmarked_at`）だけ。いいねは押す手段が無いので一覧に入れない
2. 保存記事を開いたときに読了判定・XP を出すか（モックは「読み返す +5 XP」が Swipe にある）
   → **決定（Unit 20、ADR 0018）**: 未読なら普段の「読む」と同じ（抽選・XP あり）。読み終えた記事は XP 無しで Reader を開くだけ。「読み返す +5 XP」は鍵が無いので出さない（持ち越し）
3. ひとこと要約（モックの ReadDone。今は Reader の区切りに畳んだので、置き場は未決）をここで見返す（ReadDone の注記「あとで保存タブから見返せます」）
4. Reader の「閉じる」は Main に戻る。Saved から開いたときに Saved へ戻すか（持ち越し）
5. Reader の中から保存する導線（持ち越し）
