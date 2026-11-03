# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'
require_relative 'code_list'
require_relative 'hub_link'

module SkpCm
  module ComponentLibrary
    # Publish helpers (spec §4.2 + update spec §4): pick definitions, build index.json, write the staging folder.
    # The menu flows live in publish_flow.rb
    module Publisher
      DEFAULTS = 'skp_cm_component_library'

      module_function

      # => { 'chosen' => { code => definition_name }, 'duplicates' => [code], 'missing' => { category => [code] } }
      def select(definition_names, code_list)
        items = code_list['items']
        by_code = Hash.new { |h, k| h[k] = [] }
        definition_names.each do |name|
          code = CodeList.base_name(name)
          by_code[code] << name if items.key?(code)
        end
        chosen = {}
        by_code.each { |code, names| chosen[code] = names.find { |n| !n.include?('#') } || names.first }
        missing = Hash.new { |h, k| h[k] = [] }
        items.each { |code, item| missing[item['category']] << code unless chosen.key?(code) }
        { 'chosen' => chosen, 'duplicates' => by_code.select { |_, n| n.size > 1 }.keys, 'missing' => Hash[missing] }
      end

      # index.json schema 2 (update spec §3). codes get the new version; with a previous index the other items
      # keep their version. Order: CSV order, then previous items no longer in the CSV
      def index(code_list, codes, version, published_at, previous = nil)
        old = {}
        (previous ? previous['items'] : []).each { |i| old[i['code']] = i }
        items = []
        code_list['items'].each do |code, item|
          next unless codes.include?(code) || old.key?(code)

          items << { 'code' => code, 'name' => item['name'], 'category' => item['category'],
                     'file' => CodeList.file_name(code),
                     'version' => codes.include?(code) ? version : old[code]['version'] }
        end
        old.each_value { |i| items << i unless code_list['items'].key?(i['code']) }
        { 'schema' => 2, 'published_at' => published_at,
          'categories' => items.map { |i| i['category'] }.uniq, 'items' => items }
      end

      STRUCTURE_SET = 'CM Structure Set.skp'

      # Publish only from the master file (update spec F)
      def structure_set?(path)
        File.basename(path.to_s) == STRUCTURE_SET
      end

      # Codes of the selected definitions (CSV order not needed), plus names that match no code
      def selected_codes(names, code_list)
        codes = names.map { |n| CodeList.base_name(n) }
        { 'codes' => codes.select { |c| code_list['items'].key?(c) }.uniq,
          'unknown' => names.reject { |n| code_list['items'].key?(CodeList.base_name(n)) }.uniq }
      end

      def logged_in?
        hub = HubLink.auth
        return true if hub && hub.logged_in?

        UI.messagebox(hub ? 'ยังไม่ได้ login — เปิด SKP CM Extensions Hub เพื่อ login ก่อน' : HubLink::MISSING_MESSAGE)
        hub.show_login if hub
        false
      end

      def staging_dir
        dir = Sketchup.read_default(DEFAULTS, 'staging_dir')
        return dir if dir && File.directory?(dir)

        dir = UI.select_directory(title: 'เลือกโฟลเดอร์ staging สำหรับไฟล์ที่จะ upload')
        Sketchup.write_default(DEFAULTS, 'staging_dir', dir) if dir
        dir
      end

      # Returns the codes whose .skp or .png could not be written (left out of index.json)
      def write(model, chosen, dir)
        components = File.join(dir, 'components')
        thumbs = File.join(dir, 'thumbs')
        FileUtils.mkdir_p([components, thumbs])
        chosen.reject do |code, name|
          definition = model.definitions[name]
          file = CodeList.file_name(code)
          skp = File.join(components, "#{file}.skp")
          png = File.join(thumbs, "#{file}.png")
          definition.save_as(skp)
          definition.refresh_thumbnail
          definition.save_thumbnail(png)
          File.exist?(skp) && File.exist?(png)
        end.keys
      end

      def summary(picked, failed)
        lines = ["Publish แล้ว #{picked['chosen'].size} ตัว", '']
        lines.push("บันทึกไฟล์ไม่สำเร็จ (ไม่ได้ใส่ในรายการ): #{failed.join(', ')}", '') unless failed.empty?
        unless picked['duplicates'].empty?
          lines << "Code ที่มีหลาย definition (ใช้ตัวที่ไม่มี #): #{picked['duplicates'].join(', ')}"
          lines << ''
        end
        unless picked['missing'].empty?
          lines << 'Code ใน CSV ที่ไม่มี component:'
          picked['missing'].each { |cat, codes| lines << "  #{cat} (#{codes.size}): #{codes.join(', ')}" }
          lines << ''
        end
        lines.join("\n")
      end
    end
  end
end
