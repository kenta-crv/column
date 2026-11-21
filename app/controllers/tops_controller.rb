class TopsController < ApplicationController
  def index
  end

  def overseas_seo
    I18n.locale = :ja
  end

  def development
    I18n.locale = :ja
    @inquiry = DevelopmentInquiry.new
  end

  def create_development_inquiry
    I18n.locale = :ja
    @inquiry = DevelopmentInquiry.new(development_inquiry_params)

    if params[:company_website].present?
      redirect_to development_path(sent: 1, anchor: "consult")
      return
    end

    unless @inquiry.valid?
      render :development, status: :unprocessable_entity
      return
    end

    contract = Contract.new(
      company: @inquiry.company,
      name: @inquiry.name,
      email: @inquiry.email,
      tel: @inquiry.tel,
      service: @inquiry.system_type,
      message: @inquiry.to_message
    )

    unless contract.save(validate: false)
      @inquiry.errors.add(:base, "送信を保存できませんでした。時間をおいてもう一度お試しください。")
      render :development, status: :unprocessable_entity
      return
    end

    begin
      ContractMailer.received_email(contract).deliver_now
      ContractMailer.send_email(contract).deliver_now
    rescue StandardError => e
      Rails.logger.error("[DevelopmentInquiry] mail failed: #{e.class}: #{e.message}")
    end

    redirect_to development_path(sent: 1, anchor: "consult")
  end

  def privacy
    @legal_page = :privacy
    render :legal
  end

  def tos
    @legal_page = :tos
    render :legal
  end

  def specific
    @legal_page = :specific
    render :legal
  end

  private

  def development_inquiry_params
    params.fetch(:inquiry, {}).permit(
      :company, :name, :email, :tel, :system_type, :audience, :situation, :message
    )
  end
end

class DevelopmentInquiry
  include ActiveModel::Model

  SYSTEM_TYPES = [
    "顧客向けWebサービス",
    "予約・受付システム",
    "顧客・案件管理",
    "社内業務・管理画面",
    "既存Webシステムの改修",
    "まだ決めていない"
  ].freeze

  AUDIENCES = [
    "お客様",
    "社員",
    "お客様と社員の両方",
    "まだ決めていない"
  ].freeze

  SITUATIONS = [
    "まだアイデアの段階",
    "やりたいことは決まっている",
    "公開中のシステムがある"
  ].freeze

  ATTRIBUTES = {
    company: "会社名",
    name: "担当者名",
    email: "メールアドレス",
    tel: "電話番号",
    system_type: "作りたいシステム",
    audience: "主な利用者",
    situation: "今の状態",
    message: "開発してほしい内容"
  }.freeze

  attr_accessor(*ATTRIBUTES.keys)

  validates :company, :name, :email, :message, presence: { message: "を入力してください" }
  validates :system_type, :audience, :situation, presence: { message: "を選択してください" }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "の形式を確認してください" }, allow_blank: true
  validates :system_type, inclusion: { in: SYSTEM_TYPES, message: "を選択してください" }, allow_blank: true
  validates :audience, inclusion: { in: AUDIENCES, message: "を選択してください" }, allow_blank: true
  validates :situation, inclusion: { in: SITUATIONS, message: "を選択してください" }, allow_blank: true

  def self.human_attribute_name(attr, _options = {})
    ATTRIBUTES[attr.to_sym] || attr.to_s
  end

  def to_message
    [
      "作りたいシステム: #{system_type}",
      "主な利用者: #{audience}",
      "今の状態: #{situation}",
      "",
      message.to_s
    ].join("\n")
  end
end
