# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Flow - Cumulative flow diagram' do
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

  it 'shows the cumulative flow page' do
    visit_flow

    assert_shown('flow-page-cfd')
  end

  it 'shows range toggle links' do
    visit_flow

    body = page_body

    assert_includes body, '?days=60'
    assert_includes body, '?days=90'
    assert_includes body, '?days=all'
  end

  it 'shows empty state when no stories exist' do
    visit_flow

    assert_shown('flow-empty')
  end

  it 'renders SVG when stories exist' do
    story = create_story('Work', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    visit_flow

    body = page_body

    assert_includes body, '<svg'
    assert_includes body, '<polygon'
  end

  it 'range parameter changes output' do
    story = create_story('Work', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    visit_flow(days: 'all')

    body = page_body

    assert_includes body, '<svg'
  end
end

describe 'Flow - Throughput scatter' do
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

  it 'shows the throughput page' do
    visit_throughput

    assert_shown('flow-page-throughput')
  end

  it 'shows lens toggles for releases and deploys' do
    visit_throughput

    body = page_body

    assert_includes body, 'lens=deployed'
    assert_includes body, 'lens=both'
  end

  it 'shows range toggle links' do
    visit_throughput

    body = page_body

    assert_includes body, '?days=60'
    assert_includes body, '?days=90'
    assert_includes body, '?days=all'
  end

  it 'shows empty state when no releases exist' do
    visit_throughput

    assert_shown('flow-empty')
  end

  it 'renders SVG with circles after releasing a story' do
    story = create_story('Work', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    release_story(story)

    visit_throughput

    body = page_body

    assert_includes body, '<svg'
    assert_includes body, '<circle'
  end

  it 'shows deploy dots when lens is deployed' do
    story = create_story('Work', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)

    visit_throughput(lens: 'deployed')

    body = page_body

    assert_includes body, '<svg'
    assert_includes body, '<circle'
  end

  it 'shows both deploy and release dots when lens is both' do
    story = create_story('Work', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    release_story(story)

    visit_throughput(lens: 'both')

    body = page_body

    assert_includes body, '<svg'
    assert_includes body, 'scatter-dot-release'
    assert_includes body, 'scatter-dot-deploy'
  end

  it 'shows tab navigation to cumulative flow' do
    visit_throughput

    body = page_body

    assert_includes body, %(href="/teams/#{@team.id}/flow")
  end
end

describe 'Flow - Map filter' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map(name: 'Product')
    @map_a = @map
    persona  = create_persona('User')
    activity = create_activity('Browse', for_personas: [persona])
    task_a   = create_task('Search', under_activity: activity)
    story_a  = create_story('Map A story', under_task: task_a)
    assign_person(story_a, person: @alice)
    assign_person(story_a, person: @bob)
    deploy_story(story_a)
    release_story(story_a)

    create_map(name: 'Maintenance')
    @map_b = @map
    persona_b  = create_persona('Ops')
    activity_b = create_activity('Monitor', for_personas: [persona_b])
    task_b     = create_task('Alerts', under_activity: activity_b)
    story_b    = create_story('Map B story', under_task: task_b)
    assign_person(story_b, person: @alice)
    assign_person(story_b, person: @bob)
    deploy_story(story_b)
    release_story(story_b)
  end

  it 'shows map filter toggles on CFD when team has multiple maps' do
    visit_flow

    body = page_body

    assert_includes body, "map_id=#{@map_a.id}"
    assert_includes body, 'Product'
    assert_includes body, 'Maintenance'
  end

  it 'does not show map filter when team has one map' do
    @map_b.update(archived_at: Time.now)
    visit_flow

    body = page_body

    refute_includes body, 'subnav-filter-label">Map'
  end

  it 'filters lead time histogram by map' do
    visit_lead_time(map_id: @map_a.id)

    body = page_body

    assert_includes body, '<svg'
    assert_includes body, 'aria-current="true">Product'
  end

  it 'filters throughput by map' do
    visit_throughput(map_id: @map_a.id)

    body = page_body

    assert_includes body, '<svg'
    assert_includes body, 'aria-current="true">Product'
  end

  it 'preserves map_id in day toggle links' do
    visit_flow(map_id: @map_a.id)

    body = page_body

    assert_includes body, "map_id=#{@map_a.id}"
  end
end

describe 'Flow - Lead time histogram' do
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

  it 'shows the lead time page' do
    visit_lead_time

    assert_shown('flow-page-lead-time')
  end

  it 'shows range toggle links' do
    visit_lead_time

    body = page_body

    assert_includes body, '?days=60'
    assert_includes body, '?days=90'
    assert_includes body, '?days=all'
  end

  it 'shows empty state when no released stories' do
    visit_lead_time

    assert_shown('flow-empty')
  end

  it 'renders SVG with bars after releasing a story' do
    story = create_story('Work', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    deploy_story(story)
    release_story(story)

    visit_lead_time

    body = page_body

    assert_includes body, '<svg'
    assert_includes body, '<rect'
  end

  it 'shows tab navigation to other flow views' do
    visit_lead_time

    body = page_body

    assert_includes body, %(href="/teams/#{@team.id}/flow")
    assert_includes body, %(href="/teams/#{@team.id}/flow/throughput")
    assert_includes body, "/teams/#{@team.id}/flow"
    assert_includes body, "/teams/#{@team.id}/flow/throughput"
  end
end
