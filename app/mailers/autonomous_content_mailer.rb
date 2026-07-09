class AutonomousContentMailer < ApplicationMailer
  default from: "info@j-work.jp"

  def child_titles_ready(run)
    @run = run
    @client = run.client
    @pillar = run.pillar_column
    @approval_url = dashboard_autonomous_run_url(run)

    mail(
      to: @client.email,
      subject: "【Drafity】子タイトルが生成されました（承認をお願いします）"
    )
  end

  def cycle_complete(run)
    @run = run
    @client = run.client
    @pillar = run.pillar_column
    @next_titles = Array(run.next_pillar_titles)
    @new_run_url = new_dashboard_autonomous_run_url

    mail(
      to: @client.email,
      subject: "【Drafity】自律生成サイクルが完了しました"
    )
  end

  def limit_paused(run)
    @run = run
    @client = run.client
    @dashboard_url = dashboard_autonomous_runs_url

    mail(
      to: @client.email,
      subject: "【Drafity】自律生成が一時停止しました（上限到達）"
    )
  end
end
