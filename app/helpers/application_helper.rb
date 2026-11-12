module ApplicationHelper
  # 効果音の印。鳴らす要素の data-controller に混ぜず、中に置く（同じ要素の他のコントローラを探す側を壊さない）。
  # 音の名前は app/javascript/controllers/sfx.js の CUES。cue が nil なら何も描かない
  def sfx_cue(cue, delay: nil)
    return if cue.blank?

    tag.span(hidden: true, data: { controller: "sfx", sfx_cue_value: cue, sfx_delay_value: delay })
  end
end
