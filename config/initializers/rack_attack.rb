class Rack::Attack
  Rack::Attack.cache.store = Rails.cache

  # 記事配信API（/api/v1/*）は、APIキー単位で1分間に60回までに制限する。
  # 未認証（APIキーなし）のアクセスはIPアドレス単位で1分間に20回までに制限する。
  throttle('api/v1/by_api_key', limit: 60, period: 1.minute) do |req|
    next unless req.path.start_with?('/api/v1/')

    api_key = req.get_header('HTTP_X_API_KEY').presence || req.params['api_key'].presence
    api_key
  end

  throttle('api/v1/by_ip', limit: 20, period: 1.minute) do |req|
    next unless req.path.start_with?('/api/v1/')

    api_key = req.get_header('HTTP_X_API_KEY').presence || req.params['api_key'].presence
    req.ip unless api_key
  end

  # 公開 SEO チェッカーのバースト防止（日次3回制限とは別の短時間ガード）
  throttle("seo_checker/by_ip", limit: 10, period: 1.minute) do |req|
    next unless req.post? && req.path.match?(%r{\A(/en)?/tools/seo-checker/?\z})

    req.ip
  end

  self.throttled_responder = lambda do |request|
    match_data = request.env['rack.attack.match_data']
    now = match_data[:epoch_time]
    retry_after = match_data[:period] - (now % match_data[:period])

    headers = {
      'Content-Type' => 'application/json',
      'Retry-After' => retry_after.to_s
    }

    [429, headers, [{ error: 'Too many requests. Please slow down and retry later.' }.to_json]]
  end
end
