# Learning（Unit 未定・第二の陣。案: 12）

## 目的
設定画面。通知のオン/オフ、学習の状態（フィード重み）、Claude の利用状況、ホーム画面追加への導線、一掃とリセット。
「何が学習されているか」を見せて、ブラックボックス感を減らす。

## 要素
1. ヘッダ: 「戻る」（→ Main）、「設定」
2. 「通知（外部トリガー ・ ホーム画面に追加後に有効）」: トグル 3 つ
   - 朝のダイジェスト（今日の 3 本） 7:30
   - ストリーク消滅 3 時間前に警告
   - 激レア出現を即時通知（激レアの tier が yml に無い間はこのトグルを出さない。jackpot.md の未決 4）
   （DB: ユーザー設定。standalone でなければ無効）
3. 「学習の状態（フィード重み ・ Thompson サンプリング）」: フィードごとに「重み 1.4」「開封 48% ・ 読了 31% ・ いいね 12%」（DB: 集計）
4. 「Claude（要約 ・ レコメンド ・ 週次コメント）」: 「API キー サーバー側（Rails credentials）」「モデル claude-haiku-5-5」「今月の利用 約 ¥86 ・ 要約 212 回」（`claude.summary_model`、claude_api_calls の集計。金額は未決 1）
5. 「ホーム画面に追加 ・ 通知の許可」（→ Install）
6. ボタン「古い未読 64 本を一掃」（Swipe と同じ処理）、「学習をリセット（新鮮さを戻す）」（未決 2）
7. サインアウト（モックに無いが Unit 0 の仮 root にある。ここに置く）

## 遷移
- Main の歯車 → Learning（full page）
- Learning → Install / Main

## 受け入れ条件（Given-When-Then）
- Given 通知トグルを切り替えた When 保存 Then 設定が DB に残り、Job は送信前にこの設定を見る
- Given claude_api_calls が今月 212 件 When Learning を開く Then 「要約 212 回」が出る
- Given 「学習をリセット」When 確認して実行 Then フィード重みが初期値に戻り、読了・いいねの記録は消えない

## 使う設定の鍵
dopamine.yml: `claude.summary_model`, `claude.daily_call_limit`
personas.yml: なし

## 外部 API
なし

## 未決
1. 金額の見積もり方（モデル別単価を yml に持つか、回数だけ出すか）
2. 「学習をリセット」の範囲（フィード重みだけ？ 興味なし履歴も？）
3. ユーザー設定の置き場所（users に列 / settings テーブル / Solid Cache は不可）
4. 第一の陣では「サインアウト」と「ホーム画面に追加（→ Install）」への導線だけの最小版を Unit 5 で置く（main.md / install.md / login.md はこの前提で書いた）。通知トグル・学習状態・Claude 利用状況は第二の陣
