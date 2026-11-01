# ADR 0008: Unit の計画と進捗は GitHub Issue に置く
日付: 2026-11-01 状態: 採用（Unit 3 から）

nao の決定（2026-11-01、watany「スマホで簡単 Claude Projects でらくらく Vibe Coding」の評定より）。

- 一 Unit = 一 Issue。計画（Context / 決めること / 変更 / 手順 / 差分の見込み / 触らないもの / 検証 / 持ち越し）は Issue のコメントに書き、nao の「承認」コメントで実装に入る。PR は `Closes #N` で Issue に結ぶ
- 理由: 作業中だけ要る文書をリポジトリに永続化すると docs/plans が肥大化し、検索とコンテキストを汚す。Issue なら iPhone の GitHub アプリから読んで承認でき、Unit が終われば閉じる
- 知識は動かさない: docs/SPEC.md、docs/screens/、docs/decisions/ は引き続きリポジトリが正典。docs/plans/ には陣（milestone）の範囲と完了条件だけ残す
- docs/plans/unit-0.md 〜 unit-2.md は履歴として残す。Unit 3 以降は作らない
- 手順は `.claude/skills/kick`（Issue → PR）と `.claude/skills/wrapup`（PR → マージ依頼）に置く。Codex からも `.agents/skills` 経由で同じ文を読む
- レビューで出た持ち越し（リファクタ・セキュリティ・性能）も Issue に切る。PR 本文や plan に埋めない
