#!/bin/bash
# Claude Code のクラウドセッション（Claude Code on the web / プロジェクトのスレッド）が始まるたびに走り、
# bin/ci が回る状態まで整える。Mac のローカル Claude Code では何もしない（CLAUDE_CODE_REMOTE を見る）。
#
# 置き場所: .claude/hooks/session-start.sh（chmod +x）。登録は .claude/settings.json の hooks.SessionStart。
# 必要なネットワーク許可（環境設定の Allowed domains）: cache.ruby-lang.org（Ruby のソース）。他は既定の許可で足りる
# 冪等。二度目以降は Ruby のビルドも bundle install も飛ばす。
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"

# --- 1. Ruby（.ruby-version の版を rbenv で用意する）-------------------------------
RUBY_VERSION="$(sed 's/^ruby-//' .ruby-version)"
export RBENV_ROOT="${RBENV_ROOT:-/opt/rbenv}"
if [ ! -x "$RBENV_ROOT/bin/rbenv" ]; then
  # 素の箱に rbenv が無ければ自前で入れる
  export RBENV_ROOT="$HOME/.rbenv"
  [ -d "$RBENV_ROOT" ] || git clone -q https://github.com/rbenv/rbenv.git "$RBENV_ROOT"
fi
export PATH="$RBENV_ROOT/shims:$RBENV_ROOT/bin:$PATH"

if [ ! -x "$RBENV_ROOT/versions/$RUBY_VERSION/bin/ruby" ]; then
  echo "== Ruby $RUBY_VERSION を用意する（初回だけ。数分かかる）=="
  # ruby-build の定義を最新にする（箱に入っている ruby-build は新しい Ruby を知らない）
  plugin="$RBENV_ROOT/plugins/ruby-build"
  if ! { [ -d "$plugin/.git" ] \
         && git -C "$plugin" fetch -q --depth 1 origin master \
         && git -C "$plugin" checkout -q --detach FETCH_HEAD; } 2>/dev/null; then
    rm -rf "$plugin"
    git clone -q --depth 1 https://github.com/rbenv/ruby-build.git "$plugin"
  fi
  # ソースは cache.ruby-lang.org から落ちる。403 ならクラウド環境の Allowed domains に足すこと
  MAKE_OPTS="-j$(nproc)" RUBY_CONFIGURE_OPTS="--disable-install-doc" rbenv install -s "$RUBY_VERSION"
fi
rbenv rehash
echo "ruby: $(ruby -v)"

# --- 2. bundler / gems / DB / lefthook（bin/setup が全部やる。冪等）------------------
# Gemfile.lock の BUNDLED WITH と同じ bundler を入れる（無ければ）
bundled_with="$(awk '/^BUNDLED WITH/{getline; gsub(/ /,""); print}' Gemfile.lock)"
gem list -i bundler -v "$bundled_with" >/dev/null 2>&1 || gem install bundler -v "$bundled_with" --no-document
echo "== bin/setup --skip-server（bundle install / db:prepare / db:seed / lefthook install）=="
bin/setup --skip-server
RAILS_ENV=test bin/rails db:prepare

# --- 3. Chrome / chromedriver（390×844 のシステムテスト用）----------------------------
# 箱には Google Chrome が入っているが、PATH の chromedriver は版が古く、selenium-manager の自動取得は
# googlechromelabs.github.io が塞がれていて動かない。Chrome と同じ版の chromedriver を
# storage.googleapis.com（既定で許可されている）から直接取り、PATH の先頭に置く。
DRIVER_DIR=""
if command -v google-chrome >/dev/null 2>&1; then
  chrome_version="$(google-chrome --version | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
  echo "chrome: $chrome_version"
  DRIVER_DIR="$HOME/.cache/dopafeed/chromedriver-$chrome_version"
  if [ ! -x "$DRIVER_DIR/chromedriver" ]; then
    echo "== chromedriver $chrome_version を取る =="
    tmpzip="$(mktemp)"
    curl -fsSL -o "$tmpzip" "https://storage.googleapis.com/chrome-for-testing-public/$chrome_version/linux64/chromedriver-linux64.zip"
    mkdir -p "$DRIVER_DIR"
    unzip -q -o -j "$tmpzip" 'chromedriver-linux64/chromedriver' -d "$DRIVER_DIR"
    chmod +x "$DRIVER_DIR/chromedriver"
    rm -f "$tmpzip"
  fi
  export PATH="$DRIVER_DIR:$PATH"
  echo "chromedriver: $("$DRIVER_DIR/chromedriver" --version)"
else
  echo "!! google-chrome が無い。システムテスト（bin/rspec spec/system）は落ちる" >&2
fi

# --- 4. この後のセッション全体で効かせる環境変数 ----------------------------------------
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export RBENV_ROOT=\"$RBENV_ROOT\""
    echo "export PATH=\"$RBENV_ROOT/shims:$RBENV_ROOT/bin:\$PATH\""
    [ -n "$DRIVER_DIR" ] && echo "export PATH=\"$DRIVER_DIR:\$PATH\""
  } >> "$CLAUDE_ENV_FILE"
fi

echo "== 準備完了。bin/ci が回せる =="
