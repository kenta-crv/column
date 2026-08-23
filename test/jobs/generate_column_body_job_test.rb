require "test_helper"
require "minitest/mock"

class GenerateColumnBodyJobTest < ActiveJob::TestCase
  def create_column!(body: nil)
    Column.create!(
      title: "Child article",
      article_type: "child",
      genre: "other",
      status: "approved",
      generation_status: "queued",
      code: "body-job-#{SecureRandom.hex(3)}",
      body: body,
      language: "ja"
    )
  end

  test "empty generation does not write exception text into body" do
    column = create_column!

    ColumnBodyGenerator.stub(:generate!, "") do
      GenerateColumnBodyJob.perform_now(column.id)
    end

    column.reload
    assert_nil column.body.presence
    refute_includes column.body.to_s, "❌ 失敗"
    refute_includes column.body.to_s, "RuntimeError"
    refute_includes column.body.to_s, "generate_column_body_job.rb"
  end

  test "clears previous exception dump so regeneration can run" do
    dump = "❌ 失敗: RuntimeError - 本文の生成に失敗しました\n場所: app/jobs/generate_column_body_job.rb:54"
    column = create_column!(body: dump)
    article = "# 導入\n\n現場の責任分界を契約に落とす手順を整理する。" * 5

    ColumnBodyGenerator.stub(:generate!, article) do
      FluxImageGeneratorService.stub(:already_generated?, true) do
        EvaluateColumnQualityJob.stub(:perform_now, true) do
          GenerateColumnBodyJob.perform_now(column.id)
        end
      end
    end

    column.reload
    assert_equal article, column.body
    assert_equal "completed", column.generation_status
    assert_equal "completed", column.status
  end

  test "exhausted retries mark failed without publishing error text" do
    column = create_column!(body: "❌ 失敗: RuntimeError - 本文の生成に失敗しました\n場所: job.rb:54")
    job = GenerateColumnBodyJob.new(column.id)

    job.mark_generation_failed!(ColumnBodyGenerator::EmptyOutputError.new("empty"))

    column.reload
    assert_nil column.body
    assert_equal "error", column.status
    assert_equal "failed", column.generation_status
    refute column.generated_body?
  end
end
