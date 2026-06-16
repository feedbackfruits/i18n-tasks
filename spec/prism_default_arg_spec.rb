# frozen_string_literal: true

require "spec_helper"

# The Prism scanner must capture the default: kwarg of t/translate calls on the emitted
# occurrence, matching the legacy whitequark scanner (the correctness oracle).
RSpec.describe "Prism default: argument" do
  let(:path) { "app/helpers/default_arg_helper.rb" }

  # @return [Hash{String => Object}] key => occurrence.default_arg
  def defaults_by_key(scanner)
    scanner.send(:scan_file, path).to_h { |key, occ| [key, occ.default_arg] }
  end

  def whitequark(strict)
    defaults_by_key(I18n::Tasks::Scanners::RubyScanner.new(config: {strict: strict}))
  end

  def prism(strict, mode)
    defaults_by_key(I18n::Tasks::Scanners::RubyScanner.new(config: {strict: strict, prism: mode}))
  end

  around do |ex|
    TestCodebase.in_test_app_dir(directory: "spec/fixtures/used_keys") { ex.run }
  end

  %w[ruby rails].each do |mode|
    context "prism: #{mode.inspect}" do
      [true, false].each do |strict|
        it "matches whitequark default_arg with strict: #{strict}" do
          expect(prism(strict, mode)).to eq(whitequark(strict))
        end
      end

      it "captures string, symbol and hash defaults" do
        defaults = prism(true, mode)
        expect(defaults["with_string_default"]).to eq("fallback")
        expect(defaults["with_symbol_default"]).to eq("other_key")
        expect(defaults["with_hash_default"]).to eq("one" => "One", "other" => "Other")
        expect(defaults["with_no_default"]).to be_nil
      end

      it "captures an interpolated default only in non-strict mode" do
        expect(prism(false, mode)["with_dynamic_default"]).to eq("prefix.\#{suffix}")
        expect(prism(true, mode)["with_dynamic_default"]).to be_nil
      end
    end
  end

  describe "ERB" do
    let(:path) { "app/views/application/default_args.html.erb" }

    def erb_defaults_by_key(config)
      I18n::Tasks::Scanners::ErbAstScanner.new(config: config)
        .send(:scan_file, path).to_h { |key, occ| [key, occ.default_arg] }
    end

    %w[ruby rails].each do |mode|
      context "prism: #{mode.inspect}" do
        [true, false].each do |strict|
          it "matches whitequark default_arg with strict: #{strict}" do
            whitequark = erb_defaults_by_key(strict: strict)
            prism = erb_defaults_by_key(strict: strict, prism: mode)
            expect(prism).to eq(whitequark)
          end
        end

        it "captures string, symbol, hash and interpolated defaults" do
          expect(erb_defaults_by_key(strict: true, prism: mode)).to include(
            "with_string_default" => "fallback",
            "with_symbol_default" => "other_key",
            "with_hash_default" => {"one" => "One", "other" => "Other"},
            "with_dynamic_default" => nil,
            "with_no_default" => nil
          )
          expect(erb_defaults_by_key(strict: false, prism: mode)["with_dynamic_default"])
            .to eq("prefix.\#{suffix}")
        end
      end
    end
  end
end
