# 第一の陣: 「一本読んで、XP が出て、宝箱が開く」

## 範囲
Unit 0（縄張り）, 1（モック写経）, 2（ドメインモデル）, 3（フィード取得ジョブ）, 4（要約ジョブ）,
5（Main + ReadDone）, 6（Roulette + Jackpot）, 7（DailyGoal）, 10（Install）, 15（Login）。
出力段 6 画面（Gacha, Garden, Quest, Hypothesis, Suggest, NetaBox）は対象外。本丸を一週間使ってから決める。

## 完了条件
- Lightsail 上の本番 URL を iPhone のホーム画面に追加できる
- 登録した 5 フィードが Solid Queue で定期取得され、Haiku の 3 行要約が付く
- 記事を開いて dopamine.yml の秒数で完読と判定され、XP ルーレットが回り、レアが出ることがある
- 5 本読むと宝箱が開き、翌日（reset_hour）にリセットされる
- `bin/ci` と GitHub Actions が緑、system test のスクショが 390×844 で残る
- 数字（XP・確率・秒数・本数）がすべて config/dopamine.yml にある
- Litestream が本番で動き、復元手順が docs/runbook.md にある

## 進め方
一本道。Unit 0 → 7 の順。並列は第二の陣から。
