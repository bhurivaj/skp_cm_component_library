# frozen_string_literal: true

require_relative 'code_list'

module SkpCm
  module ComponentLibrary
    # "อัปเดตในงาน" (update spec §5.1–5.2): find library components older than the index and swap them
    module ModelUpdate
      DICT = 'skp_cm_component_library'

      module_function

      # defs: [[definition_name, version_attribute_or_nil]] => { code => [definition_names] }
      # A definition with no label (copied from the Structure Set by hand) counts as old
      def outdated(defs, index)
        return {} unless index

        latest = {}
        index['items'].each { |i| latest[i['code']] = i['version'] }
        result = Hash.new { |h, k| h[k] = [] }
        defs.each do |name, version|
          code = CodeList.base_name(name)
          result[code] << name if latest.key?(code) && version != latest[code]
        end
        Hash[result]
      end

      # [[name, version]] of the model's component definitions (SketchUp only)
      def definition_info(model)
        model.definitions.reject { |d| d.group? || d.image? }.map { |d| [d.name, d.get_attribute(DICT, 'version')] }
      end

      def mark(definition, code, version)
        definition.set_attribute(DICT, 'code', code)
        definition.set_attribute(DICT, 'version', version)
      end

      # updates: [{ 'code', 'version', 'old_names', 'path' }] — one undo step; raises after abort on error
      def apply(model, updates)
        model.start_operation('อัปเดต component', true)
        updates.each { |u| swap(model, u) }
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end

      def swap(model, update)
        code = update['code']
        olds = update['old_names'].map { |n| model.definitions[n] }.compact
        current = model.definitions[code]
        # Reuse a definition already at the latest version; otherwise load. load can hand back one of the olds
        # (same GUID as the file: a pasted copy or a re-published unchanged part) — then keep that one
        fresh = current && current.get_attribute(DICT, 'version') == update['version'] ? current : model.definitions.load(update['path'])
        olds.delete(fresh)
        nested = olds.flat_map { |d| nested_definitions(d) }.uniq - [fresh]
        olds.each { |old| old.instances.each { |i| i.definition = fresh } }
        olds.each { |old| model.definitions.remove(old) }
        remove_unused(model, nested)
        fresh.name = code unless fresh.name == code
        mark(fresh, code, update['version'])
      end

      # Every definition used inside definition (any depth)
      def nested_definitions(definition, found = [])
        definition.entities.each do |e|
          next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)

          d = e.definition
          next if found.include?(d)

          found << d
          nested_definitions(d, found)
        end
        found
      end

      # Only the old version's own parts that nothing uses any more — never purge_unused (it would remove the user's)
      def remove_unused(model, candidates)
        loop do
          unused = candidates.select { |d| d.valid? && d.instances.empty? }
          break if unused.empty?

          unused.each { |d| model.definitions.remove(d) }
        end
      end
    end
  end
end
