# frozen_string_literal: true

# Requires web_spec_helper.rb to be loaded first (for Capybara setup).
# Not used until slice 17 (drag-and-drop) or when verifying HTMX behavior.

require_relative 'records'
require_relative 'oauth_records'

class BrowserDriver
  include Capybara::DSL
  include Records
  include OauthRecords

  def login_as(person)
    visit "/_test_login?person_id=#{person.id}"
  end

  def visit_map(map)
    visit "/maps/#{map.id}"
  end

  def visit_map_slices(map)
    visit "/maps/#{map.id}?slices=1"
  end

  TEMPLATE_LABELS = {
    'connextra' => 'As a... I want to... so that...',
    'card'      => 'Persona does thing',
    'behaviour' => 'When... persona can...'
  }.freeze

  def submit_create_story_from_template(map, attrs)
    visit "/maps/#{map.id}/stories/new?task_id=#{attrs[:task_id]}"
    select TEMPLATE_LABELS.fetch(attrs[:template]), from: 'template'

    case attrs[:template]
    when 'connextra'
      fill_in 'role',    with: attrs[:role]
      fill_in 'goal',    with: attrs[:goal]
      fill_in 'benefit', with: attrs[:benefit]
    when 'card'
      fill_in 'card_persona', with: attrs[:persona]
      fill_in 'card_action',  with: attrs[:action]
    when 'behaviour'
      fill_in 'beh_context', with: attrs[:context]
      fill_in 'beh_persona', with: attrs[:persona]
      fill_in 'beh_action',  with: attrs[:action]
    end

    send_form 'Create Story'
  end

  # Clicks the form's button, then waits for the browser to leave the form's
  # page. A click on its own waits for a page load only if one begins within
  # a tenth of a second, and a busy browser can take longer than that to send
  # a form, so the step would return before the form had been answered.
  def send_form(button)
    form = current_url
    click_on button

    assert_no_current_path(form, url: true)
  end

  def visit_team_dashboard(team)
    visit "/teams/#{team.id}"
  end

  def visit_teamwork(team, lens: nil)
    url = "/teams/#{team.id}/teamwork"
    url += "?lens=#{lens}" if lens
    visit url
  end

  def visit_flow(team, days: nil)
    url = "/teams/#{team.id}/flow"
    url += "?days=#{days}" if days
    visit url
  end

  def visit_throughput(team, days: nil, lens: nil)
    url = "/teams/#{team.id}/flow/throughput"
    params = []
    params << "days=#{days}" if days
    params << "lens=#{lens}" if lens
    url += "?#{params.join('&')}" if params.any?
    visit url
  end

  def visit_lead_time(team, days: nil)
    url = "/teams/#{team.id}/flow/lead-time"
    url += "?days=#{days}" if days
    visit url
  end

  def visit_ensemble_timeline(team)
    visit "/teams/#{team.id}/teamwork/ensemble"
  end

  def visit_solo_log(team)
    visit "/teams/#{team.id}/teamwork/solo"
  end

  def visit_inventory(team)
    visit "/teams/#{team.id}/inventory"
  end

  def visit_story_history(map, story)
    visit "/maps/#{map.id}/stories/#{story.id}/history"
  end

  def press_shortcut(*keys)
    find('body').send_keys(*keys)
  end

  def on_path?(path)
    page.has_current_path?(path)
  end

  def response_includes?(text)
    page.has_text?(text)
  end

  # A browser follows each redirect itself.
  def settle; end

  def flash_shown?(kind)
    page.has_css?(%([data-test-id="flash-#{kind}"]))
  end

  def form_errors_shown?
    page.has_css?('[data-test-id="form-errors"]')
  end

  def test_id_shown?(test_id)
    page.has_css?(%([data-test-id="#{test_id}"]))
  end

  # Waits for the element to go, as it may still be on its way out.
  def test_id_gone?(test_id)
    page.has_no_css?(%([data-test-id="#{test_id}"]))
  end

  def visit_edit_story(map, story)
    visit "/maps/#{map.id}/stories/#{story.id}/edit"
  end

  def press(test_id)
    find(%([data-test-id="#{test_id}"])).click
  end

  # The middle of the element on screen, to click the same spot again once
  # something else has taken its place.
  def spot_of(test_id)
    page.evaluate_script(<<~JS)
      (function() {
        var box = document.querySelector('[data-test-id="#{test_id}"]').getBoundingClientRect();
        return [box.left + box.width / 2, box.top + box.height / 2];
      })()
    JS
  end

  def click_at(spot)
    page.driver.click(*spot)
  end

  # From here on in this page, each form waits half a second before it is
  # sent, as a busy browser might. A click waits for a page load only if one
  # begins within a tenth of a second, so this shows whether a step waits for
  # the form's answer itself. Added to this test's page only, which is thrown
  # away when the test ends.
  def send_forms_slowly
    page.driver.browser.page.command('Page.addScriptToEvaluateOnNewDocument', source: <<~JS)
      document.addEventListener('submit', function(event) {
        var form = event.target;
        if (form.dataset.held) return;
        event.preventDefault();
        form.dataset.held = 'yes';
        setTimeout(function() { form.requestSubmit(event.submitter); }, 500);
      }, true);
    JS
  end

  def visit_authorize(params)
    visit "/oauth/authorize?#{URI.encode_www_form(params)}"
  end

  # An address on the test's own server, as the browser reaches it.
  def own_address(path)
    server = Capybara.current_session.server
    "http://#{server.host}:#{server.port}#{path}"
  end

  def press_twice(test_id)
    page.execute_script(<<~JS)
      (function() {
        var button = document.querySelector('[data-test-id="#{test_id}"]');
        button.click();
        setTimeout(function() { button.click(); }, 10);
      })()
    JS
    page.has_no_css?(%([data-test-id="#{test_id}"]))
  end

  def reset!
    Capybara.reset_sessions!
  end
end
