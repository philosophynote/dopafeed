// Turbo は form の送信中に別の form が送られると先の送信を止めて応答を捨てる（先の行が画面に残る、取り消しが画面に出ない）。
// 一覧の行の送信と取り消しのトーストの送信を同じ 1 本の列に並べ、前の送信が終わってから次を送る。
// run は前が終わってから呼ばれ、返した Promise が解けるまで次を待たせる。列を止めないよう、run は必ず解ける Promise を返すこと
let tail = Promise.resolve()

export function enqueue(run) {
  tail = tail.then(run)
  return tail
}

// 行を片付ける送信（応答が取り消しのトーストを置き換える）を送った回数。
// トーストは出た時の回数を覚え、増えていたら自分はもう置き換わる側だと分かる。
// 応答が画面に描かれるのは submit-end より後で、その時刻は決まらないので、画面からではなくこの回数で見る
let swipesSent = 0

export function noteSwipeSent() {
  swipesSent += 1
}

export function swipeCount() {
  return swipesSent
}
