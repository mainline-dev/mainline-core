# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Story slide-over panel (browser)' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    persona  = create_persona('Customer')
    activity = create_activity('Browse', for_personas: [persona])
    task     = create_task('Search', under_activity: activity)
    @story   = create_story('Find things', under_task: task)
  end

  it 'click story title opens panel with edit form' do
    use_browser!
    driver.visit_map(@map)

    find('[data-test-id="story-title-find-things"]').click

    assert_selector '[data-test-id="story-panel"]', wait: 5
    within '[data-test-id="story-panel"]' do
      assert_selector 'input[type="text"]'
    end
  end

  # The panel slides in, and a click aimed at a moving button can miss it.
  def wait_for_panel_to_settle
    settled = "document.querySelector('[data-test-id=\"story-panel\"]').getAnimations().length === 0"
    page.document.synchronize(5, errors: [Capybara::ExpectationNotMet]) do
      raise Capybara::ExpectationNotMet, 'the panel is still sliding in' unless page.evaluate_script(settled)
    end
  end

  it 'close button dismisses the panel' do
    use_browser!
    driver.visit_map(@map)

    find('[data-test-id="story-title-find-things"]').click

    assert_selector '[data-test-id="story-panel"]', wait: 5
    wait_for_panel_to_settle

    find('[data-test-id="panel-close"]').click

    assert_no_selector '[data-test-id="story-panel"]', wait: 5
  end

  it 'save in panel persists the title change' do
    use_browser!
    driver.visit_map(@map)

    find('[data-test-id="story-title-find-things"]').click

    assert_selector '[data-test-id="story-panel"]', wait: 3

    within '[data-test-id="story-panel"]' do
      fill_in 'title', with: 'Search results'
      find('#story-form-container button[type="submit"]:not([disabled])', wait: 2)
    end

    page.evaluate_script('htmx.trigger(document.querySelector("#story-form-container form"), "submit")')

    assert_selector '#story-form-container button.btn-saved', wait: 3

    @story.refresh

    assert_equal 'Search results', @story.title

    assert_selector ".story-card[data-id=\"#{@story.id}\"] .card-body a", text: 'Search results', wait: 5
  end
end
