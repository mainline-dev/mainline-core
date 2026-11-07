# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Deploy webhook' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    persona  = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    task     = create_task('Search', under_activity: activity)
    @story   = create_story('Show results', under_task: task)
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    @story.refresh
    @team.update(creator_id: @alice.id)
    DEPLOY_AUTH_RATE_LIMITER.reset
  end

  it 'only the account holder can rotate the webhook token' do
    login_as(@bob)

    driver.submit_generate_webhook_token(@team)
    @team.refresh

    assert_nil @team.webhook_token
  end

  it 'rotating the webhook token records an event' do
    generate_webhook_token

    event = Event.where(entity_id: @team.id, action: 'webhook_token_rotated').first

    refute_nil event
  end

  it 'shows the deploy address under the base url of this install' do
    generate_webhook_token

    visit_webhook_settings

    assert_page_includes "#{ENV.fetch('BASE_URL')}/api/teams/#{@team.id}/deploys"
  end

  it 'deploys active stories via webhook' do
    generate_webhook_token

    api_deploy(story_ids: [@story.id])

    @story.refresh

    assert_equal 1, @story.deploy_count
    refute_nil @story.first_deployed_at
  end

  it 'accepts short story ID prefix (case-insensitive)' do
    generate_webhook_token

    short_id = @story.id[0, 8].upcase
    api_deploy(story_ids: [short_id])

    @story.refresh

    assert_equal 1, @story.deploy_count
  end

  it 'rejects request with invalid token' do
    generate_webhook_token

    response = api_deploy(story_ids: [@story.id], token: 'bad-token')

    assert_equal 401, response.status

    @story.refresh

    assert_equal 0, @story.deploy_count
  end

  it 'rejects request when no token configured' do
    response = api_deploy(story_ids: [@story.id], token: 'anything')

    assert_equal 401, response.status
  end

  it 'ignores non-active stories' do
    generate_webhook_token
    planned = create_story('Planned', under_task: Task.where(map_id: @map.id).first)

    api_deploy(story_ids: [planned.id, @story.id])

    planned.refresh
    @story.refresh

    assert_equal 0, planned.deploy_count
    assert_equal 1, @story.deploy_count
  end

  it 'uses system actor for deploy events' do
    generate_webhook_token

    api_deploy(story_ids: [@story.id])

    event = Event.where(entity_id: @story.id, action: 'deployed').first

    refute_nil event
    actor = Actor[event.actor_id]

    assert_equal 'system', actor.kind
    assert_includes actor.name, 'Webhook'
  end

  it 'returns deployed story count in response' do
    generate_webhook_token

    response = api_deploy(story_ids: [@story.id])

    assert_equal 200, response.status
    body = JSON.parse(response.body)

    assert_equal 1, body['deployed']
  end

  it 'rejects deploy when the team is suspended' do
    generate_webhook_token
    suspend_team

    response = api_deploy(story_ids: [@story.id])

    assert_equal 403, response.status
  end

  it 'rejects empty request body' do
    generate_webhook_token

    response = api_deploy_raw(body: '')

    assert_equal 400, response.status
    body = JSON.parse(response.body)

    assert_equal 'invalid JSON', body['error']
  end

  it 'rejects malformed JSON body' do
    generate_webhook_token

    response = api_deploy_raw(body: '{not json')

    assert_equal 400, response.status
    body = JSON.parse(response.body)

    assert_equal 'invalid JSON', body['error']
  end

  it 'rejects story IDs with LIKE wildcards' do
    generate_webhook_token

    api_deploy(story_ids: ['%'])

    @story.refresh

    assert_equal 0, @story.deploy_count
  end

  it 'rejects story IDs with non-hex characters' do
    generate_webhook_token

    api_deploy(story_ids: ['zzzz'])

    @story.refresh

    assert_equal 0, @story.deploy_count
  end

  it 'rate limits failed auth attempts' do
    generate_webhook_token
    DEPLOY_AUTH_RATE_LIMITER.reset

    11.times { api_deploy(story_ids: [@story.id], token: 'bad-token') }

    response = api_deploy(story_ids: [@story.id], token: 'bad-token')

    assert_equal 429, response.status
  end

  it 'returns JSON 404 for unknown team' do
    post '/api/teams/00000000-0000-0000-0000-000000000000/deploys',
      JSON.generate({ story_ids: [] }),
      { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer x' }

    assert_equal 404, last_response.status
    assert_equal 'application/json', last_response.content_type
  end

  it 'returns JSON 404 for invalid path under /api/' do
    get '/api/nonexistent'

    assert_equal 404, last_response.status
    assert_equal 'application/json', last_response.content_type
  end
end

describe 'Deploy - manual button' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    persona  = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    task     = create_task('Search', under_activity: activity)
    @story   = create_story('Show results', under_task: task)
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    @story.refresh
  end

  it 'shows deploy button on active stories in map view' do
    visit_map

    body = page_body

    assert_includes body, "/stories/#{@story.id}/deploy"
  end

  it 'manual deploy uses person actor' do
    deploy_story(@story)

    event = Event.where(entity_id: @story.id, action: 'deployed').first

    refute_nil event

    assert_equal @alice.actor_id, event.actor_id
  end
end

describe 'Deploy - notification banner' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
  end

  it 'shows webhook link in team nav dropdown' do
    visit_team_dashboard

    body = page_body

    assert_includes body, "/teams/#{@team.id}/webhook"
  end
end

describe 'Deploy - short story ID' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    persona  = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    task     = create_task('Search', under_activity: activity)
    @story   = create_story('Show results', under_task: task)
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
  end

  it 'displays short ID on story card in map view' do
    visit_map

    body = page_body
    short_id = @story.id[0, 8].upcase

    assert_includes body, short_id
  end
end
