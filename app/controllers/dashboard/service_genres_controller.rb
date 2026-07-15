class Dashboard::ServiceGenresController < ApplicationController
  before_action :authenticate_admin_or_client!
  before_action :set_service_genre, only: [:edit, :update, :destroy]
  before_action :authorize_service_genre!, only: [:edit, :update, :destroy]
  before_action :assign_fallback_templates, only: [:new, :create, :edit, :update]
  before_action :assign_sub_category_config, only: [:new, :create, :edit, :update]
  before_action :authorize_fallback_template!, only: [:new]

  layout "admin"

  def index
    @service_genres = service_genres_scope.order(:ja)
  end

  def new
    @service_genre = if params[:template].present?
                       ServiceGenre.from_fallback_template(params[:template])
                     else
                       ServiceGenre.new
                     end
    if client_signed_in? && !admin_signed_in?
      @service_genre.client = current_client
      personalize_template_hosts!(@service_genre)
    end
  end

  def create
    attrs, sub_category_error = service_genre_attributes
    @service_genre = ServiceGenre.new(attrs)

    if sub_category_error
      @service_genre.errors.add(:base, sub_category_error)
      render :new, status: :unprocessable_entity
    elsif unauthorized_genre_key?(@service_genre.key)
      @service_genre.errors.add(:base, "このジャンルキーは利用できません。")
      render :new, status: :unprocessable_entity
    elsif (limit_error = sub_category_limit_error(@service_genre.sub_categories, owner_client: @service_genre.client))
      @service_genre.errors.add(:base, limit_error)
      render :new, status: :unprocessable_entity
    elsif apply_service_genre_flags!(@service_genre) && @service_genre.save
      redirect_to dashboard_service_genres_path, notice: "サービス・ジャンルを作成しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs, sub_category_error = service_genre_attributes

    if sub_category_error
      @service_genre.errors.add(:base, sub_category_error)
      render :edit, status: :unprocessable_entity
    elsif unauthorized_genre_key?(attrs[:key], except: @service_genre.key)
      @service_genre.errors.add(:base, "このジャンルキーは利用できません。")
      render :edit, status: :unprocessable_entity
    elsif (limit_error = sub_category_limit_error(attrs[:sub_categories], owner_client: @service_genre.client))
      @service_genre.errors.add(:base, limit_error)
      render :edit, status: :unprocessable_entity
    elsif apply_service_genre_flags!(@service_genre) && @service_genre.update(attrs)
      redirect_to dashboard_service_genres_path, notice: "サービス・ジャンルを更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @service_genre.destroy
    redirect_to dashboard_service_genres_path, notice: "サービス・ジャンルを削除しました"
  end

  def suggest_sub_categories
    if (limit_error = sub_category_not_allowed_error)
      return render json: { success: false, error: limit_error }, status: :unprocessable_entity
    end

    result = SubCategorySuggestionService.call(
      key: params[:key],
      ja: params[:ja],
      service_name: params[:service_name],
      strong_points: params[:strong_points],
      keywords: params[:keywords],
      suggestion_count: params[:suggestion_count],
      max_count: sub_category_limit_for_ai
    )

    if result[:success]
      render json: { success: true, sub_categories: result[:sub_categories] }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  def quick_setup
    if sub_category_not_allowed_error
      return render json: { success: false, error: "スタンダードプランからご利用いただけます" }, status: :forbidden
    end

    result = GenreQuickSetupService.call(
      service_name: params[:service_name],
      strong_points: params[:strong_points],
      keywords: params[:keywords],
      keyword1: params[:keyword1],
      keyword2: params[:keyword2],
      sub_category_limit: sub_category_limit_for_ai
    )

    if result[:success]
      render json: { success: true, draft: result[:draft] }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  def quick_create
    if client_signed_in? && !current_client.can_add_genre?
      return render json: { success: false, error: current_client.plan_limit_message(:genre) }, status: :unprocessable_entity
    end

    result = GenreQuickSetupService.call(
      service_name: params[:service_name],
      strong_points: params[:strong_points],
      keywords: params[:keywords],
      keyword1: params[:keyword1],
      keyword2: params[:keyword2],
      sub_category_limit: sub_category_limit_for_ai
    )
    unless result[:success]
      return render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end

    draft = result[:draft]
    if unauthorized_genre_key?(draft[:key])
      return render json: { success: false, error: "このジャンルキーは利用できません。" }, status: :unprocessable_entity
    end

    sub_categories = sub_categories_hash_from_draft(draft[:sub_categories])
    if (limit_error = sub_category_limit_error(sub_categories, owner_client: quick_create_owner))
      return render json: { success: false, error: limit_error }, status: :unprocessable_entity
    end

    @service_genre = ServiceGenre.new(
      key: draft[:key],
      ja: draft[:ja],
      service_name: draft[:service_name],
      strong_points: draft[:strong_points],
      keywords: Array(draft[:keywords]),
      sub_categories: sub_categories,
      hosts: quick_create_hosts
    )
    @service_genre.client = quick_create_owner if quick_create_owner

    if apply_service_genre_flags!(@service_genre) && @service_genre.save
      render json: {
        success: true,
        genre: { key: @service_genre.key, ja: @service_genre.ja },
        sub_categories_count: @service_genre.sub_categories_count
      }
    else
      render json: { success: false, error: @service_genre.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  private

  def assign_sub_category_config
    @sub_category_config = sub_category_ui_config
  end

  def assign_fallback_templates
    @fallback_templates = if admin_signed_in?
                            GenreRegistry.fallback_templates_for
                          else
                            GenreRegistry.fallback_templates_for(client: current_client, host: request.host)
                          end
  end

  def authorize_fallback_template!
    return if params[:template].blank?
    return if admin_signed_in?
    return if @fallback_templates.key?(params[:template].to_sym)

    redirect_to new_dashboard_service_genre_path, alert: "このテンプレートは利用できません。"
  end

  def unauthorized_genre_key?(key, except: nil)
    return false if admin_signed_in?
    return false if key.blank?
    return false if except.present? && key.to_s == except.to_s
    return false if GenreRegistry.custom_genre_key_allowed_for_client?(key, client: current_client)

    !GenreRegistry.template_allowed_for_client?(key, client: current_client, host: request.host)
  end

  def service_genres_scope
    if admin_signed_in?
      ServiceGenre.includes(:client).all
    else
      ServiceGenre.where(client_id: current_client.id)
    end
  end

  def set_service_genre
    @service_genre = service_genres_scope.find(params[:id])
  end

  def authorize_service_genre!
    return if admin_signed_in?
    return if @service_genre.client_id == current_client.id

    redirect_to dashboard_service_genres_path, alert: "このサービス・ジャンルにはアクセスできません"
  end

  def service_genre_attributes
    permitted = params.require(:service_genre).permit(
      :key, :ja, :service_name, :strong_points, :client_id,
      :hosts_text, :keywords_text,
      sub_categories_items: [
        :key, :name, :target, :description,
        :features_text, :keywords_text, :price_hint, :area,
        :strengths, :industry_weakness
      ]
    )

    sub_categories, sub_category_error = build_sub_categories(permitted[:sub_categories_items])

    attrs = {
      key: permitted[:key],
      ja: permitted[:ja],
      service_name: permitted[:service_name],
      strong_points: permitted[:strong_points],
      hosts: split_list(permitted[:hosts_text]),
      keywords: split_list(permitted[:keywords_text]),
      sub_categories: sub_categories
    }

    if admin_signed_in?
      attrs[:client_id] = permitted[:client_id].presence
    elsif client_signed_in?
      attrs[:client_id] = current_client.id
      hosts = split_list(permitted[:hosts_text])
      hosts << normalize_host(request.host)
      hosts << normalize_host(current_client.domain) if current_client.domain.present?
      attrs[:hosts] = hosts.compact.uniq.reject(&:blank?)
    end

    [attrs, sub_category_error]
  end

  def build_sub_categories(items)
    return [{}, nil] if items.blank?

    result = {}
    keys_seen = []

    items.each do |item|
      item = item.to_unsafe_h.with_indifferent_access if item.respond_to?(:to_unsafe_h)
      next unless item.values.any? { |value| value.to_s.strip.present? }

      key = item[:key].to_s.strip.downcase

      if key.blank?
        return [{}, "中分類のキーを入力してください"]
      end

      unless key.match?(/\A[a-z0-9_]+\z/)
        return [{}, "中分類キー「#{key}」は英小文字・数字・アンダースコアのみ使用できます"]
      end

      if keys_seen.include?(key)
        return [{}, "中分類キー「#{key}」が重複しています"]
      end

      keys_seen << key

      if item[:name].to_s.strip.blank?
        return [{}, "中分類「#{key}」の名称を入力してください"]
      end

      result[key] = {
        "name" => item[:name].to_s.strip,
        "target" => item[:target].to_s.strip.presence,
        "description" => item[:description].to_s.strip.presence,
        "features" => split_list(item[:features_text]),
        "keywords" => split_list(item[:keywords_text]),
        "price_hint" => item[:price_hint].to_s.strip.presence,
        "area" => item[:area].to_s.strip.presence,
        "strengths" => item[:strengths].to_s.strip.presence,
        "industry_weakness" => item[:industry_weakness].to_s.strip.presence
      }.compact
    end

    [result, nil]
  end

  def split_list(text)
    text.to_s.split(/[\n,、]/).map(&:strip).reject(&:blank?)
  end

  def personalize_template_hosts!(service_genre)
    hosts = []
    hosts << normalize_host(current_client.domain) if current_client.domain.present?
    hosts << normalize_host(request.host)
    hosts.concat(Array(service_genre.hosts).map { |host| normalize_host(host) })
    service_genre.hosts = hosts.compact.uniq.reject(&:blank?)
  end

  def normalize_host(host)
    host.to_s.downcase.sub(/\Awww\./, "").sub(/:\d+\z/, "")
  end

  def apply_service_genre_flags!(service_genre)
    service_genre.admin_override = admin_signed_in?
    true
  end

  def sub_category_limit_for_ai
    return 1_000 if admin_signed_in?

    client_signed_in? ? current_client.max_sub_category_count : 0
  end

  def sub_category_not_allowed_error
    return nil if admin_signed_in?
    return nil unless client_signed_in?
    return nil if current_client.sub_categories_allowed?

    current_client.plan_limit_message(:sub_category)
  end

  def sub_category_limit_error(sub_categories, owner_client:)
    return nil if admin_signed_in?
    return nil unless owner_client

    categories = sub_categories.is_a?(Hash) ? sub_categories : {}
    limit = owner_client.max_sub_category_count
    return owner_client.plan_limit_message(:sub_category) if limit.zero? && categories.present?
    return owner_client.plan_limit_message(:sub_category) if categories.size > limit

    nil
  end

  def sub_categories_hash_from_draft(items)
    Array(items).each_with_object({}) do |item, result|
      item = item.with_indifferent_access
      key = item[:key].to_s.strip.downcase
      next if key.blank? || item[:name].to_s.strip.blank?

      result[key] = {
        "name" => item[:name].to_s.strip,
        "target" => item[:target].to_s.strip.presence,
        "description" => item[:description].to_s.strip.presence,
        "features" => split_list(item[:features_text]),
        "keywords" => split_list(item[:keywords_text]),
        "price_hint" => item[:price_hint].to_s.strip.presence,
        "area" => item[:area].to_s.strip.presence,
        "strengths" => item[:strengths].to_s.strip.presence,
        "industry_weakness" => item[:industry_weakness].to_s.strip.presence
      }.compact
    end
  end

  def quick_create_owner
    return nil if admin_signed_in?

    current_client if client_signed_in?
  end

  def quick_create_hosts
    hosts = []
    if client_signed_in?
      hosts << normalize_host(request.host)
      hosts << normalize_host(current_client.domain) if current_client.domain.present?
    end
    hosts.compact.uniq.reject(&:blank?)
  end
end
