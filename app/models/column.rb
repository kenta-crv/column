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

  ALREADY_GENERATED_NOTICE = "すでに記事が作成されています。再実行する場合、記事本文を削除してください".freeze

  def generated_body?
    body.to_s.strip.present?
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
  after_create :record_client_article_creation!

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
    GenreRegistry.service_profile(genre)
  end

  def category_images
    GenreRegistry.images(genre_key)
  end

  private

  def within_client_plan_limits
    return if client_id.blank?

    owner = client
    return unless owner

    if pillar?
      errors.add(:base, owner.plan_limit_message(:pillar)) unless owner.can_create_pillar?
    else
      errors.add(:base, owner.plan_limit_message(:child)) unless owner.can_create_child?
    end
  end

  def record_client_article_creation!
    return if client_id.blank?

    if pillar?
      client.record_pillar_creation!
    else
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