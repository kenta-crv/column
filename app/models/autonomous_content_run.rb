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

  def self.start!(title:, genre:, cluster_limit:, client: nil, pause_for_approval_at: nil, notify_on: nil)
    settings = client&.autonomous_settings_with_defaults || Client::DEFAULT_AUTONOMOUS_SETTINGS
    limit = cluster_limit.to_i
    limit = DEFAULT_CLUSTER_LIMIT if limit <= 0
    limit = [[limit, MIN_CLUSTER_LIMIT].max, MAX_CLUSTER_LIMIT].min

    run = create!(
      client: client,
      title: title.strip,
      genre: genre,
      cluster_limit: limit,
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
    {
      "queued" => "待機中",
      "generating_pillar" => "親記事生成中",
      "generating_child_titles" => "子タイトル生成中",
      "awaiting_child_title_approval" => "子タイトル承認待ち",
      "generating_children" => "子記事生成中",
      "completed" => "完了",
      "failed" => "失敗",
      "paused" => "一時停止（上限到達）"
    }[status] || status
  end

  def child_columns
    return Column.none unless pillar_column_id.present?

    pillar_column.children.order(:id)
  end

  def pending_child_columns
    child_columns
      .where("body IS NULL OR TRIM(body) = ''")
      .where.not(generation_status: %w[failed generating])
      .where.not(status: "error")
  end

  def completed_child_count
    child_columns.where(generation_status: "completed").where.not(body: [nil, ""]).count
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
        client_id: client_id
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

    topic_plans = GptTitleGenerator.generate_titles(pillar_column)
    if topic_plans.blank?
      mark_failed!("子タイトルの生成に失敗しました")
      return
    end

    titles = topic_plans.map { |plan| plan["title"] }.compact.reject(&:blank?).first(cluster_limit)
    if titles.blank?
      mark_failed!("有効な子タイトルが取得できませんでした")
      return
    end

    remaining = plan_limited? ? client.plan_limits[:child_articles] - client.child_usage_count : cluster_limit
    if plan_limited? && remaining <= 0
      mark_paused!(client.plan_limit_message(:child))
      return
    end
    titles = titles.first(remaining)

    ActiveRecord::Base.transaction do
      titles.each do |child_title|
        Column.create!(
          parent_id: pillar_column.id,
          title: child_title,
          article_type: "child",
          status: "draft",
          genre: pillar_column.genre,
          choice: pillar_column.choice,
          client_id: client_id
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
      if child_columns.where(status: "error").exists? || child_columns.where(generation_status: "failed").exists?
        mark_failed!("一部の子記事の生成に失敗しました。")
      else
        finalize!
      end
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
      client: client
    )

    return [] unless result[:success]

    client&.record_title_suggestion!
    result[:titles].first(suggestion_count)
  rescue => e
    Rails.logger.error("[AutonomousContentRun] next pillar suggestions failed: #{e.message}")
    []
  end
end
