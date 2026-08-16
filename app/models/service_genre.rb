class ServiceGenre < ApplicationRecord
  belongs_to :client, optional: true

  attr_accessor :admin_override

  validates :key, presence: true,
                  format: { with: /\A[a-z0-9_]+\z/, message: "は英小文字・数字・アンダースコアのみ使用できます" },
                  uniqueness: { scope: :client_id }
  validates :ja, presence: true

  before_validation :normalize_key
  before_validation :ensure_columns_index_description
  validate :within_client_genre_limit, on: :create
  validate :within_client_sub_category_limit, if: -> { client_id? && !admin_override }
  after_save :sync_client_allowed_genres, if: :client_id?
  after_destroy :sync_client_allowed_genres_on_destroy, if: :client_id?
  after_commit :reset_genre_registry_cache

  def to_registry_hash
    {
      ja: ja,
      en: (has_attribute?(:en) ? self[:en].to_s.presence : nil),
      host: Array(hosts),
      service_name: service_name.to_s,
      keywords: Array(keywords),
      strong_points: strong_points,
      columns_index_description: columns_index_description_value,
      images: Array(images),
      sub_categories: deep_symbolize(sub_categories || {}),
      column_cta: column_cta_value
    }.compact
  end

  def column_cta_value
    return unless has_attribute?(:column_cta)

    raw = self[:column_cta]
    return {} if raw.blank?

    raw
  end

  def column_cta_index_state
    raw = has_attribute?(:column_cta) ? self[:column_cta] : nil
    stored = raw.is_a?(Hash) ? raw.with_indifferent_access : {}.with_indifferent_access
    enabled = !(stored[:enabled] == false || stored[:enabled].to_s == "0")
    title = stored[:title].presence || ColumnServiceCta::CTAS.dig(key.to_sym, :title)
    { enabled: enabled, title_present: title.present? }
  end

  def column_cta_enabled?
    data = column_cta_for_form
    flag = data[:enabled]
    !(flag == false || flag.to_s == "false" || flag.to_s == "0")
  end

  def column_cta_for_form
    default = ColumnServiceCta.stringify_payload(ColumnServiceCta.default_payload_for(key) || {})
    stored = has_attribute?(:column_cta) ? ColumnServiceCta.stringify_payload(self[:column_cta] || {}) : {}
    merged = default.deep_merge(stored)
    merged["enabled"] = true unless merged.key?("enabled")
    merged.with_indifferent_access
  end

  def default_columns_index_description
    name = service_name.presence || ja.presence || key
    tip = strong_points.to_s.gsub(/\s+/, " ").strip
    tip = tip.truncate(70) if tip.present?
    if tip.present?
      "#{name}に関する解説記事一覧。#{tip}"
    else
      "#{name}に関する解説記事一覧。導入・運用・事例のポイントをまとめています。"
    end
  end

  def columns_index_description_value
    return unless has_attribute?(:columns_index_description)

    self[:columns_index_description]
  end

  def sub_categories_count
    (sub_categories || {}).size
  end

  def self.registered_key?(key)
    return false if key.blank?

    exists?(key: GenreRegistry.equivalent_keys(key))
  end

  # 運営側（自社）ジャンル。Enterprise 相当のアトリビューション扱い。
  def self.platform_owned?(key)
    return false if key.blank?

    keys = GenreRegistry.equivalent_keys(key)
    scope = where(client_id: nil)
    scope.where(key: keys).or(scope.where(ja: key.to_s)).exists?
  end

  def platform_owned?
    client_id.nil?
  end

  def self.owner_client_id_for(key, host: nil, client: nil)
    return client.id if client&.id.present?
    return nil if key.blank?

    candidates = where(key: GenreRegistry.equivalent_keys(key)).where.not(client_id: nil)
    return candidates.first.client_id if candidates.one?

    if host.present?
      normalized = host.to_s.downcase.sub(/\Awww\./, "").sub(/:\d+\z/, "")
      match = candidates.find do |record|
        Array(record.hosts).any? do |entry|
          entry.to_s.downcase.sub(/\Awww\./, "").sub(/:\d+\z/, "") == normalized
        end
      end
      return match.client_id if match
    end

    nil
  end
  def sub_categories_for_form
    categories = sub_categories.is_a?(Hash) ? sub_categories : {}
    return [] if categories.blank?

    categories.map do |key, data|
      data = data.with_indifferent_access
      {
        key: key.to_s,
        name: data[:name],
        name_en: data[:name_en],
        target: data[:target],
        description: data[:description],
        features_text: Array(data[:features]).join("\n"),
        keywords_text: Array(data[:keywords]).join("\n"),
        price_hint: data[:price_hint],
        area: data[:area],
        strengths: data[:strengths],
        industry_weakness: data[:industry_weakness]
      }
    end
  end

  def self.from_fallback_template(template_key)
    canon = GenreRegistry.canonical_key(template_key).presence || template_key.to_s
    data = GenreRegistry::FALLBACK_GENRES[canon.to_sym]
    return new unless data

    attrs = {
      key: canon.to_s,
      ja: data[:ja],
      service_name: data[:service_name],
      strong_points: data[:strong_points],
      hosts: Array(data[:host]),
      keywords: Array(data[:keywords]),
      images: Array(data[:images]),
      sub_categories: stringify_nested(data[:sub_categories] || {})
    }
    attrs[:en] = data[:en] if attribute_names.include?("en") && data[:en].present?
    if attribute_names.include?("columns_index_description")
      attrs[:columns_index_description] = data[:columns_index_description]
    end
    if attribute_names.include?("column_cta")
      default_cta = ColumnServiceCta.default_payload_for(canon)
      attrs[:column_cta] = ColumnServiceCta.stringify_payload(default_cta) if default_cta.present?
    end
    new(attrs)
  end

  def self.stringify_nested(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested), result|
        result[key.to_s] = stringify_nested(nested)
      end
    when Array
      value.map { |item| stringify_nested(item) }
    else
      value
    end
  end

  private

  def normalize_key
    return if key.blank?

    self.key = key.to_s.strip.downcase
    self.key = GenreRegistry.canonical_key(key)
  end

  def ensure_columns_index_description
    return unless has_attribute?(:columns_index_description)
    return if columns_index_description_value.to_s.strip.present?

    self.columns_index_description = default_columns_index_description
  end

  def within_client_sub_category_limit
    owner = client
    return unless owner

    limit = owner.max_sub_category_count
    count = sub_categories_count
    return if count <= limit

    errors.add(:base, owner.plan_limit_message(:sub_category))
  end

  def within_client_genre_limit
    return if client_id.blank?

    owner = client
    return unless owner
    return if owner.can_add_genre?

    errors.add(:base, owner.plan_limit_message(:genre))
  end

  def sync_client_allowed_genres
    self.class.sync_allowed_genres_for_client!(client_id)
  end

  def sync_client_allowed_genres_on_destroy
    self.class.sync_allowed_genres_for_client!(client_id)
  end

  def self.sync_allowed_genres_for_client!(client_id)
    client = Client.find_by(id: client_id)
    return unless client

    client.update!(allowed_genres: client.service_genres.pluck(:key))
  end

  def reset_genre_registry_cache
    GenreRegistry.reset!
  end

  def deep_symbolize(value)
    case value
    when Hash
      value.each_with_object({}) do |(k, v), result|
        result[k.to_sym] = deep_symbolize(v)
      end
    when Array
      value.map { |item| deep_symbolize(item) }
    else
      value
    end
  end
end
