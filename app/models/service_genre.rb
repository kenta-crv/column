class ServiceGenre < ApplicationRecord
  belongs_to :client, optional: true

  attr_accessor :admin_override

  validates :key, presence: true,
                  format: { with: /\A[a-z0-9_]+\z/, message: "は英小文字・数字・アンダースコアのみ使用できます" },
                  uniqueness: { scope: :client_id }
  validates :ja, presence: true

  before_validation :normalize_key
  validate :within_client_genre_limit, on: :create
  validate :within_client_sub_category_limit, if: -> { client_id? && !admin_override }
  after_save :sync_client_allowed_genres, if: :client_id?
  after_destroy :sync_client_allowed_genres_on_destroy, if: :client_id?
  after_commit :reset_genre_registry_cache

  def to_registry_hash
    {
      ja: ja,
      host: Array(hosts),
      service_name: service_name.to_s,
      keywords: Array(keywords),
      strong_points: strong_points,
      images: Array(images),
      sub_categories: deep_symbolize(sub_categories || {})
    }.compact
  end

  def sub_categories_count
    (sub_categories || {}).size
  end

  def self.owner_client_id_for(key, host: nil, client: nil)
    return client.id if client&.id.present?
    return nil if key.blank?

    candidates = where(key: key.to_s).where.not(client_id: nil)
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

  def self.registered_key?(key)
    key.present? && exists?(key: key.to_s)
  end

  def sub_categories_for_form
    categories = sub_categories.is_a?(Hash) ? sub_categories : {}
    return [] if categories.blank?

    categories.map do |key, data|
      data = data.with_indifferent_access
      {
        key: key.to_s,
        name: data[:name],
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
    data = GenreRegistry::FALLBACK_GENRES[template_key.to_sym]
    return new unless data

    new(
      key: template_key.to_s,
      ja: data[:ja],
      service_name: data[:service_name],
      strong_points: data[:strong_points],
      hosts: Array(data[:host]),
      keywords: Array(data[:keywords]),
      images: Array(data[:images]),
      sub_categories: stringify_nested(data[:sub_categories] || {})
    )
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
    self.key = key.to_s.strip.downcase if key.present?
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
