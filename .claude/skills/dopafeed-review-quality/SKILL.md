---
name: dopafeed-review-quality
description: Dopafeed のレビューで受け入れ条件、RSpec と FactoryBot、Ruby の保守性、CI・運用設定と手順を検査する。dopafeed-review からの委任、またはこれらの観点を指定したレビューで使う。
---

# テストと保守性のレビュー

1. `AGENTS.md` と `SECURITY.md` を読む。対象の版で承認済み要件・画面仕様と変更を照合し、期待する結果をどの spec が保証するかを追う。[Test の確認項目](references/test.md) を使い、失敗、境界値、再試行、同時実行のうち変更に関係する条件を調べる。
2. [Ruby と設定の確認項目](references/ruby.md) を使い、既存の呼び出し方法、`spec/structure/`、`config/dopamine.yml` の責務、ADR の規約と照合する。文書やエージェント設定の差分は、実際のパス、コマンド、権限、前提となるツールで手順が成立するかを確認する。
3. CI・運用の変更では `config/ci.rb`、関連する Actions、運用手帳を読み、検証対象と配布物の版、権限、排他、失敗時の回復、旧版と DB の互換性を確認する。検証は `SECURITY.md` の範囲で行う。
4. 指摘、確認事項、検証結果を `AGENTS.md` に従って日本語で返す。
