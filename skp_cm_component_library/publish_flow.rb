# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'
require_relative 'publisher'
require_relative 'uploader'
require_relative 'library'

module SkpCm
  module ComponentLibrary
    # Menus "Publish ทั้งหมด…" / "Publish ตัวที่เลือก" (update spec §4) — SketchUp only
    module PublishFlow
      DEFAULTS = Publisher::DEFAULTS

      class << self
        def run_all
          start(:all)
        end

        def run_selected
          start(:selected)
        end

        private

        def start(mode)
          return UI.messagebox('กำลัง upload อยู่ — รอให้เสร็จก่อน') if @busy

          model = Sketchup.active_model
          unless Publisher.structure_set?(model.path)
            return UI.messagebox("Publish ได้เฉพาะในไฟล์ #{Publisher::STRUCTURE_SET} — เปิดไฟล์นั้นแล้วแก้ที่นั่นก่อน")
          end
          return unless Publisher.logged_in?

          code_list = read_csv
          return unless code_list

          staging = Publisher.staging_dir
          return unless staging

          picked = pick(mode, model, code_list)
          return unless picked

          version = Time.now.strftime('%Y%m%d-%H%M%S')
          dir = File.join(staging, version)
          failed = Publisher.write(model, picked['chosen'], dir)
          failed.each { |code| picked['chosen'].delete(code) }
          return UI.messagebox("บันทึกไฟล์ไม่สำเร็จ: #{failed.join(', ')}") if picked['chosen'].empty?

          with_previous(mode) do |previous|
            index_json = Publisher.index(code_list, picked['chosen'].keys, version, Time.now.iso8601, previous)
            FileUtils.mkdir_p(File.join(dir, 'index'))
            File.write(File.join(dir, 'index', 'index.json'), JSON.pretty_generate(index_json))
            upload(dir, version, Publisher.summary(picked, failed), mode)
          end
        rescue CodeList::Error => e
          UI.messagebox(e.message)
        rescue StandardError => e
          fail_with(e)
        end

        # CSV path is remembered; read again every time for the latest names / categories
        def read_csv
          path = Sketchup.read_default(DEFAULTS, 'csv_path')
          unless path && File.exist?(path)
            path = UI.openpanel('เลือก CSV (sheet Code List)', '', 'CSV|*.csv||')
            return nil unless path

            Sketchup.write_default(DEFAULTS, 'csv_path', path)
          end
          CodeList.parse(File.binread(path))
        end

        def pick(mode, model, code_list)
          if mode == :all
            names = model.definitions.reject { |d| d.group? || d.image? }.map(&:name)
            return Publisher.select(names, code_list)
          end

          names = model.selection.grep(Sketchup::ComponentInstance).map { |i| i.definition.name }.uniq
          sel = Publisher.selected_codes(names, code_list)
          if sel['codes'].empty?
            UI.messagebox("ไม่มี component ที่ชื่อตรง Code ในที่เลือก#{sel['unknown'].empty? ? '' : ": #{sel['unknown'].join(', ')}"}")
            return nil
          end
          picked = Publisher.select(names, code_list)
          { 'chosen' => picked['chosen'], 'duplicates' => picked['duplicates'], 'missing' => {},
            'unknown' => sel['unknown'] }
        end

        # Publish ตัวที่เลือก merges into the current index on Azure (must be schema 2)
        def with_previous(mode)
          return yield(nil) if mode == :all

          Library.http_get("#{Library::LIBRARY_URL}/index.json") do |status, body, error|
            guard do
              previous = begin
                status == 200 ? Library.parse_index(body) : raise(Library::Error, error || "HTTP #{status}")
              rescue Library::Error => e
                next UI.messagebox("อ่านรายการบน Azure ไม่ได้ (#{e.message}) — ใช้ Publish ทั้งหมดก่อน")
              end
              yield previous
            end
          end
        end

        def upload(dir, version, summary, mode)
          sas = sas_token
          return unless sas

          @busy = true
          files = Uploader.plan(dir, version)
          progress = ->(done, total) { Sketchup.status_text = "Upload component library #{done}/#{total}" }
          Uploader.run(files, sas, on_progress: progress) do |ok, message, status|
            @busy = false
            guard { finish(ok, message, status, version, summary, mode) }
          end
        end

        def finish(ok, message, status, version, summary, mode)
          Sketchup.status_text = ''
          unless ok
            bad_sas = [401, 403].include?(status) || message.to_s.include?(Uploader::BAD_SAS)
            Sketchup.write_default(DEFAULTS, 'upload_sas', '') if bad_sas
            hint = bad_sas ? "\nSAS หมดอายุ/ไม่ถูกต้อง — กด Publish ใหม่แล้วใส่ SAS ใหม่" : ''
            return UI.messagebox("Upload ไม่สำเร็จ — ทีมยังใช้รายการเดิม\n#{message}#{hint}")
          end

          Library.http_get("#{Library::LIBRARY_URL}/index.json") do |code, body, _error|
            guard do
              live = code == 200 && body.include?(version)
              note = mode == :all ? "\nทุกตัวจะขึ้นป้าย \"อัปเดต\" ในเครื่องของทีม" : ''
              check = live ? 'ทีมเห็นรายการใหม่แล้ว' : 'upload ครบ แต่ยังอ่าน index.json แบบ public ไม่ได้ — ลองเปิดหน้าต่างอีกครั้ง'
              UI.messagebox("#{summary}\n#{check}#{note}")
            end
          end
        end

        # Container SAS (Create + Write), kept only in this computer's SketchUp preferences
        def sas_token
          sas = Sketchup.read_default(DEFAULTS, 'upload_sas').to_s
          return sas unless sas.empty?

          input = UI.inputbox(['SAS token ของ container component-library (สิทธิ์ Create + Write)'], [''], 'ตั้งค่า Upload')
          sas = input && input[0].to_s.strip
          return nil if sas.nil? || sas.empty?

          Sketchup.write_default(DEFAULTS, 'upload_sas', sas)
          sas
        end

        def guard
          yield
        rescue StandardError => e
          fail_with(e)
        end

        def fail_with(error)
          @busy = false
          UI.messagebox("Publish ไม่สำเร็จ: #{error.message}")
          puts "SKP CM Component Library: #{error.class}: #{error.message}\n#{error.backtrace.first(5).join("\n")}"
        end
      end
    end
  end
end
