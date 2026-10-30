# ForYou（Unit 未定・第二の陣。案: 11）

## 目的
FOMO と個人最適化。Claude が未読から「今日の 3 本」を理由付きで選ぶ。朝 7:30 に更新され、Push の朝ダイジェストと対になる。
フィード重みは Rails 側の Thompson サンプリングで学習し、Claude には未読のタイトルと興味プロファイルだけを渡す。

## 要素
1. Main と同じヘッダとセグメント（「あなた向け」が選択状態）
2. 「いまの興味プロファイル（いいね・読了から学習）」+「編集」（→ Learning）。タグと重み「Rails 92 強化学習 71 Kaggle 64 設計 58 AWS 41 政治 4」（DB: タグ別スコア。未決 1）
3. 「Claude が未読 48 本から選んだ今日の 3 本 朝 7:30 更新」（本数・時刻は未決 2）
4. おすすめカード × 3: フィード名、相対時刻、見出し、「なぜこれ？」（Claude の理由。DB にキャッシュ）、「読むと分かること: …」、ボタン「興味なし」「保存」「読む ＋おすすめ ×1.2」（倍率は未決 3）
5. 注記「仕組み: … 1 日 1 回、約 ¥2」（固定）
6. タブバー

## 遷移
- Main のセグメント → ForYou（Turbo Frame で一覧部分だけ置換）
- 「読む」→ Roulette（おすすめ倍率付き）
- Push の朝ダイジェストをタップ → ForYou

## 受け入れ条件（Given-When-Then）
- Given 朝の Job が走った When ForYou を開く Then 3 本と理由が出て、同日中は API を呼ばない
- Given 未読が 3 本未満 When Job が走る Then ある分だけ選び、空なら「今日はおすすめ無し」
- Given Budget 上限 When Job が走る Then discard され、前日の 3 本が残る

## 使う設定の鍵
dopamine.yml: `claude.curation_model`, `claude.daily_call_limit`。選定本数・時刻・おすすめ倍率は鍵が無い（未決 2, 3）
personas.yml: なし

## 外部 API
あり。Claude Sonnet（`Claude::CurationJob`、VCR: `claude/curation_three.yml`）。Solid Queue の定期ジョブ（recurring.yml）

## 未決
1. 興味プロファイルの実体（タグはどう付くか。Unit 4 の要約時に Claude にタグも出させる案）
2. 本数 3、時刻 7:30。提案: `curation.articles: 3`, `curation.at: "07:30"`
3. おすすめ倍率 ×1.2。提案: `xp.recommended_multiplier: 1.2`
4. Thompson サンプリングの設計（フィードごとの α/β を何で更新するか）。ADR を足す
