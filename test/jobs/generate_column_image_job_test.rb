# frozen_string_literal: true

require "test_helper"

class GenerateColumnImageJobTest < ActiveJob::TestCase
  def create_column!
    Column.create!(
      title: "Image job article",
      article_type: "pillar",
      genre: CrawlPolicy::GENRE_KEY,
      status: "draft",
      code: "img-job-#{SecureRandom.hex(3)}",
      body: "# Body\n\nGenerated for image job.",
      language: "ja"
    )
  end

  test "does not raise when fal key is missing" do
    column = create_column!
    previous = ENV["FAL_API_KEY"]
    ENV.delete("FAL_API_KEY")

    assert_nothing_raised { GenerateColumnImageJob.perform_now(column.id) }
  ensure
    ENV["FAL_API_KEY"] = previous if previous
  end

  test "skips when a flux image already exists" do
    column = create_column!
    column.update_column(:file, "column_#{column.id}_abcdefabcdefabcd.webp")

    previous = ENV["FAL_API_KEY"]
    ENV["FAL_API_KEY"] = "test-key"

    assert_nothing_raised { GenerateColumnImageJob.perform_now(column.id) }
    assert_equal "column_#{column.id}_abcdefabcdefabcd.webp", column.reload[:file]
  ensure
    ENV["FAL_API_KEY"] = previous
  end

  test "assigns a stock image when flux generation fails" do
    column = create_column!
    column.update_column(:file, nil)

    original = FluxImageGeneratorService.method(:generate!)
    FluxImageGeneratorService.define_singleton_method(:generate!) do |_col|
      raise "FAL API Error: 403 locked"
    end

    GenerateColumnImageJob.perform_now(column.id)

    assert column.reload[:file].present?
  ensure
    FluxImageGeneratorService.define_singleton_method(:generate!, original) if original
  end

  test "cargo column receives a stock image when file is blank" do
    column = Column.create!(
      title: "Cargo stock image",
      article_type: "pillar",
      genre: "cargo",
      status: "draft",
      code: "cargo-stock-#{SecureRandom.hex(3)}",
      body: "Body for stock image.",
      language: "en"
    )
    column.update_column(:file, nil)

    column.reload.assign_stock_image_if_missing!

    assert column.reload[:file].present?
  end
end
