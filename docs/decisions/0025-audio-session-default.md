# ADR 0025: 効果音の audioSession は指定せず、iOS の既定に任せる
日付: 2026-11-17 状態: 採用（#138）。ADR 0022 の「`navigator.audioSession.type = "ambient"` を明示する」を改める

nao の報告（2026-11-17「音が鳴らない」）。iPhone 14 Plus・iOS 27.0.1 で、消音スイッチを切り、効果音のトグルをオンにしても、Safari でもホーム画面のアプリでも効果音が一つも鳴らなかった。開き直しても、再起動しても変わらなかった。

## 切り分け
- Web Audio の試験サイト（szynalski.com の tone-generator）は、同じ iPhone の Safari で鳴った。このサイトは audioSession を指定しない
- sfx.js と同じ合成・同じ起こし方（pointerup で作る、無音を流す、resume してから鳴らす）を、Claude アプリ内の iframe のページで試すと 4 通りとも鳴った。iframe では `"ambient"` を代入しても `auto` のままで、指定が効いていなかった
- 違いとして残ったのは、上のフレームで `"ambient"` を明示していることだけだった

## 決めたこと
- **audioSession の種類は指定しない。** iOS は Web Audio だけを鳴らすページを消音スイッチに従わせ、聴いている音楽も止めない。0022 の狙い（消音に従う、音楽を止めない）は既定のままで保てる
- **`"playback"` は今回も採らない。** 確実に鳴るが、消音を越えて鳴り、音楽も止める（0022 と同じ理由）
- **指定を戻させない。** `spec/structure/audio_session_spec.rb` が、app/javascript のコメント以外に `audioSession` が出ると落ちる

## 確かめ残し
- 上のフレームで、sfx.js から指定だけを外した形は、デプロイ後に nao の iPhone で確かめる。消音 OFF で鳴ること、消音 ON で鳴らないこと、音楽を流したまま鳴らしても止まらないこと
- 鳴らなければ、原因は指定ではなかったことになる。#138 に書いて掘り直す
