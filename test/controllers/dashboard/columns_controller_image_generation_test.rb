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
    @missing_total = Column.merge(Column.missing_generated_image).count
  end

  test "image_generation defaults to 50 per page and switches to 100" do
    assert @missing_total > 50, "test requires more than 50 missing-image columns"

    get image_generation_dashboard_columns_path
    assert_response :success
    assert_select "select[name=per] option[value='50'][selected]"
    assert_select "select[name=per] option[value='100']"
    assert_select "button#btn-trigger-run-all-generation", text: /全実行/
    assert_select "input.image-select-checkbox", count: 50
    assert_match %r{1 - 50 / #{@missing_total}件を表示}, response.body

    get image_generation_dashboard_columns_path(per: 100)
    assert_response :success
    assert_select "select[name=per] option[value='100'][selected]"
    expected_100 = [@missing_total, 100].min
    assert_select "input.image-select-checkbox", count: expected_100
    assert_match %r{1 - #{expected_100} / #{@missing_total}件を表示}, response.body
    assert expected_100 > 50

    get image_generation_dashboard_columns_path(per: 30)
    assert_response :success
    assert_select "select[name=per] option[value='50'][selected]"
    assert_select "input.image-select-checkbox", count: 50
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
end
