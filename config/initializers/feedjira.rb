# Atom の xhtml 本文は、前処理を立てないと内側のタグが落ちて文字だけが入る（<pre> や <code> が消える）。
# 前処理は名前空間を全部剥がすので、media:thumbnail の entry.image は取れなくなる（画像を使うときは別の手で読むこと）。
# RSS 側は content:encoded が CDATA なので要らない。
[ Feedjira::Parser::Atom, Feedjira::Parser::AtomFeedBurner, Feedjira::Parser::AtomGoogleAlerts ].each do |parser|
  parser.preprocess_xml = true
end
