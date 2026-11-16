# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mcp_dsl'

# A form a person posts carries a security token, checked on every request
# outside tests. These scenarios turn the check on to show what it refuses,
# and what it lets through: the paths machines call, which answer for
# themselves.
describe 'Security tokens' do
  include MainlineDSL
  include McpDSL

  before do
    setup_team
    make_account_holder(add_person(name: 'Alice'))
    create_map
    activity = create_activity('Browse', for_personas: [create_persona('User')])
    @story = create_story('Show results', under_task: create_task('Search', under_activity: activity))
    DEPLOY_AUTH_RATE_LIMITER.reset
    MCP_RATE_LIMITER.reset
  end

  it 'refuses a form a person posts without its security token' do
    assert(refused_without_security_token? { request_login_link('alice@example.test') })
  end

  it 'lets a deploy pipeline report a deploy without one' do
    generate_webhook_token

    response = with_csrf_checked { api_deploy(story_ids: [@story.id]) }

    assert_equal 200, response.status
  end

  it 'lets a coding agent call the MCP server without one' do
    generate_mcp_token

    response = with_csrf_checked { mcp_initialize }

    assert_equal 200, response.status
  end
end
