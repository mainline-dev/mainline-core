# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require 'timecop'

describe 'Candidates for splitting' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice', email: 'alice@acme.co')
    @bob   = add_person(name: 'Bob',   email: 'bob@acme.co')
    create_map
    @persona  = create_persona('Customer')
    @activity = create_activity('Onboarding', for_personas: [@persona])
    @task     = create_task('Sign up', under_activity: @activity)
    @story_seq = 0
  end

  after do
    Timecop.return
  end

  def activate_story(story)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
    story.refresh

    assert_equal 'active', story.status
  end

  def release_story_with_cycle_time(hours:)
    @story_seq += 1
    story = create_story("Story #{@story_seq}", under_task: @task)
    activate_story(story)
    Timecop.travel(Time.now + (hours * 3600))
    deploy_story(story)
    release_story(story)
    story.refresh
    story
  end

  def build_baseline(count: 10, hours: 48)
    Timecop.freeze(Time.utc(2026, 1, 5, 12, 0, 0))
    count.times { release_story_with_cycle_time(hours: hours) }
  end

  it 'no split label when fewer than 10 released stories' do
    Timecop.freeze(Time.utc(2026, 1, 5, 12, 0, 0))
    5.times { release_story_with_cycle_time(hours: 48) }

    story = create_story('New feature', under_task: @task)
    activate_story(story)
    Timecop.travel(Time.now + (72 * 3600))

    visit_map

    refute_page_includes('data-test-id="story-note-chip"')
  end

  it 'no split label when active story is within 80th percentile' do
    build_baseline(count: 10, hours: 48)

    story = create_story('New feature', under_task: @task)
    activate_story(story)
    Timecop.travel(Time.now + (24 * 3600))

    visit_map

    refute_page_includes('data-test-id="story-note-chip"')
  end

  it 'shows split notice when active story exceeds 80th percentile' do
    build_baseline(count: 10, hours: 48)

    story = create_story('New feature', under_task: @task)
    activate_story(story)
    Timecop.travel(Time.now + (72 * 3600))

    visit_map

    assert_page_includes('data-test-id="story-note-chip"')
  end

  it 'planned story never shows split label' do
    build_baseline(count: 10, hours: 48)

    create_story('New feature', under_task: @task)
    Timecop.travel(Time.now + (72 * 3600))

    visit_map

    refute_page_includes('data-test-id="story-note-chip"')
  end

  it 'released story never shows split label' do
    build_baseline(count: 10, hours: 48)

    story = create_story('New feature', under_task: @task)
    activate_story(story)
    Timecop.travel(Time.now + (72 * 3600))
    deploy_story(story)
    release_story(story)

    visit_map

    refute_page_includes('data-test-id="story-note-chip"')
  end

  it 'configurable minimum released stories' do
    TeamConstraint.create(
      team_id: @team.id,
      constraint_key: 'split_min_released',
      value: 3, min_value: 1, max_value: 100, default_value: 10
    )

    Timecop.freeze(Time.utc(2026, 1, 5, 12, 0, 0))
    3.times { release_story_with_cycle_time(hours: 48) }

    story = create_story('New feature', under_task: @task)
    activate_story(story)
    Timecop.travel(Time.now + (72 * 3600))

    visit_map

    assert_page_includes('data-test-id="story-note-chip"')
  end

  it 'configurable percentile changes sensitivity' do
    TeamConstraint.create(
      team_id: @team.id,
      constraint_key: 'split_percentile',
      value: 50, min_value: 0, max_value: 100, default_value: 80
    )

    build_baseline(count: 10, hours: 48)

    story = create_story('New feature', under_task: @task)
    activate_story(story)
    Timecop.travel(Time.now + (49 * 3600))

    visit_map

    assert_page_includes('data-test-id="story-note-chip"')
  end

  it 'percentile 100 disables the feature' do
    TeamConstraint.create(
      team_id: @team.id,
      constraint_key: 'split_percentile',
      value: 100, min_value: 0, max_value: 100, default_value: 80
    )

    build_baseline(count: 10, hours: 48)

    story = create_story('New feature', under_task: @task)
    activate_story(story)
    Timecop.travel(Time.now + (720 * 3600))

    visit_map

    refute_page_includes('data-test-id="story-note-chip"')
  end
end
