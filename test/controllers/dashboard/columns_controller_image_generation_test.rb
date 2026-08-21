require "test_helper"

class Dashboard::ColumnsControllerImageGenerationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def create_admin!
    Admin.create!(
      email: "admin-img-#{SecureRandom.hex(4)}@example.com",
      password: "password123"
    )
  end

  def create_missing_image_column!(index:)
    Column.create!(
      title: "Missing Image #{index}",
      article_type: "child",
      genre: "security",
      status: "draft",
      body: "generated body content #{index}",
      file: nil,
      code: "missing-image-#{index}-#{SecureRandom.hex(3)}"
    )
  end

  setup do
    @admin = create_admin!
    host! "drafity.pro"
    sign_in @admin

    55.times { |i| create_missing_image_column!(index: i) }
    Column.create!(
      title: "Published without image",
      article_type: "child",
      genre: "security",
      status: "completed",
      body: "published body",
      file: nil,
      published_at: Time.current,
      code: "published-no-image-#{SecureRandom.hex(3)}"
    )
    Column.create!(
      title: "Draft without image",
      article_type: "child",
      genre: "security",
      status: "draft",
      body: nil,
      file: nil,
      code: "draft-no-image-#{SecureRandom.hex(3)}"
    )
    @missing_total = Column.merge(Column.pending_review_missing_image).count
  end

  test "image_generation defaults to 30 per page and switches to 50 and 100" do
    assert @missing_total > 50, "test requires more than 50 missing-image columns"

    get image_generation_dashboard_columns_path
    assert_response :success
    assert_select "select[name=per] option[value='30'][selected]"
    assert_select "select[name=per] option[value='50']"
    assert_select "select[name=per] option[value='100']"
    assert_select "button#btn-trigger-run-all-generation", text: /全実行/
    assert_select "input.image-select-checkbox", count: 30
    assert_match %r{1 - 30 / #{@missing_total}件を表示}, response.body

    get image_generation_dashboard_columns_path(per: 50)
    assert_response :success
    assert_select "select[name=per] option[value='50'][selected]"
    assert_select "input.image-select-checkbox", count: 50
    assert_match %r{1 - 50 / #{@missing_total}件を表示}, response.body

    get image_generation_dashboard_columns_path(per: 100)
    assert_response :success
    assert_select "select[name=per] option[value='100'][selected]"
    expected_100 = [@missing_total, 100].min
    assert_select "input.image-select-checkbox", count: expected_100
    assert_match %r{1 - #{expected_100} / #{@missing_total}件を表示}, response.body
  end

  test "bulk_generate_images run_all processes all missing image targets" do
    called_ids = []
    original_generate = FluxImageGeneratorService.method(:generate!)
    original_thread = Thread.method(:new)

    FluxImageGeneratorService.define_singleton_method(:generate!) do |column|
      called_ids << column.id
    end

    # Run background work inline for deterministic assertions
    Thread.define_singleton_method(:new) do |*args, &block|
      block.call(*args)
      Class.new do
        def join(*); end
        def kill; end
      end.new
    end

    begin
      post bulk_generate_images_dashboard_columns_path, params: { run_all: "1" }
      assert_redirected_to dashboard_root_path
      assert_match(/画像生成を開始しました（#{@missing_total}件）/, flash[:notice].to_s)
      assert_equal @missing_total, called_ids.uniq.size
    ensure
      FluxImageGeneratorService.define_singleton_method(:generate!, original_generate)
      Thread.define_singleton_method(:new, original_thread)
    end
  end

  test "image generation list excludes drafts and published articles" do
    get image_generation_dashboard_columns_path(per: 100)
    assert_response :success
    assert_select "a", text: "Published without image", count: 0
    assert_select "a", text: "Draft without image", count: 0
    assert_match %r{/ #{@missing_total}件を表示}, response.body
  end

  test "sidebar missing_image badge matches pending review without images" do
    get sidebar_badges_dashboard_columns_path
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal @missing_total, json["missing_image"]
    assert json["pending_review"] >= json["missing_image"]
    assert json.key?("draft")
  end

  test "sidebar badges treat generation failure bodies as drafts not pending review" do
    Column.delete_all

    3.times do |i|
      Column.create!(
        title: "Failure dump #{i}",
        article_type: "child",
        genre: "security",
        status: "error",
        published_at: nil,
        body: "❌ 失敗: RuntimeError - 本文の生成に失敗しました",
        code: "fail-dump-#{i}-#{SecureRandom.hex(3)}"
      )
    end
    Column.create!(
      title: "Real pending review",
      article_type: "child",
      genre: "security",
      status: "completed",
      published_at: nil,
      body: "# Ready\n\nReview me.",
      file: nil,
      code: "pending-real-#{SecureRandom.hex(3)}"
    )

    get sidebar_badges_dashboard_columns_path
    assert_response :success
    json = JSON.parse(response.body)

    assert_equal 3, json["draft"]
    assert_equal 1, json["pending_review"]
    assert_equal 1, json["missing_image"]
  end

  test "dashboard draft tab count drops immediately after drafts are cleared" do
    Column.delete_all
    draft = Column.create!(
      title: "Soon cleared",
      article_type: "child",
      genre: "security",
      status: "draft",
      body: nil,
      code: "soon-cleared-#{SecureRandom.hex(3)}"
    )

    get dashboard_columns_path(scope: "draft")
    assert_response :success
    assert_match(/下書き/, response.body)
    assert_includes response.body, ">1<"

    draft.destroy!

    get dashboard_columns_path(scope: "draft")
    assert_response :success
    assert_match(/下書き/, response.body)
    assert_select ".tabs-group .tab-btn.active .count-badge", text: "0"
  end
end
