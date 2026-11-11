threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

port ENV.fetch("PORT", 3000)

plugin :tmp_restart

plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# solid_queue_mode は上の plugin が読み込まれて初めて使える。plugin は :async 以外を黙って fork に倒すので、綴り違いは起動時に落とす
if ENV["SOLID_QUEUE_IN_PUMA"]
  solid_queue_mode_name = ENV.fetch("SOLID_QUEUE_MODE", "fork")
  raise ArgumentError, "SOLID_QUEUE_MODE must be fork or async, got #{solid_queue_mode_name.inspect}" unless %w[fork async].include?(solid_queue_mode_name)

  solid_queue_mode solid_queue_mode_name
end

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
