#!/bin/bash
# Ruby ソースの取得には cache.ruby-lang.org のネットワーク許可が必要。
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"

RUBY_VERSION="$(sed 's/^ruby-//' .ruby-version)"
export RBENV_ROOT="${RBENV_ROOT:-/opt/rbenv}"
if [ ! -x "$RBENV_ROOT/bin/rbenv" ]; then
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
  MAKE_OPTS="-j$(nproc)" RUBY_CONFIGURE_OPTS="--disable-install-doc" rbenv install -s "$RUBY_VERSION"
fi
rbenv rehash
echo "ruby: $(ruby -v)"

bundled_with="$(awk '/^BUNDLED WITH/{getline; gsub(/ /,""); print}' Gemfile.lock)"
gem list -i bundler -v "$bundled_with" >/dev/null 2>&1 || gem install bundler -v "$bundled_with" --no-document
echo "== bin/setup --skip-server（bundle install / db:prepare / db:seed / lefthook install）=="
bin/setup --skip-server
RAILS_ENV=test bin/rails db:prepare

# PATH の chromedriver は古く、自動取得先が塞がれているため、Chrome と同じ版を直接取る。
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

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export RBENV_ROOT=\"$RBENV_ROOT\""
    echo "export PATH=\"$RBENV_ROOT/shims:$RBENV_ROOT/bin:\$PATH\""
    [ -n "$DRIVER_DIR" ] && echo "export PATH=\"$DRIVER_DIR:\$PATH\""
  } >> "$CLAUDE_ENV_FILE"
fi

echo "== 準備完了。bin/ci が回せる =="
