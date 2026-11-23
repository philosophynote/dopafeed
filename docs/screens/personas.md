# Personas（#172。コメントの人物の管理）

## 目的
コメント（docs/screens/comments.md）に出る架空の人物を、デプロイなしで出す・外す。人物の正は personas の表（ADR 0033）。

## 要素
1. ヘッダ: 「戻る」（→ 設定）、「コメントの人物」
2. 人数の案内（DB: 有効な人数と `comments.personas_shown`）
   - 有効が personas_shown より多い: 「有効 8 人。コメントでは 8 人の中から 3 人が出ます」
   - 有効が 1 人以上で personas_shown 以下: 「有効 2 人。コメントでは 2 人全員が出ます」
   - 有効が 0 人: 「有効な人物がいないので、記事にコメントの欄は出ません」
3. 人物の行 × N（`position` 順）: 色の丸に名前の頭文字、名前、肩書き、ひとこと紹介、有効 / 無効のスイッチ（`role="switch"`、`aria-checked`、名前入りの読み上げ名）。無効の行は薄く出す
4. 注記「外した人物のコメントは消えません。戻すと過去の記事でもまた出ます」（固定）

## 遷移
- 設定の「コメントの人物」→ Personas（full page、`GET /personas`）
- スイッチ → `PATCH /personas/:id/enablement`（`enabled` だけ）→ Turbo Stream でその行と人数の案内を差し替える。JS が無ければ送信後に Personas へ戻る
- 「戻る」→ 設定

## 受け入れ条件（Given-When-Then）
- Given 人物 8 人が有効 When 設定の「コメントの人物」 Then 8 行が並び順で出て、どのスイッチもオン、「有効 8 人。コメントでは 8 人の中から 3 人が出ます」
- Given 有効な織田信長 When スイッチを押す Then 再読込せずにその行のスイッチがオフになって薄くなり、案内が「有効 7 人」。フォーカスは押したスイッチに残る（Space で押しても同じ）。再読込しても残る
- Given 無効にした人 When もう一度押す Then オンに戻る
- Given 前の送信が終わる前 When 別の行のスイッチも押す Then どちらも外れ、表示と DB が食い違わない
- Given 全員を無効 When 一覧を見る Then 「有効な人物がいないので、記事にコメントの欄は出ません」、記事を広げてもコメントの欄は出ない
- Given 有効が 2 人（personas_shown 3） When 一覧を見る Then 「有効 2 人。コメントでは 2 人全員が出ます」
- Given 未ログイン When `GET /personas` か `PATCH /personas/:id/enablement` Then ログイン画面へ。人物は変わらない
- Given スイッチの `PATCH` に名前などが混ざる When 送る Then `enabled` 以外は変えない
- Given 390×844 When 開く Then 横スクロールがなく、タップ領域は 44px 以上

## 使う設定の鍵
dopamine.yml: `comments.personas_shown`
personas の表: 全件（ADR 0033）

## 外部 API
なし

## 未決
1. 人物の書き換え（名前・肩書き・色・ひとこと紹介・system_prompt）は #172 の次の段で足す
2. 人物の追加・並べ替えは持ち越し
