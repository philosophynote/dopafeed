---
name: Unit
about: 一 Unit の計画と進捗を置く Issue（docs/plans/unit-N.md の代わり。ADR 0008）
title: "Unit N: <name>"
labels: unit
---

## 範囲
docs/plans/milestone-__.md の Unit __。対象の画面: docs/screens/__.md

## 狙い
この Unit が終わると nao が iPhone で何をできるか、または後続 Unit に何を渡すか。1〜3 行。

## 入口
- 読む文書: docs/SPEC.md、docs/screens/__.md、docs/decisions/____
- 前提の Unit: #__

---
計画は Claude Code（`/kick #N`）がコメントで書く。nao が「承認」とコメントしたら実装に入る。
