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

  def pillar?
    article_type == "pillar"
  end

  def cluster?
    article_type == "cluster"
  end

  def cluster_full?
    return false unless pillar?
    return false if cluster_limit.blank?
    children.count >= cluster_limit
  end

  extend FriendlyId
  friendly_id :code, use: :slugged, slug_column: :code

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