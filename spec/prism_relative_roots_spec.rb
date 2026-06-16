# frozen_string_literal: true

require "spec_helper"

# Regression specs: the Prism ERB scanner must resolve relative keys using the
# configured `search.relative_roots`, matching the legacy whitequark scanner.
RSpec.describe "Prism relative roots" do
  let!(:task) { I18n::Tasks::BaseTask.new }
  let(:prism_visitor) { "rails" }

  around do |ex|
    task.config[:search] = {paths: paths, prism: prism_visitor, relative_roots: relative_roots}
    TestCodebase.in_test_app_dir(directory: "spec/fixtures/used_keys") { ex.run }
  end

  describe "engine view root" do
    let(:relative_roots) { %w[app/views engines/foo/app/views] }
    let(:paths) { %w[engines/foo/app/views/bar/show.html.erb] }

    it "strips the configured engine root" do
      leaves = leaves_to_hash(task.used_tree.leaves.to_a)
      expect(leaves.keys).to match_array(%w[bar.show.x])
    end
  end

  describe "engine partial root" do
    let(:relative_roots) { %w[app/views engines/foo/app/views] }
    let(:paths) { %w[engines/foo/app/views/bar/_card.html.erb] }

    it "strips the root and the partial underscore" do
      leaves = leaves_to_hash(task.used_tree.leaves.to_a)
      expect(leaves.keys).to match_array(%w[bar.card.subtitle])
    end
  end

  describe "custom (non app/views) root" do
    let(:relative_roots) { %w[lib/components] }
    let(:paths) { %w[lib/components/widgets/_card.html.erb] }

    it "strips the custom root" do
      leaves = leaves_to_hash(task.used_tree.leaves.to_a)
      expect(leaves.keys).to match_array(%w[widgets.card.title])
    end
  end

  describe "top-level app/views (no regression)" do
    let(:relative_roots) { %w[app/views] }
    let(:paths) { %w[app/views/application/_event.html.erb] }

    it "still resolves the default layout" do
      leaves = leaves_to_hash(task.used_tree.leaves.to_a)
      expect(leaves.keys).to include("application.event.relative_key")
    end
  end

  # Criterion: the Prism scanner must produce keys identical to the legacy
  # (whitequark/Parser) scanner — the correctness oracle.
  describe "convergence with the default scanner" do
    let(:relative_roots) do
      %w[app/views engines/foo/app/views lib/components]
    end
    let(:paths) do
      %w[
        engines/foo/app/views/bar/show.html.erb
        engines/foo/app/views/bar/_card.html.erb
        lib/components/widgets/_card.html.erb
      ]
    end

    def keys_for(prism_mode)
      t = I18n::Tasks::BaseTask.new
      t.config[:search] = {paths: paths, prism: prism_mode, relative_roots: relative_roots}
      leaves_to_hash(t.used_tree.leaves.to_a).keys.sort
    end

    it "matches the default scanner for the same fixtures" do
      TestCodebase.in_test_app_dir(directory: "spec/fixtures/used_keys") do
        expect(keys_for("rails")).to eq(keys_for(nil))
      end
    end
  end
end
