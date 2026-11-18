# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/oauth_dsl'

# The consent page holds its buttons once the person has answered, as the
# app's other forms do, so an answer pressed twice in a hurry is one answer.
describe 'Signing in a coding agent (browser)' do
  include MainlineDSL
  include OauthDsl

  before do
    turn_oauth_on
    setup_team(name: 'Payments')
    @alice = add_person(name: 'Alice')
    login_as(@alice)
    client_publishes(OauthDsl::CLAUDE_CODE, name: 'Claude Code', redirect_uris: ['http://127.0.0.1/teams'])
    use_browser!
    start_sign_in_in_this_browser
  end

  after { forget_client_documents }

  it 'signs the app in once when Approve is pressed twice in a hurry' do
    press_twice('oauth-approve')

    assert_equal 1, app_sign_ins_made
  end

  it 'still sends the answer the person pressed' do
    press_twice('oauth-approve')

    assert_equal ['Payments'], teams_given_by_last_sign_in
  end
end
