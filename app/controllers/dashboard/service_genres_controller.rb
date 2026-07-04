class Dashboard::ServiceGenresController < ApplicationController
  before_action :authenticate_admin_or_client!
  before_action :set_service_genre, only: [:edit, :update, :destroy]
  before_action :authorize_service_genre!, only: [:edit, :update, :destroy]

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
    @service_genre.client = current_client if client_signed_in?
    @fallback_templates = GenreRegistry::FALLBACK_GENRES
  end

  def create
    attrs, sub_category_error = service_genre_attributes
    @service_genre = ServiceGenre.new(attrs)
    @fallback_templates = GenreRegistry::FALLBACK_GENRES

    if sub_category_error
      @service_genre.errors.add(:base, sub_category_error)
      render :new, status: :unprocessable_entity
    elsif @service_genre.save
      redirect_to dashboard_service_genres_path, notice: "サービス・ジャンルを作成しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @fallback_templates = GenreRegistry::FALLBACK_GENRES
  end

  def update
    attrs, sub_category_error = service_genre_attributes
    @fallback_templates = GenreRegistry::FALLBACK_GENRES

    if sub_category_error
      @service_genre.errors.add(:base, sub_category_error)
      render :edit, status: :unprocessable_entity
    elsif @service_genre.update(attrs)
      redirect_to dashboard_service_genres_path, notice: "サービス・ジャンルを更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @service_genre.destroy
    redirect_to dashboard_service_genres_path, notice: "サービス・ジャンルを削除しました"
  end

  private

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
      :hosts_text, :keywords_text, :images_text,
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
      images: split_list(permitted[:images_text]),
      sub_categories: sub_categories
    }

    if client_signed_in?
      attrs[:client_id] = current_client.id
    elsif admin_signed_in?
      attrs[:client_id] = permitted[:client_id].presence
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
end
