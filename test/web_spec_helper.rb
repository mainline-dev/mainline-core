# test/web_spec_helper.rb
# frozen_string_literal: true

require_relative 'coverage_helper'
ENV['RACK_ENV'] = 'test'
require_relative '../app'
Tilt.finalize!

raise "test database doesn't end with test" if DB.opts[:database] && !DB.opts[:database].end_with?('test')

# Overlapping test runs share one Redis; each run keeps its login link marks
# under its own prefix so one run's cleanup cannot clear another's.
LoginLinkThrottle.prefix = "login_link_sent:#{SecureRandom.hex(4)}:"
SharedRateLimiter.prefix = "rate_limit:#{SecureRandom.hex(4)}:"

require 'monitor'
require 'capybara'
require 'capybara/dsl'
require 'capybara/cuprite'
require 'rack/test'
require 'omniauth'

OmniAuth.config.test_mode = true
OmniAuth.config.allowed_request_methods = [:post]

Gem.suffix_pattern

require_relative 'test_helper'

Mainline.plugin :not_found do
  raise "404 - Not Found: #{request.request_method} #{request.path_info}" unless request.path_info == '/favicon.ico'
end
Mainline.plugin :error_handler do |e|
  raise e
end

Mainline.freeze if ENV['NO_AUTOLOAD']
Capybara.app = Mainline.app
Capybara.exact = true
Capybara.server = :webrick
# First page load of a run pays Chrome launch + WEBrick warm-up, which can
# exceed the 2s default and fail whichever test happens to run first.
Capybara.default_max_wait_time = 10
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    browser_options:           { 'no-sandbox': nil },
    headless:                  ENV['HEADED'] != '1',
    pending_connection_errors: false,
    # Chrome can take longer than the default 10 seconds to start on a cold CI runner.
    process_timeout:           30
  )
end
Capybara.javascript_driver = :cuprite

# A failed browser test leaves a screenshot and the page HTML here, so a
# failure that does not repeat can still be looked at. Cleared each run.
BROWSER_FAILURES = File.expand_path('../tmp/browser-failures', __dir__)
FileUtils.rm_rf(BROWSER_FAILURES)

# Chrome 147+ aggressively GCs CDP Runtime object handles, breaking Ferrum's
# JS-based find (array handles go stale before individual nodes are resolved).
# Bypass the Runtime layer for CSS selectors by using DOM.querySelectorAll.
module CupriteDomFind
  private

  def node_ids_to_ferrum(node_ids)
    node_ids.filter_map { |nid|
      next if nid.zero?

      desc = page.command('DOM.describeNode', nodeId: nid)['node']
      Ferrum::Node.new(page.main_frame, page.target_id, nid, desc)
    }
  end

  def dom_css(parent_node_id, selector)
    ids = page.command('DOM.querySelectorAll', nodeId: parent_node_id, selector: selector)['nodeIds']
    node_ids_to_ferrum(ids)
  end

  def remote_object_to_node(remote_id)
    node = page.command('DOM.requestNode', objectId: remote_id)
    nid = node['nodeId']
    return if nid.zero?

    desc = page.command('DOM.describeNode', nodeId: nid)['node']
    Ferrum::Node.new(page.main_frame, page.target_id, nid, desc)
  rescue Ferrum::BrowserError
    nil
  end

  def dom_xpath(selector)
    page.command('DOM.getDocument', depth: 0)
    js = <<~JS
      (function() {
        var r = document.evaluate(
          #{selector.to_json}, document, null,
          XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null
        );
        var ids = [];
        for (var i = 0; i < r.snapshotLength; i++) ids.push(r.snapshotItem(i));
        return ids;
      })()
    JS
    result = page.command('Runtime.evaluate', expression: js, returnByValue: false)
    object_id = result.dig('result', 'objectId')
    return [] unless object_id

    props = page.command('Runtime.getProperties', objectId: object_id, ownProperties: true)
    props['result'].filter_map { |prop|
      remote_id = prop.dig('value', 'objectId')
      next unless remote_id

      remote_object_to_node(remote_id)
    }
  end

  def find_all(method, selector, within = nil)
    return super unless within.nil?

    if method.to_s == 'css'
      root_id = page.command('DOM.getDocument', depth: 0).dig('root', 'nodeId')
      dom_css(root_id, selector)
    else
      dom_xpath(selector)
    end
  end

  def find_within(node, method, selector)
    return dom_css(node.node_id, selector) if method.to_s == 'css'

    super
  end
end
Capybara::Cuprite::Browser.prepend(CupriteDomFind)

class Minitest::HooksSpec
  include Rack::Test::Methods
  include Capybara::DSL

  def app
    Capybara.app
  end

  # Share the test thread's DB connection with the Capybara server thread.
  # Without this, the server thread gets its own connection from the pool
  # and can't see data inside the test's rollback transaction.
  def enable_shared_connection!
    return if @_shared_connection_enabled

    test_conn = DB.synchronize { |c| c }
    mu = Monitor.new
    @_original_hold = DB.pool.method(:hold)
    DB.pool.define_singleton_method(:hold) do |_server = :default, &block|
      mu.synchronize { block.call(test_conn) }
    end
    @_shared_connection_enabled = true
  end

  def disable_shared_connection!
    if @_original_hold
      DB.pool.singleton_class.remove_method(:hold)
      @_original_hold = nil
    end
    @_shared_connection_enabled = false
  end

  def save_browser_failure
    return if passed? || skipped? || Capybara.current_driver != :cuprite

    path = File.join(BROWSER_FAILURES, "#{self.class.name}_#{name}".gsub(/\W+/, '_'))
    FileUtils.mkdir_p(BROWSER_FAILURES)
    page.driver.browser.screenshot(path: "#{path}.png", full: true)
    File.write("#{path}.html", page.html)
    puts "\nBrowser failure saved: #{path}.png"
  rescue StandardError => e
    puts "\nBrowser failure not saved: #{e.message}"
  end

  # A request still in flight when a test ends reaches the server after its
  # data is rolled back, and the 404 lands in whichever test runs next.
  def let_the_browser_settle
    return if Capybara.current_driver == Capybara.default_driver

    page.driver.wait_for_network_idle(timeout: 2)
  rescue StandardError => e
    puts "\nBrowser did not settle: #{e.message}"
  end

  after do
    save_browser_failure
    let_the_browser_settle
    AUTH_RATE_LIMITER.reset
    LOGIN_GLOBAL_LIMITER.reset
    LOGIN_EMAIL_LIMITER.reset
    LoginLinkThrottle.reset
    disable_shared_connection!
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end
end
