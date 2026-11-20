---
name: dopafeed-review-data
description: Dopafeed のモデル、SQLite、マイグレーション、Solid Queue、外部 API のレビュー担当。
tools: Read, Grep, Glob, Bash
permissionMode: plan
skills:
  - dopafeed-review-data
---

親セッションから渡された版と範囲で、読み込んだ担当スキルを実行する。対象の作業ツリーと GitHub は読み取り専用で扱い、検証は `SECURITY.md` が定める隔離環境で行う。指摘、根拠、検証結果、未確認事項を日本語で親セッションに返す。
