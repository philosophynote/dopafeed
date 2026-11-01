---
name: wrapup
description: 「/wrapup #PR」で開いた PR を仕上げる手順。CI と Codex のレビューが返ってきたら読む。
---
入力: PR 番号。Unit の Issue は PR 本文の `Closes #N`。

1. `gh pr checks <PR>` と `gh api repos/{owner}/{repo}/pulls/<PR>/comments`、`gh pr view <PR> --comments` で CI の結果と Codex（`@codex review`）・nao の指摘を読む
2. 妥当な指摘は直して push する。直さない指摘には理由を返信する。テストを消す・skip する・閾値を緩めることで緑にしない
3. CI が赤なら、まず手元で同じ段を再現してから直す（`bin/ci` か該当の `bin/rspec`）
4. 差分が 300 行を大きく超えていたら、割る案を PR に書いて nao に聞く
5. この PR で直さない指摘（リファクタ・セキュリティ・性能・持ち越し）は新しい Issue に切る。ラベル: refactor / security / performance / carryover。本文に元の PR と Issue を書く
6. 最後の push の後、`gh pr checks <PR> --watch` で**新しいコミットの** CI が緑になるのを待つ。1 で読んだ結果は前のコミットのもの
7. Unit の Issue に結果を 1 コメント（CI 緑、Codex 指摘 n 件のうち直した m 件、新 Issue の番号）。マージとデプロイは nao が行う。マージ後は `Closes #N` で Issue が閉じる
