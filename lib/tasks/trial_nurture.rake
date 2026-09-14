# frozen_string_literal: true

namespace :trial_nurture do
  desc "Dispatch trial nurture emails based on activation progress (run daily)"
  task dispatch: :environment do
    result = DispatchTrialNurtureEmailsJob.perform_now
    puts "examined=#{result.examined} sent=#{result.sent} skipped=#{result.skipped}"
  end

  desc "Send one test email per nurture kind to TO=email (actually delivers via SMTP)"
  task send_test_emails: :environment do
    to = ENV.fetch("TO")
    raise "TO is required, e.g. TO=you@example.com bin/rails trial_nurture:send_test_emails" if to.blank?

    ActionMailer::Base.raise_delivery_errors = true
    ActionMailer::Base.delivery_method = :smtp

    client = Client.find_or_initialize_by(email: to)
    if client.new_record?
      client.assign_attributes(
        password: SecureRandom.hex(12),
        name: "Nurture Test",
        preferred_locale: "ja"
      )
      client.save!
    end
    client.update_columns(
      subscription_plan: "trial",
      subscription_status: "active",
      trial_ends_at: 3.days.from_now
    )

    progress = TrialNurture::ProgressTracker.ensure_progress(client)
    progress.update!(
      conversion_offer_expires_at: ClientTrialProgress::CONVERSION_OFFER_GRACE_DAYS.days.from_now
    )

    results = []
    TrialNurtureEmailLog::KINDS.each do |kind|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      mail = nil
      I18n.with_locale(:ja) do
        mail = TrialNurtureMailer.nurture(client: client, kind: kind, progress: progress)
        mail.deliver_now
      end
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      results << {
        kind: kind,
        to: mail.to,
        subject: mail.subject,
        message_id: mail.message_id,
        delivery_method: ActionMailer::Base.delivery_method,
        elapsed_ms: elapsed_ms,
        status: "delivered"
      }
      puts "[OK] kind=#{kind} to=#{mail.to.join(',')} message_id=#{mail.message_id} elapsed_ms=#{elapsed_ms}"
    rescue StandardError => e
      results << { kind: kind, status: "failed", error: "#{e.class}: #{e.message}" }
      puts "[FAIL] kind=#{kind} #{e.class}: #{e.message}"
    end

    ok = results.count { |r| r[:status] == "delivered" }
    fail_count = results.size - ok
    puts "SUMMARY delivered=#{ok} failed=#{fail_count} total=#{results.size}"
    raise "Some nurture test emails failed" if fail_count.positive?
  end
end
