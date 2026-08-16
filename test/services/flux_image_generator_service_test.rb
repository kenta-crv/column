# frozen_string_literal: true

require "test_helper"

class FluxImageGeneratorServiceTest < ActiveSupport::TestCase
  test "already_generated? is true only for flux filenames" do
    flux = Column.new
    flux.write_attribute(:file, "column_12_abcdefabcdefabcd.webp")
    assert FluxImageGeneratorService.already_generated?(flux)

    stock = Column.new
    stock.write_attribute(:file, "app1.webp")
    refute FluxImageGeneratorService.already_generated?(stock)

    empty = Column.new
    refute FluxImageGeneratorService.already_generated?(empty)
  end
end
