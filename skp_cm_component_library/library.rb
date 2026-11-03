# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'model_update'

module SkpCm
  module ComponentLibrary
    # Library on Azure Blob (spec §4.3): index.json + one .skp per code, cached on this computer
    module Library
      class Error < StandardError; end

      # Public read URL, not a secret (spec §4.1)
      LIBRARY_URL = 'https://sketchup.blob.core.windows.net/component-library/library'

      class << self
        attr_accessor :index

        def cache_root
          base = ENV['LOCALAPPDATA'] || File.expand_path('~/Library/Application Support')
          File.join(base, 'SKP CM', 'component_library')
        end

        SAFE_NAME = /\A[\w.\-]+\z/.freeze

        def parse_index(text)
          data = JSON.parse(text)
          raise Error, 'รายการ component (index.json) ไม่ถูกต้อง — อัปเดต plugin ผ่าน Hub' unless valid_index?(data)

          data
        rescue JSON::ParserError
          raise Error, 'อ่านรายการ component (index.json) ไม่ได้'
        end

        # Version folders in the cache that no item uses any more
        def stale_dirs(root, versions)
          Dir.glob(File.join(root, '*')).select { |p| File.directory?(p) && !versions.include?(File.basename(p)) }
        end

        # Query string defeats SketchUp's HTTP cache (Azure sends no Cache-Control, so an old index could stay
        # cached for hours); Azure ignores unknown query parameters
        def index_url
          "#{LIBRARY_URL}/index.json?t=#{Time.now.to_i}"
        end

        def file_path(root, item, kind = 'components', ext = 'skp')
          File.join(root, item['version'], kind, "#{item['file']}.#{ext}")
        end

        def item_url(item, kind = 'components', ext = 'skp')
          "#{LIBRARY_URL}/#{item['version']}/#{kind}/#{item['file']}.#{ext}"
        end

        # Yields (index, error_message, offline) — first the cached index (if any), then the result from Azure
        def load_index(&done)
          cached = cached_index
          if cached
            self.index = cached
            done.call(cached, nil, false)
          end
          http_get(index_url) do |status, body, error|
            fresh = nil
            begin
              fresh = parse_index(body) if status == 200
            rescue Error => e
              error = e.message
            end
            if fresh
              begin
                save_index(body, fresh) unless cached == fresh
              rescue StandardError => e # cache is optional: still show the fresh list
                puts "SKP CM Component Library: cannot write cache (#{e.class}: #{e.message})"
              end
              self.index = fresh
              done.call(fresh, nil, false)
            elsif cached
              done.call(cached, nil, true)
            else
              done.call(nil, "โหลดรายการ component ไม่ได้ (#{error || "HTTP #{status}"})", true)
            end
          end
        end

        # Hangs the component on the mouse. Yields (ok, error_message); ok is :outdated when the model holds an
        # older version (caller asks, then calls update or place(existing_ok: true)). A second click on a code that
        # is still downloading is ignored (no yield)
        def place(code, model = active_model, existing_ok: false, &done)
          item = index && index['items'].find { |i| i['code'] == code }
          existing = model.definitions[code]
          if existing
            current = existing_ok || item.nil? || existing.get_attribute(ModelUpdate::DICT, 'version') == item['version']
            return done.call(current ? place_definition(model, existing) : :outdated, nil)
          end
          return done.call(false, "ไม่พบ #{code} ในรายการ") unless item

          @loading ||= {}
          return if @loading[code]

          path = file_path(cache_root, item)
          return done.call(load_and_place(model, path, item), nil) if File.exist?(path)

          @loading[code] = true
          url = item_url(item)
          download(url, path) do |ok, error|
            @loading.delete(code)
            begin
              if !ok
                done.call(false, "ดาวน์โหลด #{code} ไม่ได้ (#{error})")
              elsif !active_model.equal?(model) # user switched windows while downloading
                done.call(false, "ดาวน์โหลด #{code} แล้ว — คลิกอีกครั้งเพื่อวาง")
              else
                done.call(load_and_place(model, path, item), nil)
              end
            rescue StandardError => e # runs later, outside the rescue below
              done.call(false, "วาง #{code} ไม่ได้: #{e.message}")
            end
          end
        rescue StandardError => e
          @loading.delete(code) if @loading
          done.call(false, "วาง #{code} ไม่ได้: #{e.message}")
        end

        def active_model
          Sketchup.active_model
        end

        # { code => 'new' | 'updated' } against the versions the user has seen (update spec §5.3)
        def changes(index, seen)
          result = {}
          index['items'].each do |i|
            if !seen.key?(i['code'])
              result[i['code']] = 'new'
            elsif seen[i['code']] != i['version']
              result[i['code']] = 'updated'
            end
          end
          result
        end

        # First run (no seen.json): everything counts as seen, so 169 tiles don't all get a badge
        def seen_changes(index)
          path = File.join(cache_root, 'seen.json')
          if File.exist?(path)
            seen = JSON.parse(File.read(path))
            return changes(index, seen) if seen.is_a?(Hash)
          end

          ack(index)
          {}
        rescue StandardError # badges are optional: never block the list
          begin
            ack(index)
          rescue StandardError
            nil
          end
          {}
        end

        def ack(index)
          FileUtils.mkdir_p(cache_root)
          versions = {}
          index['items'].each { |i| versions[i['code']] = i['version'] }
          File.write(File.join(cache_root, 'seen.json'), JSON.generate(versions))
        end

        # "อัปเดตในงาน": outdated = { code => [old definition names] }. Downloads every missing file first and
        # touches the model only when all are here. Yields (ok, error_message)
        def update(outdated, model = active_model, &done)
          updates = outdated.map do |code, names|
            item = index['items'].find { |i| i['code'] == code }
            { 'code' => code, 'version' => item['version'], 'old_names' => names, 'path' => file_path(cache_root, item) }
          end
          missing = updates.reject { |u| File.exist?(u['path']) }
          failures = []
          finish = lambda do
            next done.call(false, "ดาวน์โหลดไม่ได้: #{failures.join(', ')} — ยังไม่ได้แก้ไฟล์งาน") unless failures.empty?
            next done.call(false, 'สลับไฟล์ระหว่างดาวน์โหลด — กดอัปเดตอีกครั้ง') unless active_model.equal?(model)

            ModelUpdate.apply(model, updates)
            done.call(true, nil)
          end
          return finish.call if missing.empty?

          pending_count = missing.size
          missing.each do |u|
            item = index['items'].find { |i| i['code'] == u['code'] }
            download(item_url(item), u['path']) do |ok, error|
              failures << "#{u['code']} (#{error})" unless ok
              pending_count -= 1
              begin
                finish.call if pending_count.zero?
              rescue StandardError => e
                done.call(false, "อัปเดตไม่สำเร็จ: #{e.message}")
              end
            end
          end
        rescue StandardError => e
          done.call(false, "อัปเดตไม่สำเร็จ: #{e.message}")
        end

        # Yields (ok, error_message)
        def download(url, path, &done)
          http_get(url) do |status, body, error|
            next done.call(false, error || "HTTP #{status}") unless status == 200

            begin
              FileUtils.mkdir_p(File.dirname(path))
              File.binwrite("#{path}.part", body)
              File.rename("#{path}.part", path)
            rescue StandardError => e
              next done.call(false, e.message)
            end
            done.call(true, nil)
          end
        end

        # Async GET on Sketchup::Http (like the Hub's http.rb). Yields (status_code, body, error_message)
        def http_get(url, &done)
          request = Sketchup::Http::Request.new(url, Sketchup::Http::GET)
          pending << request # keep a reference so the request is not garbage collected mid-flight
          request.start do |req, response|
            pending.delete(req)
            status = response ? response.status_code.to_i : 0
            status.zero? ? done.call(nil, nil, 'network error') : done.call(status, response.body, nil)
          end
        rescue StandardError => e
          done.call(nil, nil, e.message)
        end

        private

        def valid_index?(data)
          return false unless data.is_a?(Hash) && data['schema'] == 2
          return false unless data['items'].is_a?(Array) && data['categories'].is_a?(Array)

          data['items'].all? do |i|
            i.is_a?(Hash) && i['code'].is_a?(String) && [i['file'], i['version']].all? { |v| v.is_a?(String) && v =~ SAFE_NAME && !v.include?('..') }
          end
        end

        def pending
          @pending ||= []
        end

        def cached_index
          path = File.join(cache_root, 'index.json')
          File.exist?(path) ? parse_index(File.read(path, encoding: 'UTF-8')) : nil
        rescue Error
          nil
        end

        def save_index(body, fresh)
          root = cache_root
          FileUtils.mkdir_p(root)
          File.write(File.join(root, 'index.json'), body)
          stale_dirs(root, fresh['items'].map { |i| i['version'] }).each { |dir| FileUtils.rm_rf(dir) }
        end

        def load_and_place(model, path, item)
          definition = model.definitions.load(path)
          ModelUpdate.mark(definition, item['code'], item['version'])
          place_definition(model, definition)
        end

        def place_definition(model, definition)
          model.place_component(definition)
          true
        end
      end
    end
  end
end
