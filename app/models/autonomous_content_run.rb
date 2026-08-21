class AutonomousContentRun < ApplicationRecord
  STATUSES = %w[
    queued
    generating_pillar
    generating_child_titles
    awaiting_child_title_approval
    generating_children
    completed
    failed
    paused
  ].freeze

  MIN_CLUSTER_LIMIT = 1
  MAX_CLUSTER_LIMIT = 25
  DEFAULT_CLUSTER_LIMIT = 15

  belongs_to :client, optional: true
  belongs_to :pillar_column, class_name: "Column", optional: true

  validates :title, presence: true
  validates :genre, presence: true
  validates :cluster_limit, numericality: { only_integer: true, in: MIN_CLUSTER_LIMIT..MAX_CLUSTER_LIMIT }
  validates :status, inclusion: { in: STATUSES }

  before_validation :normalize_genre_key
  before_validation :normalize_language_value

  scope :recent, -> { order(created_at: :desc) }

  STALE_RUN_AFTER = 30.minutes

  def self.recover_stale_runs!
    where(status: %w[queued generating_pillar generating_child_titles generating_children])
      .where("updated_at < ?", STALE_RUN_AFTER.ago)
      .find_each do |run|
        if run.pillar_column&.generation_status == "generating"
          next
        end
        if run.child_columns.where(generation_status: "generating").exists?
          next
        end

        run.mark_failed!("処理がタイムアウトしました。再度お試しください。")
      end
  end

  def self.start!(title:, genre:, cluster_limit:, client: nil, pause_for_approval_at: nil, notify_on: nil, language: nil)
    settings = client&.autonomous_settings_with_defaults || Client::DEFAULT_AUTONOMOUS_SETTINGS
    limit = cluster_limit.to_i
    limit = DEFAULT_CLUSTER_LIMIT if limit <= 0
    limit = [[limit, MIN_CLUSTER_LIMIT].max, MAX_CLUSTER_LIMIT].min
    article_language = Column.normalize_language(language)

    run = create!(
      client: client,
      title: title.strip,
      genre: genre,
      cluster_limit: limit,
      language: article_language,
      status: "queued",
      pause_for_approval_at: pause_for_approval_at.nil? ? settings["pause_for_approval_at"] : pause_for_approval_at,
      notify_on: notify_on.nil? ? settings["notify_on"] : notify_on
    )

    AdvanceAutonomousRunJob.perform_later(run.id)
    run
  end

  def self.advance_after_column_generated!(run_id, column_id)
    run = find_by(id: run_id)
    return unless run

    column = Column.find_by(id: column_id)
    return unless column

    run.with_lock do
      run.reload
      return if run.status.in?(%w[completed failed paused])

      if run.pillar_column_id == column.id
        unless column.body.present?
          run.mark_failed!("親記事の生成に失敗しました")
          return
        end
        run.generate_child_titles!
      elsif column.parent_id == run.pillar_column_id
        run.touch
        run.advance_child_generation!
      end
    end
  end

  def notify_on_list
    Array(notify_on)
  end

  def pause_for_child_titles?
    pause_for_approval_at == "child_titles"
  end

  def status_label
    I18n.t("drafity.dashboard.autonomous.statuses.#{status}", default: status.to_s)
  end

  def child_columns
    return Column.none unless pillar_column_id.present?

    pillar_column.children.order(:id)
  end

  def pending_child_columns
    child_columns
      .merge(Column.without_generated_body)
      .where.not(generation_status: %w[failed generating])
      .where.not(status: "error")
  end

  def completed_child_count
    child_columns.merge(Column.with_generated_body).where(generation_status: "completed").count
  end

  def admin_run?
    client_id.blank?
  end

  def plan_limited?
    client.present?
  end

  def start_pillar_generation!
    with_lock do
      reload
      return unless status == "queued"

      if plan_limited? && !client.can_create_pillar?
        mark_paused!(client.plan_limit_message(:pillar))
        return
      end

      pillar = Column.create!(
        title: title,
        article_type: "pillar",
        genre: genre,
        status: "draft",
        cluster_limit: cluster_limit,
        client_id: client_id,
        language: Column.normalize_language(language)
      )

      update!(pillar_column_id: pillar.id, status: "generating_pillar")
      GenerateColumnBodyJob.perform_later_for_autonomous(pillar.id, autonomous_run_id: id)
    end
  rescue => e
    mark_failed!(e.message)
    raise
  end

  def generate_child_titles!
    reload
    return unless status == "generating_pillar"
    return mark_failed!("親記事が見つかりません") unless pillar_column

    update!(status: "generating_child_titles")

    remaining = plan_limited? ? client.plan_limits[:child_articles] - client.child_usage_count : cluster_limit
    if plan_limited? && remaining <= 0
      mark_paused!(client.plan_limit_message(:child))
      return
    end

    title_cap = [cluster_limit.to_i, remaining.to_i, GptTitleGenerator::MAX_INTENT_SLOTS].min
    topic_plans = GptTitleGenerator.generate_titles(pillar_column, limit: title_cap)
    if topic_plans.blank?
      mark_failed!("子タイトルの生成に失敗しました")
      return
    end

    titles = topic_plans.map { |plan| plan["title"] }.compact.reject(&:blank?)
    if titles.blank?
      mark_failed!("有効な子タイトルが取得できませんでした")
      return
    end

    ActiveRecord::Base.transaction do
      titles.each do |child_title|
        Column.create!(
          parent_id: pillar_column.id,
          title: child_title,
          article_type: "child",
          status: "draft",
          genre: pillar_column.genre,
          choice: pillar_column.choice,
          client_id: client_id,
          **Column.attributes_for_child_generation(pillar_column)
        )
      end
    end

    if pause_for_child_titles?
      update!(status: "awaiting_child_title_approval")
      AutonomousContentMailer.child_titles_ready(self).deliver_later if client.present?
    else
      start_child_body_generation!
    end
  rescue => e
    mark_failed!(e.message)
    raise
  end

  def approve_child_titles!
    with_lock do
      reload
      return false unless status == "awaiting_child_title_approval"

      if pending_child_columns.none?
        mark_failed!("本文生成対象の子記事がありません")
        return false
      end

      start_child_body_generation!
      true
    end
  end

  def start_child_body_generation!
    update!(status: "generating_children")
    enqueue_next_child!
  end

  def advance_child_generation!
    return unless status == "generating_children"

    if pending_child_columns.exists?
      enqueue_next_child!
    else
      finalize!
    end
  end

  def enqueue_next_child!
    next_child = pending_child_columns.first
    if next_child.nil?
      # 失敗・エラー記事があっても completed として完了させ、エラー情報は error_message に残す
      failed_count = child_columns.where(status: "error").count + child_columns.where(generation_status: "failed").count
      if failed_count > 0
        Rails.logger.warn("[AutonomousContentRun #{id}] #{failed_count}件の子記事が失敗しましたが処理を完了します")
        update!(error_message: "#{failed_count}件の子記事の生成に失敗しました（他の記事は正常に生成されています）")
      end
      finalize!
      return
    end

    GenerateColumnBodyJob.perform_later_for_autonomous(next_child.id, autonomous_run_id: id)
  end

  def finalize!
    suggestions = build_next_pillar_suggestions
    update!(
      status: "completed",
      next_pillar_titles: suggestions
    )

    AutonomousContentMailer.cycle_complete(self).deliver_later if notify_on_list.include?("cycle_complete") && client.present?
  end

  def mark_failed!(message)
    update!(status: "failed", error_message: message)
  end

  def mark_paused!(message)
    update!(status: "paused", error_message: message)
    AutonomousContentMailer.limit_paused(self).deliver_later if client.present?
  end

  def retry!
    with_lock do
      reload
      case status
      when "failed", "paused", "generating_pillar"
        retry_pillar_generation!
      when "generating_children"
        update!(status: "generating_children", error_message: nil)
        enqueue_next_child!
      else
        false
      end
    end
  end

  def retry_pillar_generation!
    return false unless pillar_column

    pillar_column.update!(
      generation_status: "idle",
      status: "draft",
      body: nil
    )
    update!(status: "generating_pillar", error_message: nil)
    GenerateColumnBodyJob.perform_later_for_autonomous(pillar_column_id, autonomous_run_id: id)
    true
  end

  private

  def normalize_genre_key
    return if genre.blank?

    resolved = GenreRegistry.resolve_key(genre, client: client)
    self.genre = resolved if resolved.present?
  end

  def normalize_language_value
    self.language = Column.normalize_language(language)
  end

  def build_next_pillar_suggestions
    return [] unless pillar_column
    return [] if plan_limited? && !client.can_suggest_titles?

    keyword = pillar_column.keyword.presence || title.split(/[\s　]+/).first.to_s
    suggestion_count = plan_limited? ? client.max_title_suggestion_count : Subscription::TITLE_SUGGESTION_BAR_MAX
    result = PillarTitleSuggestionService.call(
      keyword1: keyword,
      keyword2: title,
      target_layer: "middle",
      genre: genre,
      suggestion_count: suggestion_count,
      client: client,
      language: language
    )

    return [] unless result[:success]

    client&.record_title_suggestion!
    result[:titles].first(suggestion_count)
  rescue => e
    Rails.logger.error("[AutonomousContentRun] next pillar suggestions failed: #{e.message}")
    []
  end
end
