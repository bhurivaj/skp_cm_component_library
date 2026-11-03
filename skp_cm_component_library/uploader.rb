# frozen_string_literal: true

require 'net/http'
require 'uri'

module SkpCm
  module ComponentLibrary
    # Uploads one Publish to Azure with the owner's container SAS (update spec §4.3).
    # One file per timer tick so SketchUp stays responsive; index.json goes last.
    module Uploader
      CONTAINER_URL = 'https://sketchup.blob.core.windows.net/component-library'
      BAD_SAS = 'SAS ไม่ถูกต้อง (มีช่องว่างหรืออักขระแปลก) — กด Publish ใหม่แล้วใส่ SAS ใหม่'

      module_function

      # [[local_path, blob_name], …] — components, thumbs, then library/index.json
      def plan(dir, version)
        files = %w[components thumbs].flat_map do |kind|
          Dir.glob(File.join(dir, kind, '*')).sort.map { |p| [p, "library/#{version}/#{kind}/#{File.basename(p)}"] }
        end
        files << [File.join(dir, 'index', 'index.json'), 'library/index.json']
      end

      def content_type(path)
        { '.json' => 'application/json', '.png' => 'image/png' }.fetch(File.extname(path).downcase, 'application/octet-stream')
      end

      # put: ->(blob, path, sas) { [status, message] }; schedule: ->(&step) runs step later.
      # done.call(true, nil, nil) or (false, message, status) — stops at the first file that fails twice
      def run(files, sas, put: method(:http_put), schedule: method(:next_tick), on_progress: nil, &done)
        step = lambda do |i, tries|
          return done.call(true, nil, nil) if i >= files.size

          path, blob = files[i]
          status, message = begin
            put.call(blob, path, sas)
          rescue StandardError => e
            [0, e.message]
          end
          if status.to_i.between?(200, 299)
            on_progress.call(i + 1, files.size) if on_progress
            schedule.call { step.call(i + 1, 0) }
          elsif tries.zero?
            schedule.call { step.call(i, 1) }
          else
            done.call(false, "upload #{blob} ไม่ได้ (#{status.to_i.zero? ? message : "HTTP #{status}"})", status.to_i)
          end
        end
        step.call(0, 0)
      end

      def next_tick(&step)
        UI.start_timer(0, false) { step.call }
      end

      # index.json must never be cached by clients, or the team keeps seeing the previous publish
      def headers(blob, path)
        h = { 'x-ms-blob-type' => 'BlockBlob', 'x-ms-version' => '2021-08-06', 'Content-Type' => content_type(path) }
        h['x-ms-blob-cache-control'] = 'no-cache' if blob == 'library/index.json'
        h
      end

      # Never logs the SAS
      def http_put(blob, path, sas)
        return [0, BAD_SAS] unless sas =~ /\A\??[\w%=&.:+\-\/]+\z/

        uri = URI("#{CONTAINER_URL}/#{blob.split('/').map { |s| URI.encode_www_form_component(s).gsub('+', '%20') }.join('/')}?#{sas.sub(/\A\?/, '')}")
        request = Net::HTTP::Put.new(uri)
        headers(blob, path).each { |k, v| request[k] = v }
        request.body = File.binread(path)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 120) do |http|
          http.request(request)
        end
        [response.code.to_i, response.message]
      rescue URI::Error
        [0, BAD_SAS] # never echo the URL: it holds the SAS
      end
    end
  end
end
