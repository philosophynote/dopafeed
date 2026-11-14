# Saved（Unit 20、#95。20a = 記録と一覧、20b = 右スワイプと保存を外すスワイプ）

## 目的
「あとで読む」の取り置き。Main で今は読まない記事を右へ引いて退かせ、ここから読む。読み終えても残し、読み返す置き場も兼ねる（ADR 0018）。保存記事との類似（Similar）の起点にもなる（第二の陣）。

## 要素
1. 「保存 (5)」（DB: 保存数 = `Article.bookmarked`）
2. 保存記事の一覧（保存した新しい順）: 見出し、フィード名 ・ 相対時刻（published_at）、右のサムネイル。Main の行と同じ見た目。読み終えた記事には「読んだ」の印
3. 空状態「まだ保存した記事はありません。」「フィードで記事を右へ引くと、ここに取り置けます。」
4. タブバー（保存が選択）
5. 効果音（#100、ADR 0022）: 行のタップと、スワイプが閾値を越えた瞬間に Main と同じ音。ルーレットの音は roulette.md

モックにある「保存した記事に似ている未読 3 件」カード（→ Similar）と「似た未読 1」バッジは出さない（Similar の Unit で）。

## 遷移
- タブバー「保存」→ Saved（full page、`GET /saved`）
- Main の行を右へ引いて離す → 行の中の隠れた「保存」の form を送る → `POST /articles/:id/bookmark` → Turbo Stream で行を隠し、画面下（タブバーの上）に暗いトースト「1 件を保存しました　元に戻す」を出し、未読数を合わせる。引いた幅だけ左から丸型の背景とブックマークのアイコン「保存」が伸び、閾値の手前は灰、越えたら橙
- トーストの「元に戻す」→ `DELETE /articles/:id/bookmark` → 行が元の位置に戻りトーストが消える（保存した後に読み終えていたら行は戻らない）。トーストの消え方は swipe.md と同じ（#112）
- Saved の未読の行 → 「読む」（Roulette → Reader。Main と同じ POST、カードも普段どおり）。読み終えても保存は残り、Reader の「次の 1 本」は Main の未読（その記事より古い方）から継ぎ足す
- Saved の読んだ行 → Reader（抽選し直さずカードも増えない）
- Saved の行を左へ引いて離す → 隠れた「保存を外す」の form を送る → `DELETE /articles/:id/bookmark?from=saved` → 行を隠し、画面下に「1 件の保存を外しました　元に戻す」のトーストを出し、保存数と未読数を合わせる。背景は右から伸び、斜線のブックマーク「外す」、越えたら濃い灰（赤にしないのは消すのではなく Main に戻すだけだから）。右へは動かない
- トーストの「元に戻す」→ `POST /articles/:id/bookmark?from=saved` → 行が元の位置に戻りトーストが消える（保存した時刻は今になるので、開き直すと一覧の先頭に来る）

## 受け入れ条件（Given-When-Then）
- Given 保存 2 本・いいねだけ 1 本・未保存 1 本 When Saved を開く Then 「保存 (2)」で 2 本が保存日時の新しい順
- Given 保存が 0 本 When Saved を開く Then 空状態の文言
- Given Main の未読の行 When 保存する Then 行が消えて画面下に「元に戻す」のトーストが出て、未読数が 1 減り、`articles.bookmarked_at` が入る。カード・読了・今日のゴールは変わらない
- Given 保存した記事 When Main を開き直す Then 行にも未読数にも出ず、Reader の「次の 1 本」にも継ぎ足されない
- Given 保存した直後のトースト When 「元に戻す」を押す Then 行が元の位置に戻り、未読数が 1 増え、`bookmarked_at` が nil になる
- Given Saved の未読の行 When 押す Then ルーレットが回り Reader へ進む
- Given Saved の読んだ行 When 押す Then 抽選せずに Reader が開く
- Given Main の行 When 右へ閾値を越えて引いて離す Then 行が消えて保存される。閾値の手前で離すと戻り、保存しない
- Given 保存を解除（Saved の行を左へ引く） When 一覧 Then Turbo Stream でその行が消えて画面下に「1 件の保存を外しました　元に戻す」のトーストが出て、保存数が 1 減り、Main の未読数が 1 増える
- Given Saved の読んだ行 When 引いて戻した直後の click Then Reader へ移らない

## 使う設定の鍵
dopamine.yml: `swipe.dismiss_threshold_ratio`、`swipe.flick_velocity`、`swipe.flick_window_ms`、`swipe.flick_min_px`、`swipe.submit_timeout_seconds`（右スワイプと保存を外すのも左の削除と同じ値）、`toast.visible_seconds`（取り消しのトースト。#112）
personas.yml: なし

## 外部 API
なし

## 未決
1. いいねとブックマークの違い（学習への寄与が違う？ 表示は同じ？）。Unit 2 で列を決めるときに要る
   → **決定（Unit 2、ADR 0006）**: 別の列 `articles.liked_at` / `articles.bookmarked_at`。表示は `Article.saved` で束ねる。学習への寄与の違いは第二の陣
   → **改め（Unit 20、ADR 0018）**: Saved の一覧は保存（`bookmarked_at`）だけ。いいねは押す手段が無いので一覧に入れない
2. 保存記事を開いたときに読了判定・XP を出すか（モックは「読み返す +5 XP」が Swipe にある）
   → **決定（Unit 20、ADR 0018）**: 未読なら普段の「読む」と同じ（抽選・XP あり）。読み終えた記事は XP 無しで Reader を開くだけ。「読み返す +5 XP」は鍵が無いので出さない（持ち越し）
   → **改め（Unit 23、#106、ADR 0020）**: XP はカードに。未読なら抽選してカード、読み終えた記事は Reader を開くだけ
3. ひとこと要約（モックの ReadDone。今は Reader の区切りに畳んだので、置き場は未決）をここで見返す（ReadDone の注記「あとで保存タブから見返せます」）
4. Reader の「閉じる」は Main に戻る。Saved から開いたときに Saved へ戻すか（持ち越し）
5. Reader の中から保存する導線（持ち越し）
6. 保存と保存を外すはスワイプだけで、キーボードと VoiceOver からはできない（削除と同じ。要るなら VoiceOver のカスタムアクションを別に足す）
