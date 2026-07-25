class Column < ApplicationRecord
  mount_uploader :file, ImagesUploader
  belongs_to :client, optional: true
  belongs_to :parent, class_name: "Column", optional: true
  has_many :children, class_name: "Column", foreign_key: :parent_id
  
  scope :pillars, -> { where(article_type: "pillar") }
  scope :clusters, -> { where(article_type: "cluster") }
  scope :without_image_file, -> { where("file IS NULL OR file = ''") }
  scope :missing_generated_image, -> {
    where("body IS NOT NULL AND TRIM(body) != ''").merge(without_image_file)
  }
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
  scope :without_generated_body, -> { where("body IS NULL OR TRIM(body) = ''") }
  scope :with_generated_body, -> { where("body IS NOT NULL AND TRIM(body) != ''") }
  scope :published, -> { where.not(published_at: nil) }
  scope :pending_review, -> { with_generated_body.where(published_at: nil) }

  ALREADY_GENERATED_NOTICE = "すでに記事が作成されています。再実行する場合、記事本文を削除してください".freeze

  def generated_body?
    body.to_s.strip.present?
  end

  # 本文生成が完了しても、レビュー・手動公開を行うまでは一般公開されない。
  def published?
    published_at.present?
  end

  def publicly_visible?
    generated_body? && published?
  end

  def publish!
    return false unless generated_body?

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
    { title: title, keyword: keyword, description: description }
  end

  def approved?
    status == "approved"
  end

  before_validation :assign_random_file, on: :create

  def genre_key
    GenreRegistry.from_ja(genre)
  end

  def genre_label
    GenreRegistry.to_ja(genre)
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

  def assign_random_file
    return if file.present?

    key = genre_key
    return if key.nil?

    images = GenreRegistry.images(key)
    return if images.blank?

    file_name = images.sample
    file_path = Rails.root.join("app/assets/images", file_name)

    if File.exist?(file_path)
      self.file = Rack::Test::UploadedFile.new(file_path, "image/jpeg")
    end
  end
end