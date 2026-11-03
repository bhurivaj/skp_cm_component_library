# frozen_string_literal: true

require 'csv'

module SkpCm
  module ComponentLibrary
    # Reads sheet "Code List" of Material Code.xlsx, saved by the owner as CSV UTF-8 (spec §4.2)
    module CodeList
      class Error < StandardError; end

      BOM = "﻿"

      module_function

      # => { 'items' => { code => { 'name', 'category' } }, 'categories' => [in CSV order] }
      def parse(bytes)
        text = bytes.dup.force_encoding('UTF-8')
        raise Error, 'อ่านไฟล์ไม่ได้ — ให้ Save As เป็น "CSV UTF-8"' unless text.valid_encoding?

        rows = CSV.parse(text.delete_prefix(BOM))
        header_at = rows.index { |r| cells = r.map { |c| c.to_s.strip }; cells.include?('Code') && cells.include?('Categories') }
        raise Error, 'ไม่พบคอลัมน์ Code / Categories — เช็คว่า export sheet Code List เป็น CSV UTF-8' unless header_at

        header = rows[header_at].map { |c| c.to_s.strip }
        code_i, cat_i, name_i = header.index('Code'), header.index('Categories'), header.index('List')
        items = {}
        rows[(header_at + 1)..-1].each do |r|
          code = r[code_i].to_s.strip
          next if code.empty?

          items[code] = { 'name' => (name_i ? r[name_i].to_s.strip : ''), 'category' => r[cat_i].to_s.strip }
        end
        { 'items' => items, 'categories' => items.values.map { |v| v['category'] }.uniq }
      end

      # "VC-4203#2" => "VC-4203" (same rule as BoQ Counter)
      def base_name(definition_name)
        definition_name.split('#').first.to_s.strip
      end

      def file_name(code)
        code.gsub(/[\\\/:*?"<>|\s]/, '_')
      end
    end
  end
end
