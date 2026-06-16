# frozen_string_literal: true

require "spec_helper"

# The Prism scanner must emit the same keys as the legacy whitequark scanner for
# dynamic/interpolated translate calls, under both strict modes. The whitequark
# scanner is the correctness oracle.
RSpec.describe "Prism dynamic keys" do
  let(:path) { "app/helpers/dynamic_keys_helper.rb" }

  def whitequark_keys(strict)
    scanner = I18n::Tasks::Scanners::RubyScanner.new(config: {strict: strict})
    scanner.send(:scan_file, path).map(&:first).sort
  end

  def prism_keys(strict, mode)
    scanner = I18n::Tasks::Scanners::RubyScanner.new(config: {strict: strict, prism: mode})
    scanner.send(:scan_file, path).map(&:first).sort
  end

  around do |ex|
    TestCodebase.in_test_app_dir(directory: "spec/fixtures/used_keys") { ex.run }
  end

  %w[ruby rails].each do |mode|
    context "prism: #{mode.inspect}" do
      it "matches whitequark with strict: true (dynamic keys dropped)" do
        expect(prism_keys(true, mode)).to eq(whitequark_keys(true))
        expect(prism_keys(true, mode)).to eq(%w[plain.static.key])
      end

      it "matches whitequark with strict: false (dynamic keys preserved)" do
        expect(prism_keys(false, mode)).to eq(whitequark_keys(false))
        expect(prism_keys(false, mode)).to include(
          "analytics.actor.\#{'admin_' if admin}name",
          "lti.calendar.\#{lms_type}.title",
          "\#{record.type}.type",
          "trailing.prefix.\#{suffix}",
          "sym.dynamic.\#{seg}",
          "plain.static.key"
        )
      end
    end
  end
end
