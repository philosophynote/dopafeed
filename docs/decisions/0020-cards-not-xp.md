# ADR 0020: XP をやめ、完読した記事がカードになって図鑑に溜まる
日付: 2026-11-08 状態: 採用（#106）。0006 の「確定した xp を保存する」と、SPEC の報酬表の可変報酬・報酬距離・止まり所の仕組みを改める

nao の決定（2026-11-08「ポイントが貯まっても何も起きないので、ジャックポットなどポイント制度を廃止して演出を派手にする方式だとどうなりますか」→ 4 案から「図鑑に置き換える」を選択、#106 の計画を推奨どおり承認）。

## なぜ
累計 XP は Main の隅で増えるだけで、閾値も解放物も使い道も無かった。数字があること自体より、行き先が無いことが「何も起きない」の正体。
演出だけを派手にする案（dopairb の初期の形）は積み上がる感覚を失い、慣れると効かなくなる。dopairb 自身も後から生涯 XP・図鑑（ART DROP）を足している。
そこで、数字ではなく「手に入れて残るもの」に置き換える。素材を作らずに済むよう、読んだ記事そのものをカードにする。

## 決めたこと
- **カード = 完読した `readings` の行。** テーブルは足さない。表は OGP 画像（無ければフィードの色地に見出し）＋見出し＋フィード名＋完読日、枠の色が希少度。未完はカードにならない
- **出目はカードの枠の希少度。** `readings.tier` の値（common / rare / jackpot）はそのまま使い、yml の鍵を `xp.tiers` から `cards.rarities`（name / probability）に改める。倍率は持たない。頂点（金）は yml の最後の段（`Dopamine.top_rarity`）。確率は変えない
- **希少度は開いた時に抽選し、完読で確定する。** 広げた欄・Reader の帯で予告（「出目 レア ・ 完読でレアカード」）し、判定の区切りで開封する。Jackpot 画面は「金のカードが懸かった」の予告になり、「読んで手に入れる」で Reader へ
- **コンボは「n 本連続」の数だけ。** `Combo#multiplier` と `readings.combo_multiplier` は消す。演出の強さに効かせ、確率には効かせない（鍵が要る。持ち越し）
- **宝箱の中身は今日のカード。** `daily_goals.bonus_xp` と鍵 `daily_goal.bonus_xp` を消し、今日手に入れたカードの一覧とストリーク確定を見せる
- **ステータス行の累計 XP は図鑑の枚数に。** `Reading.card_count`。コンボのバッジは「n 連続」（2 以上で出す）
- **列は落とす。** migration で `readings.xp`・`readings.combo_multiplier`・`daily_goals.bonus_xp` を消す。本番の累計 XP は戻らない（nao が承知のうえ）
- **図鑑（Collection）はタブ「レポート」の枠に置く**（23b）。開封の演出（めくり・金の全画面・宝箱の 5 枚）は 23c

## 影響
- docs/SPEC.md の報酬表、docs/screens/main.md・reader.md・roulette.md・jackpot.md・daily_goal.md・saved.md の XP の記述
- `XpRoulette` → `RarityDraw`、`Dopamine.tier*` → `Dopamine.rarit*` / `top_rarity`、locale `dopamine.tiers` → `dopamine.rarities`（通常 / レア / 金）
- #100（Unit 22 演出）はこの形の上で計画し直す
