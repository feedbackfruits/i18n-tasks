# frozen_string_literal: true

require_relative "../relative_keys"

# These classes are used in the PrismScanners::Visitor class to store the translations found in the parsed code
# Used in the PrismScanners::Visitor class.
module I18n::Tasks::Scanners::PrismScanners
  class Root
    include ::I18n::Tasks::Scanners::RelativeKeys

    attr_reader(:calls, :translation_calls, :children, :node, :parent, :rails)

    def initialize(node: nil, parent: nil, file_path: nil, rails: false, relative_roots: nil)
      @calls = []
      @translation_calls = []
      @children = []
      @node = node
      @parent = parent
      @rails = rails
      @file_path = file_path
      @relative_roots = relative_roots
    end

    def file_path
      @file_path || @parent&.file_path
    end

    # The configured search.relative_roots, propagated from the root node to its children.
    def relative_roots
      @relative_roots || @parent&.relative_roots
    end

    def add_child(node)
      @children << node
      node
    end

    def add_call(node)
      @calls << node
    end

    def add_translation_call(translation_call)
      @translation_calls += Array(translation_call)
    end

    def rails_view?
      return false unless rails && file_path.present?

      view_path_parts.present? || component_view?
    end

    def support_relative_keys?
      rails_view?
    end

    def support_candidate_keys?
      false
    end

    def path
      if view_path_parts.present?
        view_path_parts
      elsif component_view?
        component_path
      else
        []
      end
    end

    def process
      (@translation_calls + @children.flat_map(&:process)).flatten
    end

    # Only supported for Rails controllers currently
    def private_method
      false
    end

    private

    # Key-prefix segments for a view template under one of the configured relative roots,
    # or nil when the file is not under any root. Reuses RelativeKeys so the resolved key
    # matches the legacy whitequark scanner.
    def view_path_parts
      return @view_path_parts if defined?(@view_path_parts)

      # Only view templates resolve via the file path; .rb sources (controllers, mailers,
      # components) get their namespace from the class/module name instead.
      @view_path_parts =
        if file_path.present? && !file_path.end_with?(".rb")
          relative_roots_path(file_path, relative_roots)
        end
    end

    # ViewComponent templates live under app/components, which is not a relative root.
    def component_view?
      file_path.present? && file_path.include?("app/components/") && !file_path.end_with?(".rb")
    end

    def component_path
      folder_path = file_path.sub(%r{app/components/}, "").split("/")
      name = folder_path.pop.split(".").first
      # Remove leading underscores from partials
      name = name[1..] if name.start_with?("_") # rubocop:disable Performance/ArraySemiInfiniteRangeSlice

      [*folder_path, name]
    end
  end

  class TranslationCall
    class ScopeError < StandardError; end
    attr_reader(:node, :key, :receiver, :options, :parent)

    def initialize(node:, key:, receiver:, options:, parent:, candidate_keys: nil)
      @node = node
      @key = key
      @receiver = receiver
      @options = options
      @parent = parent
      @candidate_keys = candidate_keys || []
    end

    def relative_key?
      @key&.start_with?(".") && @receiver.nil?
    end

    def with_parent(parent)
      self.class.new(
        node: @node,
        key: @key,
        receiver: @receiver,
        options: @options,
        parent: parent
      )
    end

    def with_node(node)
      self.class.new(
        node: node,
        key: @key,
        receiver: @receiver,
        options: @options,
        parent: @parent
      )
    end

    def occurrences(file_path)
      occurrence(file_path)
    end

    # Returns either a single key string or an array of candidate key strings for this call.
    def full_key
      return nil if key.nil?
      return nil unless key.is_a?(String)
      return nil if relative_key? && !support_relative_keys?

      base_parts = [scope].compact

      if relative_key? && support_candidate_keys?
        # For relative keys in controllers/methods, generate candidate keys by
        # progressively stripping trailing path segments from the parent path.
        # Example: parent.path = ["events", "create"], key = ".success"
        # yields: ["events.create.success", "events.success"]
        parent_path = parent&.path || []
        rel_key = key[1..] # strip leading dot # rubocop:disable Performance/ArraySemiInfiniteRangeSlice

        candidates = []
        parent_path_length = parent_path.length
        # Do not generate an unscoped bare key (keep_count = 0). Start from full parent path
        parent_path_length.downto(1) do |keep_count|
          parts = base_parts + parent_path.first(keep_count) + [rel_key]
          candidates << parts.compact.join(".")
        end

        candidates.map { |c| c.gsub("..", ".") }
      elsif relative_key?
        # For relative keys in views, just append to the full path
        [base_parts + parent.path + [key[1..]]].flatten.compact.join(".").gsub("..", ".") # rubocop:disable Performance/ChainArrayAllocation,Performance/ArraySemiInfiniteRangeSlice
      elsif key.start_with?(".")
        [base_parts + [key[1..]]].flatten.compact.join(".").gsub("..", ".") # rubocop:disable Performance/ArraySemiInfiniteRangeSlice,Performance/ChainArrayAllocation
      elsif @candidate_keys.present?
        ([key] + @candidate_keys).map do |c|
          [base_parts + [c]].flatten.compact.join(".").gsub("..", ".") # rubocop:disable Performance/ChainArrayAllocation
        end
      else
        [base_parts + [key]].flatten.compact.join(".").gsub("..", ".") # rubocop:disable Performance/ChainArrayAllocation
      end
    end

    private

    def scope
      return nil if @options.nil?
      return nil unless @options.key?("scope")

      scope_value = @options["scope"]
      scope_array = Array(scope_value)

      # ArgumentsVisitor returns a Prism::LocalVariableReadNode for local variables.
      # Scope cannot be resolved if array is empty
      if scope_value.is_a?(Prism::LocalVariableReadNode) ||
          scope_array.empty? ||
          !scope_array.all? { |s| s.is_a?(String) || s.is_a?(Symbol) }
        fail(ScopeError, "Could not process scope")
      end

      scope_array.join(".")
    end

    def occurrence(file_path)
      local_node = @node

      location = local_node.location

      final = full_key
      return nil if final.nil?

      occurrence = ::I18n::Tasks::Scanners::Results::Occurrence.new(
        path: file_path,
        line: local_node.respond_to?(:slice) ? local_node.slice : local_node.location.slice,
        pos: location.start_offset,
        line_pos: location.start_column,
        line_num: location.start_line,
        raw_key: key,
        candidate_keys: Array(final)
      )

      # full_key may be a single String or an Array of candidate strings
      if final.is_a?(Array)
        [final.first, occurrence]
      else
        [final, occurrence]
      end
    rescue ScopeError
      nil
    end

    # Only public methods are added to the context path
    # Only some classes supports relative keys
    def support_relative_keys?
      (parent.is_a?(ParsedMethod) || parent.is_a?(Root)) && parent.support_relative_keys?
    end

    # Not supported for Rails views
    def support_candidate_keys?
      support_relative_keys? && parent.support_candidate_keys?
    end
  end

  class ParsedModule < Root
    def support_relative_keys?
      false
    end

    def path
      (@parent&.path || []) + [path_name]
    end

    def path_name
      @node.name.to_s.underscore
    end
  end

  class ParsedClass < Root
    attr_reader(:private_method)

    def initialize(node:, parent:, rails:)
      @private_method = false
      @methods = []
      @private_methods = []
      @before_actions = []

      super
    end

    def add_child(node)
      case node
      when ParsedMethod
        if @private_method
          @private_methods << node
        else
          @methods << node
        end
      when ParsedBeforeAction
        @before_actions << node
      end

      super
    end

    def process # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
      if controller?
        process_controller
      else
        super
      end
    end

    def process_controller
      methods_by_name = @methods.group_by(&:name)
      private_methods_by_name = @private_methods.group_by(&:name)

      # For each before_action we need to
      # - Find which method it calls
      # - Find out which methods it applies to
      # - Calculate translation calls (and see if they are relative)
      # - Add the translation calls to the methods it applies to

      @before_actions.each do |before_action|
        before_action_name = before_action.name&.to_sym
        method_call = methods_by_name[before_action_name]&.first || private_methods_by_name[before_action_name]&.first
        translation_calls = (method_call&.translation_calls || []) + before_action.translation_calls

        # We need to handle the parent here, should not be the before_action when it is called in the method.
        @methods.each do |method|
          next unless before_action.applies_to?(method.name)

          method.add_translation_call(
            translation_calls.map do |call|
              call.with_parent(method)
            end
          )
        end
      end

      nested_calls = {}
      new_translation_calls = []

      @methods.each do |method|
        method.calls.each do |call|
          next if call.receiver.present?

          other_method = methods_by_name[call.name]&.first || private_methods_by_name[call.name]&.first
          next unless other_method

          nested_calls[method.name] ||= []
          nested_calls[method.name] << other_method.name

          if nested_calls[call.name]&.include?(method.name)
            next
          end

          other_method.translation_calls.each do |translation_call|
            new_translation_calls.push(translation_call.with_parent(method))
          end
        end
      end

      @translation_calls + @children.flat_map(&:process) + new_translation_calls
    end

    def private_methods!
      @private_method = true
    end

    def support_relative_keys?
      controller? || mailer? || view_component?
    end

    def support_candidate_keys?
      controller?
    end

    def path
      (@parent&.path || []) + [path_name]
    end

    def controller?
      @rails && @node.name.to_s.end_with?("Controller")
    end

    def mailer?
      @rails && @node.name.to_s.end_with?("Mailer")
    end

    def view_component?
      @rails && file_path.present? && file_path.include?("app/components/")
    end

    def path_name
      path = @node.constant_path.full_name_parts.map { |s| s.to_s.underscore }
      path.last.delete_suffix!("_controller") if controller?

      path
    end
  end

  class ParsedMethod < Root
    def initialize(node:, parent:, private_method: false)
      @private_method = private_method

      super(node: node, parent: parent)
    end

    def support_relative_keys?
      !@private_method && @parent&.support_relative_keys?
    end

    delegate(:support_candidate_keys?, to: :parent)

    def path
      if @parent.respond_to?(:view_component?) && @parent.view_component?
        @parent.path
      else
        (@parent&.path || []) + [@node.name]
      end
    end

    def name
      @node.name
    end

    def process
      @translation_calls
    end
  end

  class ParsedBeforeAction < Root
    attr_accessor(:name)
    attr_reader(:only, :except)

    def initialize(node:, parent:, name: nil, only: nil, except: nil)
      @name = name
      self.only = only
      self.except = except

      super(node: node, parent: parent)
    end

    # only:/except: come from the ArgumentsVisitor, which resolves array and symbol/string
    # literals but passes other AST nodes (constants, method calls, splats) through
    # unresolved. Coerce to a list of action-name strings, or nil when the filter cannot be
    # statically resolved — in which case the before_action conservatively applies to all
    # actions, so real usages are never missed.
    def only=(value)
      @only = normalize_action_filter(value)
    end

    def except=(value)
      @except = normalize_action_filter(value)
    end

    def support_relative_keys?
      false
    end

    def applies_to?(method_name)
      if @only.nil? && @except.nil?
        true
      elsif @only.nil?
        !@except.include?(method_name.to_s)
      elsif @except.nil?
        @only.include?(method_name.to_s)
      else
        false
      end
    end

    def path
      @parent&.path || []
    end

    def process
      @translation_calls.filter { |call| !call.relative_key? }
    end

    private

    # @return [Array<String>, nil] action names, or nil when the value cannot be resolved
    #   to a literal list of names (conservatively treated as "applies to all actions").
    def normalize_action_filter(value)
      case value
      when nil
        nil
      when String, Symbol
        [value.to_s]
      when Array
        names = value.select { |v| v.is_a?(String) || v.is_a?(Symbol) }.map(&:to_s)
        # If any element was dynamic (e.g. an interpolated or non-literal entry), bail out
        # to "applies to all" rather than matching on a partial list.
        (names.size == value.size) ? names.presence : nil
      end
    end
  end
end
