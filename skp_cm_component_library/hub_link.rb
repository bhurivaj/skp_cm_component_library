# frozen_string_literal: true

module SkpCm
  module ComponentLibrary
    # The only place that knows SKP CM Extensions Hub. Looked up at call time:
    # SketchUp loads plugins in file-name order, so the Hub may load after this plugin.
    module HubLink
      MISSING_MESSAGE = "ต้องติดตั้งหรืออัปเดต SKP CM Extensions Hub (0.4.0 ขึ้นไป) แล้ว restart SketchUp\n" \
                        'https://github.com/bhurivaj/skp_cm_extensions_hub/releases/latest'

      class << self
        # SkpCm::ExtensionsHub::Auth, or nil when the Hub is missing, disabled or older than 0.4.0
        def auth
          defined?(SkpCm::ExtensionsHub::Auth) ? SkpCm::ExtensionsHub::Auth : nil
        end

        def status
          hub = auth
          return { 'hub' => false, 'logged_in' => false, 'username' => nil, 'online' => false } unless hub

          { 'hub' => true, 'logged_in' => hub.logged_in?, 'username' => hub.username, 'online' => !hub.uid.nil? }
        end

        # Returns the listener to pass to unwatch, or nil when there is no Hub
        def watch(&listener)
          hub = auth
          hub ? hub.on_change(&listener) : nil
        rescue StandardError => e
          puts "#{PLUGIN_NAME}: #{e.class}: #{e.message}"
          nil
        end

        def unwatch(listener)
          hub = auth
          hub.off_change(listener) if hub && listener
        end

        def show_login
          hub = auth
          return false unless hub

          hub.show_login
          true
        end
      end
    end
  end
end
