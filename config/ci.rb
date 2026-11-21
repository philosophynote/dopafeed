CI.run do
  step "Setup", "bin/setup --skip-server"
  step "Style: Ruby", "bin/rubocop"
  step "Style: ERB", "bundle exec erb_lint --lint-all"
  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap audit", "bin/importmap audit"
  step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Structure: 規約テスト", "bin/rspec spec/structure"
  # system は flaky で遅く PR とデプロイを止めるので、ここでは回さず毎晩 bin/system-nightly で回す
  step "Tests: Rails", "bin/rspec --exclude-pattern 'spec/system/**/*_spec.rb'"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  if success?
    step "Signoff: 緑。マージしてよい", "true"
  else
    failure "Signoff: 赤。マージするな", "落ちた段を直してから bin/ci を再実行せよ"
  end
end
