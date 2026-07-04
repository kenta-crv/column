ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

# .env は development / test で自動読み込み（rails s 単体起動でも STRIPE 等が使えるように）
if %w[development test].include?(ENV.fetch('RAILS_ENV', 'development'))
  env_path = File.expand_path('../.env', __dir__)
  if File.exist?(env_path)
    File.foreach(env_path) do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#')

      key, value = line.split('=', 2)
      next if key.nil? || key.empty? || value.nil?

      value = value.strip.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
      ENV[key] ||= value
    end
  end
end

require 'logger'
require 'bundler/setup' # Set up gems listed in the Gemfile.
require 'bootsnap/setup' # Speed up boot time by caching expensive operations.
