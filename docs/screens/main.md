# Main（Unit 5）

## 目的
無限供給と FOMO を担う入口。開くたびに「読むもの」と「今日の進み」が一画面に出て、「読む」1 タップでルーレット（Roulette）に繋がる。
未読の山ではなく「新着 + 発掘 1 本」として見せ、罪悪感ではなく期待で開かせる。

## 要素
上から順。出典: 固定 / DB / dopamine.yml の鍵。

1. ヘッダ: 「DopaFeed」ロゴ（固定）、設定ボタン（→ Learning）、フィード追加ボタン（→ AddFeed）
2. セグメント「すべて / あなた向け」（固定。あなた向け → ForYou。第一の陣では「あなた向け」は無効か非表示。未決 1）
3. ステータスカード（白）
   - 「N 日連続」炎アイコン（DB: ストリーク）
   - 「未読 N 件 ・ 読了 N」（DB: 未読数、読了累計）
   - 「Lv.N」と XP バー「238 / 400 XP」（DB: 累計 XP。レベル閾値は未決 2）
   - 「今日のゴール n / 5」とドット 5 個（DB: 今日の読了数、dopamine.yml `daily_goal.articles`）。タップ → DailyGoal
   - コンボバッジ「コンボ ×1.5 ・ あと 2:14」（DB: 直近の読了時刻。倍率は `xp.combo_multiplier_step`、上限 `xp.combo_max_multiplier`、有効時間は未決 3）
4. 新着バナー（白ピル）「新着 12 件 ＋ 過去の神記事を 1 本発掘」（DB: 前回開いた後の新着数。発掘は未決 4）
5. 記事カード（新しい順。種類 3 つ）
   - 掘り出し物カード: 枠がグラデーション。フィード名、はてブ数「128 users」（DB、未決 5）、相対時刻、ラベル「掘り出し物 ・ XP 1.5〜3 倍」（未決 11: カードの属性か、ルーレットの出目か）、見出し、要約 2 行（DB: summary）、「約 6 分 ・ 完読で +40 XP」（推定読了時間は未決 6、XP は `xp.base` × 倍率）、いいね / 保存 / コメント（→ Comments）、「読む」ボタン（→ Roulette）
   - 今日限定カード: 赤枠。ラベル「今日限定 ・ 残り 4:12:08 ・ 消える前に読むと +30 XP」（未決 7）、アイキャッチ画像（DB: 未決 8）、「読む ＋10〜30 XP」
   - 通常カード: フィード名、相対時刻、「保存した『…』に 61% 似ている」（→ Similar。第一の陣では出さない）、見出し
6. タブバー: フィード（未読バッジ 48、aria-current）/ 保存 / レポート / 購読（固定。第一の陣ではフィード以外は無効。未決 9）

## 遷移
- Login → Main（認証後の after_authentication_url）
- Main → Roulette（「読む」。Turbo Frame でモーダルを重ねる。カード自体は残す）
- Main → DailyGoal（ゴール表示をタップ、または 5 本目の読了後に自動）
- Main → Comments / Similar / ForYou / Learning / AddFeed / Saved / Weekly / Feeds（full page。第一の陣では無い）
- 第一の陣の導線: 設定ボタンは Learning の最小版（サインアウト + Install への導線だけ。Unit 5 で置く）へ。フィード追加の「+」は出さない（5 フィードは seed と Unit 3 で入る。AddFeed は第二の陣）
- 読了後に ReadDone → Main に戻ると、読んだカードは一覧から消え、ステータスカードが Turbo Stream で更新される

## 受け入れ条件（Given-When-Then）
- Given 未読記事が 3 本ある When Main を開く Then 3 本が published_at の新しい順に並ぶ
- Given 記事に summary がある When カードを見る Then 要約が 2 行で切れて表示される
- Given 記事に summary が無い（要約ジョブ未完）When カードを見る Then 要約欄が空で見出しだけ出る
- Given 今日 3 本読了している When Main を開く Then 「今日のゴール 3 / 5」とドットが 3 個塗られる（5 は dopamine.yml）
- Given 今日 0 本 When Main を開く Then 「今日のゴール 0 / 5」で全ドットが灰色
- Given 昨日まで 3 日連続で 1 本以上完読している When 今日 Main を開く Then 「3日連続」が出る（ストリークの定義は daily_goal.md の未決 6）
- Given 既読の記事が 1 本ある When Main を開く Then その記事はカードに出ない
- Given 未読が 48 本 When Main を開く Then タブバーのフィードに「48」バッジが出る
- Given 未読が 0 本 When Main を開く Then バッジが出ず、一覧に「全部読んだ」の空状態が出る（文言は未決 10）
- Given カードの「読む」をタップ When Roulette が出る Then 背景の一覧はそのまま残り、Roulette 終了後に記事が開く
- Given 390 幅 When Main を開く Then 横スクロールが出ず、タップ領域は 44px 以上
- Given 未ログイン When /（root）を開く Then /session/new にリダイレクト

## 使う設定の鍵
dopamine.yml: `daily_goal.articles`, `xp.base`, `xp.tiers`, `xp.combo_multiplier_step`, `xp.combo_max_multiplier`
personas.yml: なし

## 外部 API
なし（記事とフィードの取得は Unit 3 の Job、要約は Unit 4 の Job。画面は DB を読むだけ）

## 未決
1. 「あなた向け」セグメントを第一の陣でどう出すか（非表示 / 無効 / 「すべて」と同じ）
2. レベルの閾値（Lv.4 = 400 XP？）。dopamine.yml に `level` の鍵が無い。第一の陣でレベルを出すか
3. コンボの有効時間（モックは「あと 2:14」）。dopamine.yml に鍵が無い。提案: `xp.combo_window_seconds`
4. 「過去の神記事を 1 本発掘」の選び方（既読から？ いいね済みから？）。第一の陣では出さない案
5. はてブ数（users）の取得元。第一の陣では出さない案
6. 「約 6 分」の推定読了時間の出し方（本文の文字数 ÷ 定数？ 本文を保存するか）
7. 今日限定カードの条件と +30 XP。dopamine.yml に鍵が無い。第一の陣では出さない案
8. アイキャッチ画像を取るか（本文から og:image？）。第一の陣では出さない案
9. 保存 / レポート / 購読タブが無い間のタブバーの見せ方
10. 未読 0 本のときの文言
11. 「掘り出し物」はカードの属性（記事ごとに事前抽選、または一定割合に付く）か、Roulette の出目（タップ時に抽選）か。前者なら Unit 2 で articles に tier 列が要る。roulette.md の未決 2 と合わせて決める
