# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# A time in a history says which zone it is in: UTC, with the exact moment in
# the page for anything reading it.
describe 'Times in the histories' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    task = create_task('Pay', under_activity: create_activity('Check out', for_personas: [create_persona('Shopper')]))
    @story = create_story('Pay by card', under_task: task)
  end

  it "stamps a story's history in UTC" do
    visit_story_history(@story)

    assert_stamped_in_utc
  end

  it "stamps the map's history in UTC" do
    visit_map_history

    assert_stamped_in_utc
  end

  it "stamps the settings' history in UTC" do
    update_settings(aging_days: 5, stale_days: 10)
    visit_settings

    assert_stamped_in_utc
  end
end
