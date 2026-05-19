require 'net/http'
require 'json'
require 'open-uri'
require 'securerandom'
require 'fileutils'

class FluxImageGeneratorService
  API_URL = 'https://fal.run/fal-ai/flux/schnell'

  def self.generate!(column)
    raise 'Column not found' if column.nil?

    prompt = build_prompt(column)

    puts "================ IMAGE PROMPT ================"
    puts prompt
    puts "============================================="

    image_url = request_image(prompt)

    raise 'Image URL not returned' if image_url.blank?

    save_image(column, image_url)
  end

  private

  def self.request_image(prompt)
    uri = URI(API_URL)

    request = Net::HTTP::Post.new(uri)

    request['Authorization'] = "Key #{ENV['FAL_API_KEY']}"
    request['Content-Type'] = 'application/json'

    request.body = {
      prompt: prompt,
      image_size: 'landscape_16_9',
      num_images: 1,
      enable_safety_checker: true,
      output_format: 'jpeg'
    }.to_json

    response = Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: true,
      read_timeout: 180
    ) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise "FAL API Error: #{response.code} #{response.body}"
    end

    json = JSON.parse(response.body)

    json.dig('images', 0, 'url')
  end

  def self.save_image(column, image_url)
    filename = "column_#{column.id}_#{SecureRandom.hex(8)}.jpg"

    tmp_dir = Rails.root.join('tmp', 'column_images')

    FileUtils.mkdir_p(tmp_dir)

    tmp_path = tmp_dir.join(filename)

    URI.open(image_url) do |image|
      File.binwrite(tmp_path, image.read)
    end

    File.open(tmp_path) do |file|
      column.file = file
      column.save!
    end

    tmp_path.to_s
  end

  def self.build_prompt(column)
    genre_key = column.genre.to_sym rescue nil

    genre = GenreRegistry::GENRES[genre_key] || {}

    genre_name = genre[:ja].to_s
    service_name = genre[:service_name].to_s
    strong_points = genre[:strong_points].to_s

    sub_category_key =
      if column.respond_to?(:sub_category)
        column.sub_category
      elsif column.respond_to?(:sub_genre)
        column.sub_genre
      else
        nil
      end

    service_profile =
      GenreRegistry.service_profile(
        genre_key,
        sub_category_key
      ).to_s

    keywords = Array(genre[:keywords]).join(', ')

    body_text = column.body.to_s
                      .gsub(/[#*\n\r]/, ' ')
                      .squish
                      .slice(0, 2000)

    description = column.description.to_s

    visual_direction = visual_direction_prompt(
      genre_key,
      sub_category_key
    )

    <<~PROMPT.squish
      Create a realistic and modern Japanese business website hero image.

      Article title:
      #{column.title}

      Article description:
      #{description}

      Article content summary:
      #{body_text}

      Industry:
      #{genre_name}

      Service name:
      #{service_name}

      SEO keywords:
      #{keywords}

      Service profile:
      #{service_profile}

      Brand strengths:
      #{strong_points}

      Visual direction:
      #{visual_direction}

      Image requirements:
      - realistic photography style
      - cinematic lighting
      - modern Japanese commercial atmosphere
      - authentic environment
      - premium business branding
      - highly detailed
      - natural composition
      - depth and realism
      - suitable for corporate blog thumbnail
      - suitable for landing page hero section
      - no text
      - no typography
      - no letters
      - no logo
      - no watermark
      - clean framing
      - natural colors
      - professional quality
      - wide landscape composition
      - 16:9 aspect ratio
    PROMPT
  end

  def self.visual_direction_prompt(category_key, sub_category_key = nil)
    category = GenreRegistry::GENRES[category_key.to_sym] rescue nil

    return default_visual_prompt if category.blank?

    sub_category =
      category[:sub_categories]&.dig(sub_category_key.to_sym) rescue nil

    profile_text =
      GenreRegistry.service_profile(
        category_key,
        sub_category_key
      ).to_s

    base_keywords = Array(category[:keywords]).join(', ')

    sub_keywords =
      Array(sub_category&.dig(:keywords)).join(', ')

    <<~TEXT.squish
      Visualize the actual business scene naturally and realistically.

      Industry keywords:
      #{base_keywords}

      Sub category keywords:
      #{sub_keywords}

      Business profile:
      #{profile_text}

      Focus on:
      - realistic Japanese business environments
      - people naturally working
      - operational scenes instead of abstract concepts
      - trustworthy commercial atmosphere
      - modern clean interiors or urban environments
      - authentic business workflow
      - realistic clothing and equipment
      - premium corporate branding feeling
      - documentary-style realism
    TEXT
  end

  def self.default_visual_prompt
    <<~TEXT.squish
      Modern Japanese business environment.
      Professional commercial atmosphere.
      Realistic people and workspace.
      Clean and trustworthy visual composition.
    TEXT
  end
end