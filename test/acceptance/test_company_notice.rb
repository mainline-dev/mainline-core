# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# The company's copyright and trade mark notice belongs on the pages the
# public sees. Someone signed in and working keeps the whole screen for the
# work, the story map most of all.
describe 'Company notice' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
    create_map
  end

  it "is left off a signed-in person's team page" do
    visit_team_dashboard

    refute_shown('app-footer')
  end

  it "is left off a signed-in person's story map" do
    visit_map

    refute_shown('app-footer')
  end
end
