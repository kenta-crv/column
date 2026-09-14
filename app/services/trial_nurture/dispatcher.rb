# frozen_string_literal: true

module TrialNurture
  # 日次でトライアル進捗に応じた促進メールを1通送る。
  # 各 kind はクライアントあたり1回のみ。
  # 着手促進は Day1 / Day5、転換オファーは期限3日前と期限翌日。
  class Dispatcher
    PRODUCT = "Drafity"

    Result = Struct.new(:examined, :sent, :skipped, keyword_init: true)

    def self.run!(now: Time.current)
      new(now: now).run!
    end

    def initialize(now: Time.current)
      @now = now
    end

    def run!
      sent = 0
      skipped = 0
      examined = 0

      candidate_clients.find_each do |client|
        examined += 1
        if dispatch_for!(client)
          sent += 1
        else
          skipped += 1
        end
      end

      Result.new(examined: examined, sent: sent, skipped: skipped)
    end

    def dispatch_for!(client)
      return false if client.email.blank?
      return false if paid?(client)

      progress = ProgressTracker.ensure_progress(client)
      return false if progress.blank? || progress.converted_at.present?

      progress.ensure_conversion_offer_expires_at!
      kind = select_kind(client, progress)
      return false if kind.blank?
      return false if already_sent?(client, kind)

      deliver!(client, progress, kind)
      true
    rescue StandardError => e
      Rails.logger.error("[TrialNurture::Dispatcher] client=#{client.id} #{e.class}: #{e.message}")
      false
    end

    def select_kind(client, progress)
      day = trial_day_number(client)
      return nil if day < 1

      days_left = days_until_trial_end(client)
      expired_days = days_since_trial_end(client)

      # 期限後フォロー（Day 15 相当）
      if expired_days >= 1 && expired_days <= ClientTrialProgress::CONVERSION_OFFER_GRACE_DAYS
        return "day15_expired_followup" unless already_sent?(client, "day15_expired_followup")
      end

      # 期限3日前〜終了日（Day 11〜14）
      if client.on_trial? && days_left <= 3 && days_left >= 0
        return "day11_conversion_offer" unless already_sent?(client, "day11_conversion_offer")
      end

      # Day 5 窓（5〜10）
      if day >= 5 && day <= 10
        if progress.not_started?
          return "day5_not_started" unless already_sent?(client, "day5_not_started")
        elsif !progress.has_pillar?
          return "day5_no_pillar" unless already_sent?(client, "day5_no_pillar")
        elsif !progress.has_child?
          return "day5_no_child" unless already_sent?(client, "day5_no_child")
        end
      end

      # Day 1 窓（1〜4）— 未着手のみ・1回
      if day >= 1 && day <= 4 && progress.not_started?
        return "day1_not_started" unless already_sent?(client, "day1_not_started")
      end

      nil
    end

    private

    def candidate_clients
      Client.where(subscription_plan: "trial")
        .where.not(email: [nil, ""])
        .where("trial_ends_at IS NULL OR trial_ends_at > ?", @now - (ClientTrialProgress::CONVERSION_OFFER_GRACE_DAYS + 1).days)
    end

    def paid?(client)
      plan = client.subscription_plan.to_s
      plan.present? && plan != "trial"
    end

    def already_sent?(client, kind)
      TrialNurtureEmailLog.exists?(client_id: client.id, kind: kind)
    end

    def trial_started_on(client)
      (client.trial_ends_at.present? ? client.trial_ends_at - Subscription::TRIAL_DAYS.days : client.created_at).to_date
    end

    def trial_day_number(client)
      (@now.to_date - trial_started_on(client)).to_i
    end

    def days_until_trial_end(client)
      return 999 if client.trial_ends_at.blank?

      (client.trial_ends_at.to_date - @now.to_date).to_i
    end

    def days_since_trial_end(client)
      return -1 if client.trial_ends_at.blank?
      return -1 if client.trial_ends_at > @now

      (@now.to_date - client.trial_ends_at.to_date).to_i
    end

    def deliver!(client, progress, kind)
      I18n.with_locale(client.ui_locale) do
        TrialNurtureMailer.nurture(client: client, kind: kind, progress: progress).deliver_now
      end

      TrialNurtureEmailLog.create!(
        client: client,
        kind: kind,
        sent_at: @now,
        stage_at_send: progress.stage.to_s,
        metadata: {
          trial_day: trial_day_number(client),
          days_left: days_until_trial_end(client),
          offer_expires_at: progress.conversion_offer_expires_at,
          offer_percent_off: Subscription.trial_conversion_offer_configured? ? Subscription::STANDARD_INTRO_PERCENT_OFF : nil,
          offer_configured: Subscription.trial_conversion_offer_configured?
        }
      )
    end
  end
end
