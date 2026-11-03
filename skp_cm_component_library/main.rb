# frozen_string_literal: true

require 'sketchup.rb'
require 'json'
require_relative 'hub_link'
require_relative 'library'
require_relative 'model_update'
require_relative 'publisher'
require_relative 'publish_flow'

module SkpCm
  module ComponentLibrary
    # Window "Component Library" (spec §4.3 layout A + update spec §5)
    module Dialog
      class << self
        def show
          return @dialog.bring_to_front if @dialog && @dialog.visible?

          @dialog = UI::HtmlDialog.new(
            dialog_title: PLUGIN_NAME,
            preferences_key: 'skp_cm_component_library_dialog',
            width: 640, height: 560, min_width: 420, min_height: 320,
            resizable: true, style: UI::HtmlDialog::STYLE_DIALOG
          )
          @dialog.set_file(File.join(PLUGIN_DIR, 'library.html'))
          @dialog.add_action_callback('ready') { |_ctx| guard { refresh } }
          @dialog.add_action_callback('refresh') { |_ctx| guard { refresh } }
          @dialog.add_action_callback('login') { |_ctx| guard { HubLink.show_login } }
          @dialog.add_action_callback('place') { |_ctx, code| guard { place(code.to_s) } }
          @dialog.add_action_callback('update') { |_ctx| guard { update } }
          @dialog.add_action_callback('ack') { |_ctx| guard { ack } }
          listener = HubLink.watch { |_logged_in| guard { refresh } }
          @dialog.set_on_closed { HubLink.unwatch(listener) }
          @dialog.show
        end

        # Model switched / opened (AppObserver) — recount old components in the new active model
        def model_changed
          guard { push_outdated } if @dialog && @dialog.visible?
        end

        private

        # Shows the Hub status; loads the list only when logged in (spec §4.4)
        def refresh
          status = HubLink.status
          js('showAuth', status, HubLink::MISSING_MESSAGE)
          return unless status['hub'] && status['logged_in']

          Library.load_index do |index, error, offline|
            guard do
              next js('showError', error) unless index

              js('showIndex', index, offline, Library::LIBRARY_URL, Library.seen_changes(index))
              push_outdated
            end
          end
        end

        def outdated
          model = Sketchup.active_model
          return {} if Library.index.nil? || Publisher.structure_set?(model.path)

          ModelUpdate.outdated(ModelUpdate.definition_info(model), Library.index)
        end

        def push_outdated
          js('showOutdated', outdated)
        end

        # after.call(ok, error) runs once the update finished (also when there was nothing to update)
        def update(codes = nil, &after)
          todo = outdated
          todo = todo.select { |code, _| codes.include?(code) } if codes
          if todo.empty?
            push_outdated
            js('updateDone', true, '')
            return after && after.call(true, nil)
          end

          Library.update(todo) do |ok, error|
            guard do
              js('updateDone', ok, ok ? "อัปเดตแล้ว #{todo.size} ตัว" : error)
              push_outdated
              after.call(ok, error) if after
            end
          end
        end

        def ack
          return unless Library.index

          Library.ack(Library.index)
          js('showChanges', {})
        end

        def place(code, existing_ok: false)
          # The Structure Set is the master: never offer to replace its definitions
          existing_ok ||= Publisher.structure_set?(Sketchup.active_model.path)
          Library.place(code, existing_ok: existing_ok) do |ok, error|
            guard do
              next ask_outdated(code) if ok == :outdated

              js('placeDone', code, ok, error)
              push_outdated if ok
            end
          end
        end

        # Update spec E: the model already holds an older version of code
        def ask_outdated(code)
          model = Sketchup.active_model
          names = outdated[code] || [code]
          count = names.sum { |n| (d = model.definitions[n]) ? d.instances.size : 0 }
          answer = UI.messagebox("ไฟล์นี้มี #{code} เวอร์ชันเก่า #{count} ตัว\n\n" \
                                 "Yes = อัปเดตทั้งหมดเป็นเวอร์ชันใหม่ แล้ววางตัวใหม่\nNo = วางตัวเดิม", MB_YESNO)
          return place(code, existing_ok: true) unless answer == IDYES

          update([code]) do |ok, error|
            ok ? place(code, existing_ok: true) : js('placeDone', code, false, error)
          end
        end

        def js(function, *args)
          return unless @dialog && @dialog.visible?

          @dialog.execute_script("window.#{function} && window.#{function}(#{args.map { |a| JSON.generate(a) }.join(',')})")
        end

        def guard
          yield
        rescue StandardError => e
          puts "#{PLUGIN_NAME}: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          js('showError', "เกิดข้อผิดพลาด: #{e.message}")
        end
      end
    end

    # Recount old components when the user switches or opens a model
    class ModelWatcher < Sketchup::AppObserver
      def onActivateModel(_model)
        Dialog.model_changed
      end

      def onOpenModel(_model)
        Dialog.model_changed
      end

      def onNewModel(_model)
        Dialog.model_changed
      end
    end

    unless file_loaded?(__FILE__)
      open_cmd = UI::Command.new('Component Library') { Dialog.show }
      open_cmd.tooltip = 'เลือก component มาตรฐานมาวางในงาน'
      icon = File.join(PLUGIN_DIR, 'icons', 'library_icon.png')
      open_cmd.large_icon = open_cmd.small_icon = icon if File.exist?(icon)

      menu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)
      menu.add_item(open_cmd)
      menu.add_separator
      menu.add_item('Publish ทั้งหมด…') { PublishFlow.run_all }
      menu.add_item('Publish ตัวที่เลือก') { PublishFlow.run_selected }

      UI.add_context_menu_handler do |context|
        model = Sketchup.active_model
        if Publisher.structure_set?(model.path) && model.selection.grep(Sketchup::ComponentInstance).any?
          context.add_item('Publish ตัวที่เลือก (Component Library)') { PublishFlow.run_selected }
        end
      end

      toolbar = UI::Toolbar.new('SKP CM Component Library')
      toolbar.add_item(open_cmd)
      toolbar.show
      Sketchup.add_observer(ModelWatcher.new)
      file_loaded(__FILE__)
    end
  end
end
