# frozen_string_literal: true

class PublicAssetFallbacksController < ActionController::Base
  # ブランドサイト経由の .js は別オリジン扱いになり、CSRF 検証が 422 を返す。
  skip_forgery_protection

  def show
    relative = relative_asset_path
    file = locate_asset(relative)
    if file
      expires_in 30.days, public: true
      send_file file, disposition: "inline"
    else
      head :not_found
    end
  end

  private

  def relative_asset_path
    raw = params[:path].to_s
    format = params[:format].to_s
    raw = "#{raw}.#{format}" if format.present? && !raw.end_with?(".#{format}")
    return if raw.blank? || raw.include?("\0")

    cleaned = Pathname.new(raw).cleanpath.to_s
    return if cleaned == "." || cleaned.start_with?("/") || cleaned == ".." || cleaned.start_with?("../")

    cleaned
  end

  def locate_asset(relative)
    return if relative.blank?

    %w[assets_ok assets].each do |directory|
      root = Rails.root.join("public", directory).cleanpath
      file = root.join(relative).cleanpath
      next unless file.to_s.start_with?("#{root}#{File::SEPARATOR}")
      return file if file.file?
    end

    nil
  end
end
