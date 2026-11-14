Rails.application.configure do
  config.enable_reloading = false

  config.eager_load = ENV["CI"].present?

  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  config.consider_all_requests_local = true
  # null_store では rate_limit の回数を数えられない。
  config.cache_store = :memory_store

  config.action_dispatch.show_exceptions = :rescuable

  config.action_controller.allow_forgery_protection = false

  config.active_storage.service = :test

  config.action_mailer.delivery_method = :test

  config.action_mailer.default_url_options = { host: "example.com" }

  config.active_support.deprecation = :stderr

  config.action_controller.raise_on_missing_callback_actions = true

  # system spec では音を出さず、鳴らした音の名前を記録させる（app/javascript/controllers/sfx.js）
  config.x.sfx_record = true
end
