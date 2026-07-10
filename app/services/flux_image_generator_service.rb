require 'net/http'
require 'json'
require 'open-uri'
require 'securerandom'
require 'fileutils'

class FluxImageGeneratorService
  API_URL = 'https://fal.run/fal-ai/flux/schnell'

  def self.generate!(column)
    raise 'Column not found' if column.nil?

    if column.file.present?
      Rails.logger.info "[FluxImageGeneration] column #{column.id}: image already exists, skip"
      return false
    end

    unless ENV['FAL_API_KEY'].present?
      raise "FAL_API_KEY is not configured"
    end

    prompt = build_prompt(column)

    Rails.logger.info "[FluxImageGeneration] column #{column.id}: requesting image"
    puts "================ IMAGE PROMPT ================"
    puts prompt
    puts "============================================="

    image_url = request_image(prompt)

    raise 'Image URL not returned' if image_url.blank?

    save_image(column, image_url)
    true
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

    column.client&.record_image_generation!

    tmp_path.to_s
  end

  def self.build_prompt(column)
    genre_info = GenreRegistry::GENRES[column.genre.to_sym] rescue nil

    genre_name = genre_info&.dig(:ja).to_s
    service_name = genre_info&.dig(:service_name).to_s
    strong_points = genre_info&.dig(:strong_points).to_s

    body_text = column.body.to_s
                      .gsub(/[#*\n\r]/, ' ')
                      .squish
                      .slice(0, 1500)

    description = column.description.to_s

    genre_prompt = genre_specific_prompt(column.genre)

    <<~PROMPT.squish
      Create a realistic modern Japanese business website hero image.

      Article title:
      #{column.title}

      Article description:
      #{description}

      Article content summary:
      #{body_text}

      Industry:
      #{genre_name}

      Service:
      #{service_name}

      Service strengths:
      #{strong_points}

      Visual direction:
      #{genre_prompt}

      Requirements:
      - realistic photo style
      - cinematic lighting
      - Japanese environment
      - professional business atmosphere
      - modern composition
      - highly detailed
      - clean design
      - no text
      - no letters
      - no watermark
      - suitable for blog thumbnail
      - suitable for hero section
      - natural colors
      - high quality
      - 16:9 composition
    PROMPT
  end

  def self.genre_specific_prompt(genre)
    case genre.to_s

    when 'vender'
      <<~TEXT
        Japanese vending machine business.
        Tourist area or hotel environment.
        Modern vending machines.
        Commercial facility atmosphere.
        Passive income business concept.
        Bright clean environment.
        People walking naturally.
      TEXT

    when 'routine_cleaning'
      <<~TEXT
        Professional Japanese cleaning staff.
        Modern office or commercial building.
        Clean atmosphere.
        Hygiene and cleanliness.
        Professional uniforms.
        Bright interior lighting.
      TEXT

    when 'patrol_cleaning'
      <<~TEXT
        Apartment or building maintenance.
        Japanese property management.
        Exterior cleaning.
        Hallway cleaning.
        Clean apartment environment.
      TEXT

    when 'special_cleaning'
      <<~TEXT
        Professional floor cleaning.
        Commercial building maintenance.
        Polishing machines.
        Modern facility cleaning.
      TEXT

    when 'restoration'
      <<~TEXT
        Empty apartment restoration.
        Clean renovated room.
        Japanese housing interior.
        Professional restoration work.
      TEXT

    when 'cargo'
      <<~TEXT
        Japanese delivery driver.
        Logistics business.
        Parcel delivery.
        Urban transportation.
        Amazon style delivery atmosphere.
      TEXT

    when 'app'
      <<~TEXT
        Modern SaaS dashboard.
        AI sales automation.
        Business analytics.
        Professional office environment.
        Digital transformation concept.
        Blue technology atmosphere.
      TEXT

    when 'meetia'
      <<~TEXT
        Futuristic AI meeting.
        AI avatar assistant.
        Online business negotiation.
        Modern digital interface.
        Advanced technology atmosphere.
        Blue neon lighting.
      TEXT

    when 'housekeeping'
      <<~TEXT
        Japanese housekeeping service.
        Clean modern home.
        Organized living environment.
        Friendly professional staff.
      TEXT

    when 'pest'
      <<~TEXT
        Professional pest control.
        Safe home environment.
        Inspection service.
        Clean residential atmosphere.
      TEXT

    else
      <<~TEXT
        Modern Japanese business concept.
        Professional commercial atmosphere.
        Clean and realistic environment.
      TEXT
    end
  end
end
