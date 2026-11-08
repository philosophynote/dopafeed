# ADR 0012: 興味なしは articles.dismissed_at に残し、読了の行は作らない
日付: 2026-11-05 状態: 採用（#56）。「右スワイプは何もしない」は ADR 0018 が改めた（保存）

nao の決定（2026-11-05「関心がない記事もあるのでスワイプで完了できるようにしたい。Tinder みたいに」。#56 の計画を推奨どおり承認）。ADR 0006 が「Swipe の列はその Unit で ADR と一緒に足す」と残した分。

- **列は `articles.dismissed_at`（datetime、index）。** いいね・保存と同じく記事に直接残す（一人用。ADR 0006）
- **`readings` に行は作らない。** 読んでいない記事に抽選と XP の行を持たせない（article_id の一意制約とも衝突する）。帰結として XP は 0、`Reading.completed` に入らないので読了累計・今日のゴール（`Reading.on`）・`Combo`・`ReadingStreak` のどれも動かない。鍵の追加も無い
- **`Article.unread` が `dismissed_at: nil` を条件に持つ。** Main の一覧と未読数、Reader の「次の 1 本」（`next_unread_after`）はこの scope を通るので、興味なしを自動で飛ばす。`Article.read` は変えない（興味なしは読了ではない）
- **開いたが未完の `Reading` がある記事を興味なしにしても、その行は残す。** 戻したときに出目を使い回す（再抽選しない。ADR 0006）。開いたままの Reader でその記事を読み終えれば完読になり XP も付く（読んだのは事実。`Article.read` に入り、`unread` には入らない）。判定は `dismissed_at` を見ない
- **取り消しは `dismissed_at` を nil に戻すだけ。** 二度目の `dismiss!` は最初の時刻を保つ。時刻は後の学習の材料なので、二重送信で動かさない
- **学習はしない。** フィードと単語の重みを下げる（SPEC の Thompson サンプリング）は ADR が無く第二の陣。ここでは材料を残すだけ。一掃（swipe.md 要素 1）の記事を同じ列で持つか別の列（archived）にするかは、一掃の Unit で決める
- **右スワイプは何もしない。** いいね・保存の列はあるが Saved 画面が無い間は押しても見えず、「読む」に繋ぐと指の勢いでルーレットと遷移が起きる。右は Saved の Unit で「保存」に充てる
