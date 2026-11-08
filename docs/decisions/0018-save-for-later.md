# ADR 0018: 保存は「あとで読む」の取り置き。articles.bookmarked_at に残し、未読の流れから外す
日付: 2026-11-08 状態: 採用（#95）

nao の決定（2026-11-08「Saved を進めて」。#95 の計画を推奨どおり承認）。ADR 0012 が「右スワイプは Saved の Unit で保存に充てる」と空けた分。

- **保存は「あとで読む」の取り置き。** docs/screens/saved.md の旧い目的「あとで読むではなく読み返す」を改める。読み終えても保存は外さず、Saved の一覧に「読んだ」の印付きで残す（読み返す用途も兼ねる）
- **列は既存の `articles.bookmarked_at`（ADR 0006）。** migration は無い。`liked_at`（いいね）はこの Unit では使わず、Saved の一覧（`Article.bookmarked`）にも入れない。`Article.saved`（いいねか保存）はそのまま残す
- **`Article.unread` が `bookmarked_at: nil` を条件に持つ。** 保存した記事は Main の一覧と未読数、アイコンのバッジ、Reader の「次の 1 本」、朝のダイジェスト、購読ごとの未読数から退く（Gmail のアーカイブと同じく受信箱から外れ、スワイプの手応えになる）。`Article.read` は変えない（保存は読んだかどうかを変えない）
- **`readings` に行は作らない。** 保存に抽選も XP も無い。Saved から未読の記事を開けば、Main と同じ「読む」（ルーレット → Reader）で XP も普段どおり付く。読み終えた後の「次の 1 本」は Main と同じ `Article.next_unread_after`（保存は飛ばす）なので、Main の未読から継ぎ足される。読み終えた記事は抽選し直さず、XP の付かない Reader を開くだけ（「読み返す +5 XP」は鍵が無いので出さない）
- **二度目の `bookmark!` は最初の時刻を保つ。** Saved は保存した時刻の新しい順に並ぶので、二重送信で順番を動かさない。取り消しは nil に戻すだけで、未読なら Main に戻る
- **右スワイプが保存を送る。** 閾値と応答待ちは左と同じ `swipe.dismiss_threshold_ratio` / `swipe.submit_timeout_seconds` を使い、鍵を増やさない（左右を別に調整したくなったら鍵を足す）
