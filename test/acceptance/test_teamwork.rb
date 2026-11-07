# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/mcp_dsl'

describe 'Teamwork - Pairing matrix' do
  include MainlineDSL
  include McpDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    @carol = add_person(name: 'Carol')
    create_map
    persona  = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    @task    = create_task('Search', under_activity: activity)
  end

  it 'shows pairing matrix heading' do
    visit_teamwork

    assert_shown('teamwork-page-matrix')
  end

  it 'shows team members in matrix' do
    visit_teamwork

    body = page_body

    assert_includes body, 'pairing-matrix'
    assert_includes body, 'Alice'
    assert_includes body, 'Bob'
    assert_includes body, 'Carol'
  end

  it 'shows edit profile link in nav for current user' do
    login_as(@alice)
    visit_teamwork

    body = page_body

    assert_includes body, '/profile/edit'
  end

  it 'shows team member names as headers' do
    visit_teamwork

    assert_page_includes('Alice')
    assert_page_includes('Bob')
    assert_page_includes('Carol')
  end

  it 'default lens shows story count for a pair that worked together' do
    story = create_story('Paired work', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    visit_teamwork

    body = page_body

    assert_includes body, 'data-stories="1"'
  end

  it 'shows the agent with the stories it read alongside each person' do
    @team.update(creator_id: @alice.id)
    story = create_story('Agent read', under_task: @task)
    assign_person(story, person: @alice)
    generate_mcp_token
    mcp_initialize
    mcp_call_tool('get_story', arguments: { 'story_id' => story.id })

    visit_teamwork

    assert_shown('matrix-agent')
    assert_includes page_body, %(data-agent-with="#{@alice.id}" data-stories="1")
  end

  it 'has no agent in the matrix until an agent has read a story' do
    visit_teamwork

    refute_shown('matrix-agent')
  end

  it 'days lens shows days since last paired' do
    story = create_story('Paired work', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    visit_teamwork(lens: 'days')

    body = page_body

    assert_includes body, 'data-days='
  end

  it 'shows zero for pairs that never worked together' do
    visit_teamwork

    assert_page_includes('matrix-never')
  end

  it 'shows lens toggle links' do
    visit_teamwork

    body = page_body

    assert_includes body, '?lens=days'
    assert_includes body, '?lens=current'
  end

  it 'current lens shows only live pairs' do
    story = create_story('Active pair', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    visit_teamwork(lens: 'current')

    body = page_body

    assert_includes body, 'matrix-current'
  end
end

describe 'Teamwork - Ensemble Timeline' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    @carol = add_person(name: 'Carol')
    create_map
    persona  = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    @task    = create_task('Search', under_activity: activity)
  end

  it 'shows ensemble sessions on the ensemble timeline page' do
    story = create_story('Ensemble story', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    assign_person(story, person: @carol)

    visit_ensemble_timeline

    assert_shown('teamwork-page-ensemble')
    assert_page_includes('Ensemble story')
    assert_page_includes('Alice')
    assert_page_includes('Bob')
    assert_page_includes('Carol')
  end

  it 'excludes paired-only stories' do
    story = create_story('Pair story', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    visit_ensemble_timeline

    refute_page_includes('Pair story')
  end

  it 'shows team member list' do
    visit_ensemble_timeline

    body = page_body

    assert_includes body, 'teamwork-members'
    assert_includes body, 'Alice'
    assert_includes body, 'Bob'
    assert_includes body, 'Carol'
  end

  it 'shows tab navigation' do
    visit_ensemble_timeline

    assert_page_includes(%(href="/teams/#{@team.id}/teamwork"))
    assert_page_includes(%(href="/teams/#{@team.id}/teamwork/ensemble"))
    assert_page_includes(%(href="/teams/#{@team.id}/teamwork/solo"))
  end

  it 'shows window selector and respects window param' do
    visit_ensemble_timeline

    assert_page_includes('90d')
    assert_page_includes('180d')
    assert_page_includes('1y')
    assert_page_includes('aria-current="true">180d')
  end
end

describe 'Teamwork - Solo Log' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    persona  = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    @task    = create_task('Search', under_activity: activity)
  end

  it 'shows released stories that were shipped solo' do
    story = create_story('Solo ship', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    sa = StoryAssignment.where(story_id: story.id, person_id: @bob.id).first
    unassign_person(story, sa)

    deploy_story(story)
    release_story(story)

    visit_solo_log

    assert_shown('teamwork-page-solo')
    assert_page_includes('Solo ship')
    assert_page_includes('Alice')
  end

  it 'excludes stories that were ever paired' do
    story = create_story('Paired ship', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    deploy_story(story)
    release_story(story)

    visit_solo_log

    refute_content_includes('Paired ship')
  end

  it 'shows team member list' do
    visit_solo_log

    body = page_body

    assert_includes body, 'teamwork-members'
    assert_includes body, 'Alice'
    assert_includes body, 'Bob'
  end

  it 'shows tab navigation' do
    visit_solo_log

    assert_page_includes(%(href="/teams/#{@team.id}/teamwork"))
    assert_page_includes(%(href="/teams/#{@team.id}/teamwork/ensemble"))
    assert_page_includes(%(href="/teams/#{@team.id}/teamwork/solo"))
  end
end

describe 'Teamwork - Rename Person (trialing team)' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
  end

  it 'shows edit profile link on teamwork page for trialing team' do
    login_as(@alice)
    visit_teamwork

    body = page_body

    assert_includes body, '/profile/edit'
  end

  it 'renames person on trialing team' do
    login_as(@alice)
    rename_person(@alice, name: 'Alicia')

    @alice.reload

    assert_equal 'Alicia', @alice.name
  end
end

describe 'Teamwork - Rename Person' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
  end

  it 'shows edit form with current name' do
    login_as(@alice)
    visit_edit_person(@alice)

    assert_shown('profile-edit')
    assert_page_includes('Alice')
  end

  it 'renames person and actor' do
    login_as(@alice)
    rename_person(@alice, name: 'Alicia')

    @alice.reload

    assert_equal 'Alicia', @alice.name
    assert_equal 'Alicia', @alice.actor.reload.name
  end

  it 'records an edited event for each team' do
    login_as(@alice)
    rename_person(@alice, name: 'Alicia')

    SetTeamContext.call(@team.id)
    event = assert_event_recorded(entity: @alice, action: 'edited')
    assert_equal({ 'name' => 'Alice' }, event.before_state)
    assert_equal({ 'name' => 'Alicia' }, event.after_state)
  end

  it 'rejects blank name' do
    login_as(@alice)
    rename_person(@alice, name: '')

    @alice.reload

    assert_equal 'Alice', @alice.name
  end

  it 'rejects name longer than 100 characters' do
    login_as(@alice)
    rename_person(@alice, name: 'A' * 101)

    @alice.reload

    assert_equal 'Alice', @alice.name
  end
end
