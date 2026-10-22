# <Screen 名>（Unit <n>）

## 目的
この画面が担う報酬要素と、ユーザーが得るもの。一段落。

## 要素
モックに写っているものを上から列挙。各要素に「出典: 固定 / DB / dopamine.yml の鍵」を添える。

## 遷移
入ってくる画面 → この画面 → 出ていく画面。Turbo Frame か Stream か full page か。

## 受け入れ条件（Given-When-Then）
- Given 未読記事が 3 本ある When 一覧を開く Then 3 本が新しい順に並ぶ
- Given … When … Then …

## 使う設定の鍵
dopamine.yml: 
personas.yml: 

## 外部 API
あり / なし。あれば Job 名と VCR カセット名。

## 未決
モックから読み取れなかったこと。nao に聞く。
