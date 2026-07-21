# Puma can serve each request in a thread from an internal thread pool.
# The `threads` method setting takes two numbers: a minimum and maximum.

threads_count = ENV.fetch("RAILS_MAX_THREADS") { 3 }
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port        ENV.fetch("PORT") { 3000 }

# Specifies the `environment` that Puma will run in.
environment ENV.fetch("RAILS_ENV") { "development" }

# Specifies the `pidfile` that Puma will use.
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Workers (cluster mode)
# macOS + preload_app! は objc fork で落ちることがあるため、
# development は single mode (workers=0) をデフォルトにする。
rails_env = ENV.fetch("RAILS_ENV") { "development" }
default_workers = rails_env == "development" ? 0 : 1
workers_count = Integer(ENV.fetch("WEB_CONCURRENCY") { default_workers })
workers workers_count

# Important: enable Copy on Write optimization
# This reduces memory usage when using workers
preload_app! if workers_count > 0

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
