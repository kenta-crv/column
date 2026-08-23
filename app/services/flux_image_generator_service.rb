require 'net/http'
require 'json'
require 'open-uri'
require 'securerandom'
require 'fileutils'

class FluxImageGeneratorService
  API_URL = 'https://fal.run/fal-ai/flux/schnell'
  GPT_API_URL = 'https://api.openai.com/v1/chat/completions'

  # Flux は negative prompt 非対応のため、文字なしを positive 表現で強調する
  TEXT_FREE_REQUIREMENTS = <<~TEXT.squish
    Pure photography with absolutely no readable content anywhere in the frame.
    No text, no letters, no numbers, no logos, no captions, no subtitles,
    no signage, no labels, no watermarks, no UI elements, no screens showing words,
    no books or documents with visible writing, no banners, no typography of any kind,
    no Chinese characters, no Japanese characters, no alphabet characters.
    Blank surfaces, plain walls, and unmarked objects only.
  TEXT

  FLUX_FILENAME_RE = /\Acolumn_\d+_[0-9a-f]{16}\.(webp|jpe?g)\z/i

  def self.already_generated?(column)
    column.present? && stored_filename(column).match?(FLUX_FILENAME_RE)
  end

  def self.stored_filename(column)
    column.read_attribute(:file).to_s
  end

  def self.generate!(column)
    raise 'Column not found' if column.nil?

    if already_generated?(column)
      Rails.logger.info "[FluxImageGeneration] column #{column.id}: flux image already exists, skip"
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
      # jpegで受け取り、CarrierWave側でWebP+縮小する
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

    # Uploader が WebP 変換・長辺1200px 縮小を担当
    File.open(tmp_path) do |file|
      column.file = file
      column.save!
    end

    column.client&.record_image_generation!

    tmp_path.to_s
  ensure
    FileUtils.rm_f(tmp_path) if defined?(tmp_path) && tmp_path && File.exist?(tmp_path)
  end

  def self.build_prompt(column)
    scene = visual_scene_description(column)

    <<~PROMPT.squish
      Photorealistic hero image for a #{column.try(:english_article?) ? 'English-language' : 'Japanese'} business blog article.
      Scene: #{scene}
      Style: cinematic natural lighting, professional atmosphere, modern composition,
      highly detailed, clean design, natural colors, high quality, 16:9 landscape.
      #{TEXT_FREE_REQUIREMENTS}
    PROMPT
  end

  def self.visual_scene_description(column)
    gpt_scene = request_visual_scene_from_gpt(column)
    return gpt_scene if gpt_scene.present?

    genre_specific_prompt(column.genre).squish
  end

  def self.request_visual_scene_from_gpt(column)
    api_key = ENV['GPT_API_KEY']
    return nil unless api_key.present?

    genre_info = GenreRegistry.genre_entry(column.genre)
    industry = genre_info&.dig(:ja).to_s

    instruction = <<~PROMPT
      記事テーマに合った「写真の被写体・構図・雰囲気」だけを英語1段落で出力してください。

      【記事の参考情報（画像内に表示してはいけない）】
      タイトル: #{column.title}
      キーワード: #{column.keyword}
      業種: #{industry}

      【厳守ルール】
      - 出力は英語の視覚描写のみ（1段落、120語以内）
      - 画像内に表示する文字・単語・看板・UIテキストは一切含めない
      - dashboard, screen, monitor, sign, banner, label, document, book など文字が写りやすい被写体は使わない
      - 人物・建物・道具・風景など、文字のないリアルなシーンを描写する
      - 説明文や箇条書きは禁止。描写文のみ出力
    PROMPT

    response = call_gpt_api(api_key, instruction)
    content = response&.dig('choices', 0, 'message', 'content')&.strip
    content.presence
  rescue => e
    Rails.logger.warn "[FluxImageGeneration] visual scene GPT fallback: #{e.message}"
    nil
  end

  def self.call_gpt_api(api_key, prompt)
    uri = URI(GPT_API_URL)
    req = Net::HTTP::Post.new(uri)
    req['Content-Type'] = 'application/json'
    req['Authorization'] = "Bearer #{api_key}"
    req.body = GptGenerationLocale.chat_completions_payload(
      model: "gpt-5.4-nano",
      messages: [
        {
          role: "system",
          content: "You write image-generation prompts describing scenes only. Never include any words that should appear inside the image."
        },
        { role: "user", content: prompt }
      ],
      temperature: 0.4
    ).to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 60) do |http|
      http.request(req)
    end

    return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)

    Rails.logger.warn "[FluxImageGeneration] GPT error: #{res.code} #{res.body}"
    nil
  rescue => e
    Rails.logger.warn "[FluxImageGeneration] GPT exception: #{e.message}"
    nil
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
        Professional team collaborating in a bright modern office.
        Laptop lids closed or angled away from camera.
        Minimalist workspace with plain walls and soft blue ambient light.
        Business technology atmosphere without visible screens or devices showing content.
      TEXT

    when 'meetia', 'ai_sales_agent'
      <<~TEXT
        Two business professionals in a sleek conference room with frosted glass walls.
        Soft blue ambient lighting, empty whiteboard, no visible screens.
        Professional negotiation atmosphere in a clean futuristic interior.
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
