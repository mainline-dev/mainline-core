# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# The cross on a scenario asks before it deletes. The way to keep the scenario
# sits where the cross was, so a second click on the same spot keeps it.
describe 'Deleting a scenario (browser)' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    activity = create_activity('Browse', for_personas: [create_persona('Customer')])
    @story = create_story('Find things', under_task: create_task('Search', under_activity: activity))
    create_scenario(@story, given_text: 'a full shop', when_text: 'a guest searches', then_text: 'matches are listed')
    use_browser!
    visit "/maps/#{@map.id}/stories/#{@story.id}/edit"
  end

  def cross
    find('[data-test-id="scenario-delete"]')
  end

  def middle_of_the_cross
    evaluate_script(<<~JS)
      (function() {
        var box = document.querySelector('[data-test-id="scenario-delete"]').getBoundingClientRect();
        return [box.left + box.width / 2, box.top + box.height / 2];
      })()
    JS
  end

  it 'asks first, with a way to delete and a way to keep' do
    cross.click

    assert_selector '[data-test-id="scenario-delete-ask"]'
    assert_selector '[data-test-id="scenario-delete-yes"]'
    assert_selector '[data-test-id="scenario-keep"]'
    assert_selector '[data-test-id="scenario-name"]'
  end

  it 'keeps the scenario when the same spot is clicked a second time' do
    x, y = middle_of_the_cross
    page.driver.click(x, y)

    assert_selector '[data-test-id="scenario-keep"]'
    page.driver.click(x, y)

    assert_no_selector '[data-test-id="scenario-keep"]'
    assert_selector '[data-test-id="scenario-delete"]'
    assert_selector '[data-test-id="scenario-name"]'
  end

  it 'goes on asking until someone answers' do
    cross.click
    sleep 3.2

    assert_selector '[data-test-id="scenario-keep"]'
    assert_selector '[data-test-id="scenario-name"]'
  end

  it 'deletes the scenario on Delete' do
    cross.click
    find('[data-test-id="scenario-delete-yes"]').click

    assert_no_selector '[data-test-id="scenario-name"]'
  end
end
