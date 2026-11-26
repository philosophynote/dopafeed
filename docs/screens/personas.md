# Personas（#172・#184。コメントの人物の管理）

## 目的
コメント（docs/screens/comments.md）に出る架空の人物を、デプロイなしで足す・出す・外す・書き換える。人物の正は personas の表（ADR 0033）。

## 要素
1. ヘッダ: 「戻る」（→ 設定）、「コメントの人物」
2. 人数の案内（DB: 有効な人数と `comments.personas_shown`）
   - 有効が personas_shown より多い: 「有効 8 人。コメントでは 8 人の中から 3 人が出ます」
   - 有効が 1 人以上で personas_shown 以下: 「有効 2 人。コメントでは 2 人全員が出ます」
   - 有効が 0 人: 「有効な人物がいないので、記事にコメントの欄は出ません」
3. 人物の行 × N（`position` 順）: 色の丸に名前の頭文字、名前、肩書き、ひとこと紹介、リンク「書き換える」、有効 / 無効のスイッチ（`role="switch"`、`aria-checked`、名前入りの読み上げ名）。無効の行は薄く出す
4. 「＋ 人物を足す」（一覧の下）
5. 注記「外した人物のコメントは消えません。戻すと過去の記事でもまた出ます」（固定）
6. 書き換え（`GET /personas/:id/edit`、full page）: 「戻る」（→ Personas）、「人物を書き換える」、注記「保存済みのコメントは作り直しません。書き換えは、これからコメントを作る記事から効きます」（固定）、入力欄「名前」「肩書き」「色」（カラーピッカー。`input type="color"`）「ひとこと紹介」「口調の指示（system_prompt）」（複数行）、「保存」「やめる」
7. 追加（`GET /personas/new`、full page）: 「戻る」（→ Personas）、「人物を足す」、注記「足した人物は、これからコメントを作る記事から出ます。コメントのある記事には出ません」（固定）、書き換えと同じ 5 つの入力欄（色はカラーピッカーに `#6B7280` を入れておく）、「保存」「やめる」。slug は画面に出さず、作るときに `persona-` ＋英小文字 8 字の乱数を振る

## 遷移
- 設定の「コメントの人物」→ Personas（full page、`GET /personas`）
- スイッチ → `PATCH /personas/:id/enablement`（`enabled` だけ）→ Turbo Stream でその行と人数の案内を差し替える。JS が無ければ送信後に Personas へ戻る
- 「戻る」→ 設定
- 「書き換える」→ 書き換え →「保存」で `PATCH /personas/:id` → Personas に戻る。誤りがあれば 422 で同じ画面に赤字。「やめる」「戻る」で Personas に戻り、何も変えない
- 「＋ 人物を足す」→ 追加 →「保存」で `POST /personas` → Personas に戻る。誤りがあれば 422 で同じ画面に赤字、入れた値は残る。「やめる」「戻る」で Personas に戻り、何も足さない

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
- Given 松岡修造の「書き換える」 When ひとこと紹介と口調の指示を変えて保存 Then Personas に戻り、行に新しい紹介が出る。次に作るコメントの指示は新しい口調の指示を使う
- Given 書き換え When 開く Then どの欄にも今の値が入っている
- Given 空白だけの欄や #RRGGBB でない色（ピッカーを通さない送信） When 保存 Then 422 でその欄の下に赤字（「名前を入力してください」「色は #RRGGBB で指定してください」など）、人物は変わらない。前後の空白は落とす。空欄はブラウザが送らせない
- Given 書き換えや追加 When 「色」を押す Then 端末のカラーピッカーが開き、選んだ色で保存される（カラーコードを打たない）
- Given 書き換えの `PATCH` に slug や enabled が混ざる When 送る Then 書き換えの 5 項目以外は変えない
- Given 保存済みのコメントがある記事 When 口調を書き換える Then 保存済みのコメントは変わらない（ADR 0033）
- Given 人物 8 人 When 「＋ 人物を足す」で 5 つを書いて保存 Then Personas に戻り、9 行目（最後）に有効で出て、案内が「有効 9 人。コメントでは 9 人の中から 3 人が出ます」。次に作るコメントから候補に入る
- Given 追加 When 開く Then 色のピッカーは `#6B7280`、ほかの欄は空
- Given 空白だけの欄や #RRGGBB でない色 When 追加で保存 Then 422 でその欄の下に赤字、文字の欄は入れた値が残り、人物は増えない
- Given 追加の `POST` に slug・enabled・position が混ざる When 送る Then 使わない（slug は自動、有効、最後に並ぶ）
- Given 未ログイン When `GET /personas/new` か `POST /personas` Then ログイン画面へ。人物は増えない
- Given 390×844 When 追加を開く Then 横スクロールがなく、タップ領域は 44px 以上、入力欄の文字は 16px 以上

## 使う設定の鍵
dopamine.yml: `comments.personas_shown`
personas の表: 全件（ADR 0033）

## 外部 API
なし

## 未決
1. 並べ替えと削除は持ち越し（外すで足りる間は作らない）
2. system_prompt の長さの上限（数字なので yml に置く。要るなら PR で提案）
