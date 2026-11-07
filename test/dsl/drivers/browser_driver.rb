# frozen_string_literal: true

# Requires web_spec_helper.rb to be loaded first (for Capybara setup).
# Not used until slice 17 (drag-and-drop) or when verifying HTMX behavior.

require_relative 'records'

class BrowserDriver
  include Capybara::DSL
  include Records

  def login_as(person)
    visit "/_test_login?person_id=#{person.id}"
  end

  def visit_map(map)
    visit "/maps/#{map.id}"
  end

  def visit_map_slices(map)
    visit "/maps/#{map.id}?slices=1"
  end

  def submit_create_persona(map, attrs)
    visit "/maps/#{map.id}"
    click_on '+ Persona'
    fill_in 'Name', with: attrs[:name]
    fill_in 'Description', with: attrs.fetch(:description, '') if attrs[:description]
    click_on 'Create Persona'
  end

  def submit_create_activity(map, attrs)
    visit "/maps/#{map.id}"
    click_on '+ Activity'
    fill_in 'Name', with: attrs[:name]
    attrs[:persona_names].each { |name| check name }
    click_on 'Create Activity'
  end

  def submit_create_task(map, attrs)
    visit "/maps/#{map.id}"
    within '.activity-col', text: attrs[:activity_name] do
      click_on '+ Task'
    end
    fill_in 'Name', with: attrs[:name]
    click_on 'Create Task'
  end

  def submit_create_story(map, attrs)
    visit "/maps/#{map.id}"
    within '.tasks-block', text: attrs[:task_name] do
      click_on '+ Story'
    end
    fill_in 'Title', with: attrs[:title]
    click_on 'Create Story'
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

    click_on 'Create Story'
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

  def flash_shown?(kind)
    page.has_css?(%([data-test-id="flash-#{kind}"]))
  end

  def form_errors_shown?
    page.has_css?('[data-test-id="form-errors"]')
  end

  def test_id_shown?(test_id)
    page.has_css?(%([data-test-id="#{test_id}"]))
  end

  def reset!
    Capybara.reset_sessions!
  end
end
