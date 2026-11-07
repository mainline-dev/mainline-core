# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Delete team confirmation (browser)' do
  include MainlineDSL

  before do
    setup_team(name: "nat's Mainline")
    @alice = add_person(name: 'Alice')
    @team.update(creator_id: @alice.id)
  end

  it 'enables the delete button when the team name contains an apostrophe' do
    use_browser!

    driver.visit "/teams/#{@team.id}/account/delete"

    assert_selector '#delete-btn[disabled]'

    fill_in 'confirmation', with: "DELETE nat's Mainline"

    assert_selector '#delete-btn:not([disabled])'
  end
end
