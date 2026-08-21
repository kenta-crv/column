class Column < ApplicationRecord
  DEFAULT_STOCK_IMAGE = "hero-bg.webp"

  mount_uploader :file, ImagesUploader
  belongs_to :client, optional: true
  belongs_to :parent, class_name: "Column", optional: true
  has_many :children, class_name: "Column", foreign_key: :parent_id
  before_validation :normalize_language_value
  before_validation :normalize_generation_mode_for_language
  
  scope :pillars, -> { where(article_type: "pillar") }
  scope :clusters, -> { where(article_type: "cluster") }
  scope :without_image_file, -> { where("file IS NULL OR file = ''") }
  scope :with_article_type_filter, ->(article_type) {
    case article_type.to_s
    when "pillar"
      where(article_type: "pillar")
    when "child"
      where(article_type: %w[child cluster])
    when ""
      all
    else
      where(article_type: article_type)
    end
  }

  def self.reconcile_broken_image_file_refs!(scope)
    scope.where.not(file: [nil, ""]).find_each do |column|
      next if column.image_file_stored?
      next if column.repair_image_filename_from_disk!

      Rails.logger.warn "[Column #{column.id}] clearing broken image file reference"
      column.update_column(:file, nil)
    end
  end

  def image_file_stored?
    return false if self[:file].blank?

    path = file.path
    path.present? && File.exist?(path)
  rescue StandardError
    false
  end

  # uploads 上の実ファイルと DB の file 名がズレている場合に修復する（webp↔jpg 等）
  def repair_image_filename_from_disk!
    dir = Rails.root.join("public", "uploads", "column", "file", id.to_s)
    return false unless dir.directory?

    files = dir.children.select { |p| p.file? && p.extname.to_s.match?(/\A\.(webp|jpe?g|png|gif)\z/i) }
    return false if files.empty?

    current = self[:file].to_s
    return true if current.present? && dir.join(current).file?

    preferred_base = current.present? ? File.basename(current, ".*") : nil
    chosen =
      files.find { |f| preferred_base.present? && f.basename(".*").to_s == preferred_base && f.extname.downcase == ".webp" } ||
      files.find { |f| preferred_base.present? && f.basename(".*").to_s == preferred_base } ||
      files.find { |f| f.extname.downcase == ".webp" } ||
      files.max_by(&:mtime)

    return false if chosen.blank?

    update_column(:file, chosen.basename.to_s)
    true
  rescue StandardError => e
    Rails.logger.warn "[Column #{id}] repair_image_filename_from_disk! failed: #{e.message}"
    false
  end
  # TRIMは全文スキャンが重くなるため、空判定は IS NULL / octet_length に統一
  scope :without_generated_body, -> { where("body IS NULL OR octet_length(body) = 0") }
  scope :with_generated_body, -> { where("body IS NOT NULL AND octet_length(body) > 0") }
  scope :published, -> { where.not(published_at: nil) }
  scope :pending_review, -> { with_generated_body.where(published_at: nil) }
  # 画像一括生成・サイドバーバッジ用。下書き（本文なし）や公開済みは含めない。
  scope :pending_review_missing_image, -> {
    pending_review.merge(without_image_file)
  }

  # 一覧用: body 全文を転送せず、有無フラグだけ付与する
  LIST_SELECT_COLUMNS = %w[
    id title description file code genre sub_genre article_type parent_id
    published_at created_at updated_at quality_score evaluation_metrics
    generation_mode generation_status status client_id keyword language
  ].freeze

  scope :with_list_attributes, -> {
    quoted = LIST_SELECT_COLUMNS.map { |column| "#{table_name}.#{column}" }
    select(
      *(quoted + [
        Arel.sql(
          "CASE WHEN #{table_name}.body IS NULL OR octet_length(#{table_name}.body) = 0 " \
          "THEN FALSE ELSE TRUE END AS body_present"
        )
      ])
    )
  }

  ALREADY_GENERATED_NOTICE = "すでに記事が作成されています。再実行する場合、記事本文を削除してください".freeze

  # 公開UIで選べる生成スタイル（note/qiita/zenn は社内転用向け・コンソール等で設定）
  PUBLIC_GENERATION_MODES = %w[default comparison recommendation].freeze
  ALL_GENERATION_MODES = %w[default comparison recommendation note qiita zenn].freeze
  INTERNAL_GENERATION_MODES = %w[note qiita zenn].freeze
  LANGUAGES = %w[ja en].freeze
  DEFAULT_LANGUAGE = "ja"

  scope :for_language, ->(lang) { where(language: normalize_language(lang)) }
  scope :for_ui_locale, ->(locale = I18n.locale) { for_language(locale) }

  def self.normalize_generation_mode(mode)
    value = mode.to_s
    ALL_GENERATION_MODES.include?(value) ? value : "default"
  end

  def self.normalize_generation_mode_for(mode, language: nil)
    normalized = normalize_generation_mode(mode)
    return "default" if english_language?(language) && INTERNAL_GENERATION_MODES.include?(normalized)

    normalized
  end

  def self.normalize_language(value)
    language = value.to_s
    LANGUAGES.include?(language) ? language : DEFAULT_LANGUAGE
  end

  def self.english_language?(value)
    normalize_language(value) == "en"
  end

  def english_article?
    self.class.english_language?(language_value)
  end

  def assign_stock_image_if_missing!
    assign_random_file
  end

  def self.attributes_for_child_generation(parent)
    parent_language = parent&.has_attribute?(:language) ? parent[:language] : nil
    {
      generation_mode: normalize_generation_mode_for(parent&.generation_mode, language: parent_language),
      prompt: parent&.prompt,
      language: normalize_language(parent_language)
    }
  end

  def generated_body?
    if has_attribute?(:body_present)
      ActiveModel::Type::Boolean.new.cast(self[:body_present])
    elsif has_attribute?(:body)
      body.to_s.strip.present?
    else
      self.class.where(id: id).merge(self.class.with_generated_body).exists?
    end
  end

  # 本文生成が完了したら公開可能。publish! で一般公開される。
  def published?
    published_at.present?
  end

  def publicly_visible?
    generated_body? && published?
  end

  def publish!
    return false unless generated_body?
    return true if published?

    update!(published_at: Time.current)
  end

  def unpublish!
    update!(published_at: nil)
  end

  def pillar?
    article_type == "pillar"
  end

  def cluster?
    article_type == "cluster"
  end

  def child?
    %w[child cluster].include?(article_type)
  end

  def cluster_full?
    return false unless pillar?
    return false if cluster_limit.blank?
    children.count >= cluster_limit
  end

  extend FriendlyId
  friendly_id :code, use: :slugged, slug_column: :code

  validate :within_client_plan_limits, on: :create
  validate :within_client_plan_limits_on_update, on: :update
  after_create :record_client_article_creation!

  WEBHOOK_RELEVANT_ATTRIBUTES = %w[title body description genre sub_genre code keyword status article_type].freeze

  after_commit :notify_webhook_on_create, on: :create
  after_commit :notify_webhook_on_update, on: :update
  after_commit :notify_webhook_on_destroy, on: :destroy

  def should_generate_new_friendly_id?
    code_changed? || super
  end

  def to_meta_tags
    {
      title: title,
      keyword: keyword,
      description: description.presence || title
    }
  end

  # 同一ジャンル内で、別ピラー配下（＝別クラスター）の公開記事を返す。
  # 似たタイトルは除外し、同じサブジャンル・キーワード重なりを優先する。
  def self.cross_cluster_related_to(column, limit: 5)
    return [] if column.blank? || limit.to_i <= 0

    resolved = GenreRegistry.resolve_key(column.genre, client: column.client) || column.genre
    genre_values = GenreRegistry.equivalent_keys(resolved)
    ja = GenreRegistry.to_ja(resolved, client: column.client)
    genre_values = (genre_values + [column.genre.to_s, ja]).compact.map(&:to_s).uniq.reject(&:blank?)

    scope = published.with_generated_body
                     .where.not(id: column.id)
                     .where.not(code: [nil, ""])
                     .where(genre: genre_values)
                     .for_language(column.language)

    scope =
      if column.client_id.present?
        scope.where(client_id: column.client_id)
      else
        scope.where(client_id: nil)
      end

    exclude_ids = [column.id]
    if column.pillar?
      exclude_ids.concat(column.children.limit(200).pluck(:id))
    elsif column.parent_id.present?
      exclude_ids << column.parent_id
      exclude_ids.concat(where(parent_id: column.parent_id).limit(200).pluck(:id))
    end
    scope = scope.where.not(id: exclude_ids.uniq)

    candidates = scope.with_list_attributes.order(published_at: :desc).limit(60).to_a
    return [] if candidates.empty?

    own_sub = column.sub_genre.to_s
    own_keywords = related_keyword_tokens(column)
    scored = candidates.map do |c|
      score = 0
      score += 50 if own_sub.present? && c.sub_genre.to_s == own_sub
      score += 20 if c.pillar?
      score += 15 if c.description.to_s.strip.present? && c.description.to_s.strip != c.title.to_s.strip
      score += 10 * (related_keyword_tokens(c) & own_keywords).size
      # 新しすぎる一括公開だけに偏らないよう、少しだけ新しいものを優遇
      age_days = ((Time.current - (c.published_at || c.updated_at)).to_i / 86_400)
      score += 8 if age_days <= 30
      score += 4 if age_days <= 90
      score -= 30 if titles_too_similar?(column.title, c.title)
      [score, c]
    end

    scored.sort_by! { |score, c| [-score, -(c.published_at || c.updated_at).to_i] }

    picked = []
    scored.each do |_score, c|
      next if picked.any? { |p| titles_too_similar?(p.title, c.title) }

      picked << c
      break if picked.size >= limit
    end
    picked
  rescue StandardError => e
    Rails.logger.warn("[Column.cross_cluster_related_to] #{e.class}: #{e.message}")
    []
  end

  def self.related_siblings_for(column, limit: 5)
    return [] if column.blank? || column.parent_id.blank? || limit.to_i <= 0

    candidates = published.with_generated_body
                          .with_list_attributes
                          .where(parent_id: column.parent_id)
                          .where.not(id: column.id)
                          .where.not(code: [nil, ""])
                          .for_language(column.language)
                          .order(published_at: :desc)
                          .limit(40)
                          .to_a

    picked = []
    candidates.each do |c|
      next if picked.any? { |p| titles_too_similar?(p.title, c.title) }

      picked << c
      break if picked.size >= limit
    end
    picked
  end

  def self.related_keyword_tokens(column)
    raw = [column.keyword, column.title, column.sub_genre].compact.join(" ")
    raw.downcase.scan(/[a-z0-9一-龥ぁ-んァ-ヶー]{2,}/).uniq.first(12)
  end

  def self.titles_too_similar?(a, b)
    na = normalize_related_title(a)
    nb = normalize_related_title(b)
    return false if na.blank? || nb.blank?
    return true if na == nb
    return true if na.include?(nb) || nb.include?(na)

    prefix = na.chars.zip(nb.chars).take_while { |x, y| x == y }.size
    prefix >= 14
  end

  def self.normalize_related_title(title)
    title.to_s.downcase.gsub(/[\s　\[\]【】「」『』（）()：:・\-_|]/, "")
  end
  private_class_method :related_keyword_tokens, :titles_too_similar?, :normalize_related_title

  def approved?
    status == "approved"
  end

  before_validation :normalize_genre_key

  def genre_key
    GenreRegistry.resolve_key(genre, client: client).presence || GenreRegistry.from_ja(genre)
  end

  def genre_label(locale: I18n.locale)
    GenreRegistry.label_for(genre, client: client, locale: locale)
  end

  def service_profile
    GenreRegistry.service_profile(genre, sub_genre, client: client)
  end

  def category_images
    GenreRegistry.images(genre_key)
  end

  def webhook_payload
    {
      id: id,
      title: title,
      body: body,
      description: description,
      genre: genre,
      sub_genre: sub_genre,
      code: code,
      keyword: keyword,
      language: language,
      status: status,
      article_type: article_type,
      published_at: published_at,
      updated_at: updated_at
    }
  end

  private

  def notify_webhook_on_create
    return if client_id.blank?
    return unless published?

    DeliverArticleWebhookJob.perform_later(client_id, "created", webhook_payload)
  end

  def notify_webhook_on_update
    return if client_id.blank?

    became_published = saved_change_to_published_at? && published_at.present? && published_at_before_last_save.blank?
    became_unpublished = saved_change_to_published_at? && published_at.blank? && published_at_before_last_save.present?

    if became_published
      DeliverArticleWebhookJob.perform_later(client_id, "created", webhook_payload)
    elsif became_unpublished
      DeliverArticleWebhookJob.perform_later(client_id, "deleted", webhook_payload)
    elsif published? && WEBHOOK_RELEVANT_ATTRIBUTES.any? { |attr| saved_change_to_attribute?(attr) }
      DeliverArticleWebhookJob.perform_later(client_id, "updated", webhook_payload)
    end
  end

  def notify_webhook_on_destroy
    return if client_id.blank?
    return unless published?

    DeliverArticleWebhookJob.perform_later(client_id, "deleted", webhook_payload)
  end

  def language_value
    has_attribute?(:language) ? self[:language] : DEFAULT_LANGUAGE
  end

  def normalize_language_value
    return unless has_attribute?(:language)

    self.language = self.class.normalize_language(self[:language])
  end

  def normalize_generation_mode_for_language
    self.generation_mode = self.class.normalize_generation_mode_for(generation_mode, language: language_value)
  end

  def within_client_plan_limits
    return if client_id.blank?

    owner = client
    return unless owner

    if counts_as_pillar_slot?
      errors.add(:base, owner.plan_limit_message(:pillar)) unless owner.can_create_pillar?(excluding: self)
    elsif counts_as_child_slot?
      errors.add(:base, owner.plan_limit_message(:child)) unless owner.can_create_child?(excluding: self)
    end
  end

  def within_client_plan_limits_on_update
    return if client_id.blank?

    owner = client
    return unless owner
    return unless will_save_change_to_article_type? || will_save_change_to_parent_id?

    was_pillar_slot = pillar_slot?(article_type_in_database, parent_id_in_database)
    will_be_pillar_slot = counts_as_pillar_slot?

    if !was_pillar_slot && will_be_pillar_slot
      errors.add(:base, owner.plan_limit_message(:pillar)) unless owner.can_create_pillar?(excluding: self)
    end

    was_child_slot = child_slot?(article_type_in_database, parent_id_in_database)
    will_be_child_slot = counts_as_child_slot?

    if !was_child_slot && will_be_child_slot
      errors.add(:base, owner.plan_limit_message(:child)) unless owner.can_create_child?(excluding: self)
    end
  end

  def counts_as_pillar_slot?
    return false if parent_id.present?
    return false if child?

    true
  end

  def counts_as_child_slot?
    child? || parent_id.present?
  end

  def pillar_slot?(type, parent_id)
    return false if parent_id.present?
    return false if Client::CHILD_ARTICLE_TYPES.include?(type)

    true
  end

  def child_slot?(type, parent_id)
    Client::CHILD_ARTICLE_TYPES.include?(type) || parent_id.present?
  end

  def record_client_article_creation!
    return if client_id.blank?

    if counts_as_pillar_slot?
      client.record_pillar_creation!
    elsif counts_as_child_slot?
      client.record_child_creation!
    end
  end

  def normalize_genre_key
    return if genre.blank?

    resolved = GenreRegistry.resolve_key(genre, client: client)
    self.genre = resolved if resolved.present?
  end

  def assign_random_file
    return if read_attribute(:file).present?

    file_path = first_existing_stock_image_path
    return if file_path.blank?

    File.open(file_path) do |io|
      self.file = io
      save! if persisted?
    end
  end

  def first_existing_stock_image_path
    stock_image_candidate_names.each do |name|
      path = Rails.root.join("app/assets/images", name)
      return path if File.exist?(path)
    end
    nil
  end

  def stock_image_candidate_names
    key = genre_key
    names = []
    names.concat(Array(GenreRegistry.images(key))) if key.present?
    names.concat(Array(GenreRegistry::FALLBACK_GENRES.dig(key&.to_sym, :images))) if key.present?
    names << DEFAULT_STOCK_IMAGE
    names.flatten.compact.map(&:to_s).reject(&:blank?).uniq
  end
end