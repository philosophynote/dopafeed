# Weekly（Unit 未定・第二の陣。案: 13）

## 目的
社会的報酬の「過去の自分と比べる」版。週の読了数・時間・XP・フィード別内訳と Claude のひとことを 1 枚のカードにして画像で共有できる。

## 要素
1. ヘッダ: 「レポート」、ボタン「画像で共有」（未決 1）
2. セグメント「今週 / Garden」（Garden は段 4。第一の陣の外）
3. カード: 「今週のレポート ・ 10/3 – 10/9」「7 日連続」、「32 本 読了」「先週比 +40%（23 本）」、曜日別の棒 7 本（金〜木。週の始まりは未決 2）
4. 「読書時間 2h 41m」「獲得 XP +1,240」「ひとこと要約 11 本」（DB: 集計）
5. フィード別「Zenn 14 / Publickey 9 / はてブ 6 / その他 3」（DB）
6. 「Claude のひとこと」: 「今週は Swift の並行処理まわりを 6 本連続で…来週は『設計』タグを 2 本混ぜると…」（DB: 週次 Job の生成結果）
7. フッター「DopaFeed ・ 過去の自分と比べる週次カード」、タブバー（レポートが選択）

## 遷移
- タブバー「レポート」→ Weekly（full page）
- 「画像で共有」→ 画像生成（未決 1）→ iOS の共有シート

## 受け入れ条件（Given-When-Then）
- Given 今週 32 本、先週 23 本 When Weekly を開く Then 「32 本」「先週比 +39%」（小数点以下は四捨五入。モックの +40% は丸めの違い）
- Given 週次 Job が走った When Weekly を開く Then Claude のひとことが出て、同じ週に再生成しない
- Given 今週の読了 0 When Weekly を開く Then 0 本で画面が崩れない（棒グラフは空）

## 使う設定の鍵
dopamine.yml: `claude.curation_model`（週次コメントのモデル。未決 3）
personas.yml: なし

## 外部 API
あり。Claude（`Claude::WeeklyCommentJob`、VCR: `claude/weekly_comment.yml`）。週 1 回の定期ジョブ

## 未決
1. 画像生成の方法（サーバーで HTML → PNG は重い。Canvas で描くか、html-to-image 系は外部 JS なので不可。OG 画像的にサーバー側で SVG → PNG？ ADR が要る）
2. 週の始まり（モックは金曜始まり 10/3–10/9）
3. 週次コメントのモデルと、ひとことの文字数上限
