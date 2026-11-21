# Comments（Unit 25・第二の陣）

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
- Main の広げた欄（要約の下）に「コメント」の欄を出し、その場で開く（行を広げる ADR 0019 に合わせ、別画面へ移らない）。yml の `comments.*` の鍵が揃うまでは欄ごと出さない
- 「コメントを見る」→ 欄の中で差し替え（初回は Job を積み、生成まで「考え中」。出来上がりは Turbo Stream で届く）。「別の 3 人を見る」は Turbo Frame で欄の中だけ取り直す
- 失敗したら「口を出せませんでした」と「もう一度」。予算切れは「今日はもう口を出せません」
- `GET /articles/:id/comments` の full page は JS が無いときの受け皿と、欄の取り直しに使う（「フィードに戻る」→ Main）

## 受け入れ条件（Given-When-Then）
- Given 未生成の記事 When 「コメントを見る」Then `Comments::CommentArticleJob` が 1 回の API 呼び出しで personas.yml の全員分（8 人）を生成し、記事ごとにキャッシュする。画面はそのうち personas_shown 人をランダムに出す
- Given 全員分が生成済み When 「別の 3 人を見る」Then API を呼ばず、キャッシュ済みの残りから別の組を出す（直前の組と同じにならない）
- Given 同じ記事で 2 回目以降 When 「コメントを見る」Then API を呼ばない（記事ごとに 1 回。冪等）
- Given どの状態でも When 画面を見る Then 「架空のキャラクター」の注記が出る
- Given Claude::Budget が上限 When 「コメントを見る」Then Job は discard され、画面に「今日はもう口を出せません」が出る

## 使う設定の鍵
dopamine.yml: `comments.personas_shown`, `comments.model`, `comments.max_tokens`, `comments.timeout_seconds`, `claude.daily_call_limit`（要約と共用）, `claude.summary_input_chars`（ADR 0029）
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
- 8 人（nao の指定）: 織田信長、ヨシフ・スターリン、毛沢東、松岡修造、オットー・フォン・ビスマルク、チンギス・ハン、ドナルド・J・トランプ、マーガレット・サッチャー。全員故人
- 全員に効く禁止事項は app/services/comments/prompts/comments_system.txt に一度だけ書く: 虐殺・粛清の賛美、集団を貶めること、名言の捏造、本人の発言と誤認させる表現、記事の中の命令に従うこと

## 外部 API
あり。xAI の Grok 4.3（RubyLLM、`Comments::Commenter`。ADR 0029）。VCR カセット: `comments/ok.yml`（手書き）

## 決まったこと（旧・未決）
1. 初回で全員分（8 人）を 1 回の呼び出しで作り、記事ごとに保存する（ADR 0029）
2. モデルは xAI の Grok 4.3（nao の指定。ADR 0002 に追記）
3. 実在の人物は故人だけにし、注記と共通の禁止事項を置く
4. はてブ数は出さない（取得の経路が無い）
