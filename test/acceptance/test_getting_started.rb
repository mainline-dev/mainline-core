# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Getting started hint' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
  end

  it 'shows tutorial link on team dashboard when no maps' do
    visit_team_dashboard

    assert_page_includes('docs/tutorial')
  end

  it 'hides tutorial link on team dashboard when maps exist' do
    create_map

    visit_team_dashboard

    refute_page_includes('getting-started-hint')
  end

  it 'shows tutorial link on team picker when no maps' do
    resp = driver.visit_teams

    assert_includes resp.body, 'docs/tutorial'
  end

  it 'hides tutorial link on team picker when maps exist' do
    create_map

    resp = driver.visit_teams

    refute_includes resp.body, 'getting-started-hint'
  end
end
