class ImagesUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick

  storage :file

  # 表示用に十分な解像度へ縮小（長辺1200px）
  process resize_to_limit: [1200, 1200]
  process :convert_to_webp

  def store_dir
    "uploads/#{model.class.to_s.underscore}/#{mounted_as}/#{model.id}"
  end

  def extension_allowlist
    %w[jpg jpeg gif png webp]
  end

  def content_type_allowlist
    [%r{image/}]
  end

  def filename
    return if original_filename.blank?

    base = File.basename(original_filename, ".*")
    "#{base}.webp"
  end

  private

  def convert_to_webp
    manipulate! do |img|
      img.format("webp")
      img.quality(82)
      img
    end
  end
end
