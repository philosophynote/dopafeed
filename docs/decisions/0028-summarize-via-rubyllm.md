# ADR 0028: 要約も RubyLLM で呼び、anthropic gem をやめる
日付: 2026-11-19 状態: 採用（#137）。ADR 0024 の「要約は anthropic gem のまま」を改める。ADR 0002 の使い分け（Haiku / Sonnet）、日次上限、VCR は変えない

nao の決定（2026-11-17 の依頼で #137 を起票。2026-11-19「全て承認」で計画の決めること 1〜5 を推奨どおり承認）。

## なぜ
判定（ADR 0024）で RubyLLM が入り、AI の呼び出しの道具が二つになった。これから足す Claude の呼び出し（コメントなど）も同じ道具に乗せたい。要約の見た目・契機・文言は変えず、中の経路だけを替える。

## 決めたこと
- **要約は RubyLLM の chat で、プロバイダは Anthropic、モデルは yml `claude.summary_model`。** `Claude::Client.build` が呼ぶたびに `RubyLLM.context` を作り、鍵（`ANTHROPIC_API_KEY`）、待ち時間（`claude.timeout_seconds`）、gem の再試行なし（`max_retries = 0`。やり直しは Job だけ、#33）をそこに入れる。鍵と秘密の追加は無い
- **1 回の要約は 1 回の要求。** `ask` はツールを求める応答に答えて呼び直すので、`ask_later` のあと `generate` で 1 回だけ生成する。台帳の 1 行と要求の数が合う
- **thinking は明示して切る。** gem はモデルの既定で思考を有効にし、3 行ぶんの `summary_max_tokens` を思考が食って切れる
- **応答の検査は今と同じ。** `finish_reason` が `:max_tokens`（文脈の上限で切れた場合を含む）なら失敗、本文は「・」始まりの 3 行
- **例外の分け方は判定と同じ規則。** 状態なし（接続・タイムアウト）と 408・429・5xx は再試行、それ以外の 4xx は失敗を記録して終わり、RubyLLM::Error 以外の例外も失敗として記録する。anthropic gem のときから変わるのは 408 が再試行になる点だけ
- **呼び出しは app/services/claude/ に集約したまま。** spec/structure は、Anthropic の鍵とプロバイダ指定を app/services/claude/ の外で、RubyLLM を app/judges/・app/services/judgments/・app/services/claude/ の外で書くと落とす
- **テストの応答は手書きのカセットと WebMock のまま。** カセットの照合は method と URI だけで、宛先は変わらないので録り直さない

## 採らなかった案
- **anthropic gem のまま残す**（ADR 0024 の判断）: 道具が二つのまま残り、読み込みの重さも二重になる
- **初期化子で RubyLLM 全体に鍵を入れる**: 鍵の無い箱（CI・開発）で起動から落ちるか、空の鍵のまま呼ぶ。判定と同じく呼ぶたびに context を作る
- **台帳 `claude_api_calls` と `Claude::Budget` の改名を一緒にやる**: 表の改名は migration が要り、デプロイの切り替えの間に古い版が古い表名を読む。中の経路を替えるこの決定と混ぜない

## 承知している弱み
- **gem が付ける `anthropic-version` ヘッダは `2023-06-01`**（SDK は新しい日付を付けていた）。Messages API の要求の形は変わらないが、新しい版でしか使えない機能を使うときは gem の版を確かめる
- **CI の応答は手書き。** 実物との一致はデプロイ後に Reader で記事を 1 本開いて確かめる
- **判定と要約で例外の分け方が 2 か所に同じ形である。** 呼び出しが 3 つ目になったら一か所に寄せる
