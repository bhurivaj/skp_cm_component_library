# frozen_string_literal: true

# Run (no SketchUp needed): ruby tests/tc_hub_link.rb
require 'minitest/autorun'
require_relative '../skp_cm_component_library/hub_link'

class TestHubLink < Minitest::Test
  L = SkpCm::ComponentLibrary::HubLink

  # Stands in for SkpCm::ExtensionsHub::Auth
  class FakeAuth
    attr_reader :login_shown

    def logged_in?
      true
    end

    def username
      'u'
    end

    def uid
      nil
    end

    def show_login
      @login_shown = true
    end
  end

  def install_hub(auth)
    SkpCm.const_set(:ExtensionsHub, Module.new) unless SkpCm.const_defined?(:ExtensionsHub, false)
    remove_hub
    SkpCm::ExtensionsHub.const_set(:Auth, auth)
  end

  def remove_hub
    hub = SkpCm.const_defined?(:ExtensionsHub, false) ? SkpCm::ExtensionsHub : nil
    hub.send(:remove_const, :Auth) if hub && hub.const_defined?(:Auth, false)
  end

  def teardown
    remove_hub
  end

  def test_without_hub
    assert_equal false, L.status['hub']
    assert_equal false, L.show_login
    assert_nil L.watch { |_| nil }
  end

  def test_status_with_hub_logged_in_offline
    install_hub(FakeAuth.new)
    assert_equal({ 'hub' => true, 'logged_in' => true, 'username' => 'u', 'online' => false }, L.status)
  end

  def test_show_login_opens_hub_login
    auth = FakeAuth.new
    install_hub(auth)
    assert_equal true, L.show_login
    assert auth.login_shown
  end
end
