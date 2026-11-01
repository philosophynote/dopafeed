---
name: kick
description: 「/kick #N」または「/kick Unit N」で一 Unit を GitHub Issue から PR まで回す手順。Unit の実装を始めるときに必ず読む。
---
一 Unit = 一 Issue = 一ブランチ `unit-<n>-<name>` = 一 PR。計画と進捗は Issue に書き、リポジトリに中間ファイルを増やさない（ADR 0008）。

## 入口
- `/kick #N`: Issue N を読む（`gh issue view N --comments`）
- `/kick Unit N`: Issue が無ければ `.github/ISSUE_TEMPLATE/unit.md` の体裁で `gh issue create --title "Unit N: <name>" --label unit` を先に行い、その番号で続ける

## 手順
1. Issue 本文、docs/SPEC.md、対象の docs/screens/<name>.md（受け入れ条件と未決）、関係する docs/decisions/ を読む。docs/plans/milestone-*.md で陣の範囲を確かめる
2. 計画を Issue に **1 コメント**で書く。見出しは次の通り（docs/plans/unit-2.md と同じ型）: Context / 決めること（nao の承認で確定。ADR が要るもの） / 変更（ファイル単位） / 手順（テスト先行） / 差分の見込み / 触らないもの / 検証 / 持ち越し。
   未決への問いは「決めること」に番号を付けて並べ、推奨を添える
3. **nao の「承認」コメントを待つ。** 承認の無い計画で実装に入らない。質問への答えで計画が変わったら、差分を短い追記コメントにする（元コメントの編集はしない。履歴を残す）
4. 承認後、`git checkout -b unit-<n>-<name>`（base は main）。spec を先に書き、`bin/rspec` で赤を確かめる
5. 実装する。`bin/ci` が緑になるまで直す。同じ修正に二度失敗したら止まり、Issue に状況を書く
6. 画面を触った Unit は `bin/screens` で tmp/screenshots/ に 390×844 の絵を撮る
7. `reviewer` サブエージェントに差分と Issue 番号を渡し、指摘を直す。直した点は Issue に「レビューで直したこと」として 1 コメント
8. `.github/pull_request_template.md` の欄を全部埋めて PR を開く。Unit 欄は `Closes #N`。絵を貼る。末尾の `@codex review` を残す
9. Issue に PR のリンクを 1 コメント。以後は `/wrapup #PR`

## 守ること
- 差分 300 行前後。超えそうなら割る案を Issue に書いて止まる
- config/dopamine.yml・`kamal deploy`・secrets には触らない。数字の提案は PR 本文の提案欄へ
- Issue への書き込みは「計画」「追記」「レビューで直したこと」「PR リンク」「止まった理由」だけ。作業ログを垂れ流さない（iPhone で読める量に保つ）
