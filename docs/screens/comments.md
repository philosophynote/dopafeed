# Comments（Unit 未定・第二の陣。案: 9）

## 目的
社会的報酬。著名人を模した架空 AI キャラクターが記事に口を出す。押すたびに 8 人から 3 人がランダムに現れ、「誰が出るか分からない」可変報酬にもなる。
返信機能は持たない。読んで笑って次へ。

## 要素
1. ヘッダ: 「フィードに戻る」（→ Main）、「コメント」
2. 記事カード: フィード名、見出し（DB）
3. 未開封状態: 「? ? ?」「この記事に、誰が口を出すか」「8 人の中から 3 人がランダムに現れます」、ボタン「コメントを見る」（人数は personas.yml の件数と `comments.personas_shown`）
4. 開封状態: 3 人分のカード（イニシャルの丸アイコン・名前・「AI」バッジ・肩書き・本文）、ボタン「別の 3 人を見る」
5. 注記「人物は AI による架空のキャラクターです。本人の発言ではありません」（固定。必ず出す）

## 遷移
- Main のカードの「コメント」→ Comments（full page）
- 「コメントを見る」→ 同画面内で Turbo Frame 置換（初回は Job を起動し、生成まで「考え中」を出す）
- Comments → Main

## 受け入れ条件（Given-When-Then）
- Given 未生成の記事 When 「コメントを見る」Then `Claude::CommentsJob`（仮）が 1 回の API 呼び出しで personas_shown 人分を生成し、記事ごとにキャッシュする
- Given 生成済み When 「別の 3 人を見る」Then API を呼ばず、キャッシュ済みの人物から別の組を出す（未決 1）
- Given どの状態でも When 画面を見る Then 「架空のキャラクター」の注記が出る
- Given Claude::Budget が上限 When 「コメントを見る」Then Job は discard され、画面に「今日はもう口を出せません」が出る

## 使う設定の鍵
dopamine.yml: `comments.personas_shown`, `claude.daily_call_limit`, `claude.curation_model`（コメントのモデルは未決 2）
personas.yml: 全件（下のスキーマ）

### config/personas.yml のスキーマ（grok-council の personas を移植。この Unit で作る）
```yaml
personas:
  - id: oda-nobunaga          # 英小文字とハイフン
    name: 織田信長
    title: 戦国大名
    color: "#F0831A"          # アイコンの色
    description: 一行の人物像
    system_prompt: |          # 4 部構成: 基本スタンス / 話し方 / コメントの型 / 禁止事項
      ...
```
- モックの 8 人: 織田信長、孔子、マーガレット・サッチャー、イーロン・マスク、スティーブ・ジョブズ、アリストテレス、シモーヌ・ド・ボーヴォワール、ドナルド・J・トランプ
- 禁止事項に必ず入れる: 名言の捏造、本人の発言と誤認させる表現。Claude は Grok より穏やかになるので過激な部分は削る

## 外部 API
あり。Claude（`Claude::CommentsJob`、VCR カセット: `claude/comments_three_personas.yml`, `claude/comments_budget_exhausted.yml`）

## 未決
1. 「別の 3 人」のたびに API を呼ぶか、初回で 8 人分を生成して出し分けるか（費用と鮮度）
2. コメントのモデル（Haiku で十分か Sonnet か）。ADR 0002 に追記
3. 実在の人物（存命含む）を模すことの表現上の線引き。注記と禁止事項で足りるか
4. はてブ数（「社会的報酬」の表にある）をこの画面に出すか
