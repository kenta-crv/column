# frozen_string_literal: true

# 防犯カメラ一括見積（secruri-camera.pro）向けジャンルを追加する。
class AddSecurityCameraGenre < ActiveRecord::Migration[6.1]
  def up
    return unless table_exists?(:service_genres)

    data = GenreRegistry::FALLBACK_GENRES[:security_camera]
    return if data.blank?

    cta = ColumnServiceCta.default_payload_for("security_camera")

    say_with_time "upsert security_camera ServiceGenre" do
      genre = ServiceGenre.find_or_initialize_by(key: "security_camera", client_id: nil)
      genre.ja = data[:ja]
      genre.en = data[:en] if genre.has_attribute?(:en)
      genre.service_name = data[:service_name]
      genre.strong_points = data[:strong_points] if genre.has_attribute?(:strong_points)
      genre.keywords = Array(data[:keywords]) if genre.has_attribute?(:keywords)
      genre.hosts = Array(data[:host]) if genre.has_attribute?(:hosts)
      genre.columns_index_description = data[:columns_index_description] if genre.has_attribute?(:columns_index_description)
      genre.sub_categories = ServiceGenre.stringify_nested(data[:sub_categories] || {})
      if genre.has_attribute?(:column_cta) && cta.present?
        genre.column_cta = ColumnServiceCta.stringify_payload(cta)
      end
      genre.admin_override = true
      genre.save!(validate: false)
    end

    GenreRegistry.reset! if defined?(GenreRegistry)
  end

  def down
    return unless table_exists?(:service_genres)

    ServiceGenre.where(key: "security_camera", client_id: nil).delete_all
    GenreRegistry.reset! if defined?(GenreRegistry)
  end
end
