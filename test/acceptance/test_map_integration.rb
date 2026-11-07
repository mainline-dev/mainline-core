# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Map structure' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
  end

  describe 'building a story map from scratch' do
    it 'creates the full persona -> activity -> tasks -> story hierarchy' do
      visitor = create_persona('New Visitor')
      admin   = create_persona('Admin')

      browse  = create_activity('Browse catalogue', for_personas: [visitor])
      manage  = create_activity('Manage accounts', for_personas: [admin])

      search    = create_task('Search products', under_activity: browse)
      user_crud = create_task('User CRUD', under_activity: manage)

      create_story('Keyword search', under_task: search)
      create_story('Deactivate user', under_task: user_crud)

      assert_map_shows 'Browse catalogue'
      assert_map_shows 'Keyword search'
      assert_map_shows 'Deactivate user'
      assert_map_shows 'New Visitor'
      assert_map_shows 'Admin'
    end
  end

  describe 'invalid map id' do
    it 'returns 404 for a garbage id' do
      err = assert_raises(RuntimeError) { visit_map_by_id('not-a-uuid') }

      assert_match(/404/, err.message)
    end

    it 'returns 404 for a non-existent uuid' do
      err = assert_raises(RuntimeError) { visit_map_by_id(SecureRandom.uuid) }

      assert_match(/404/, err.message)
    end
  end

  describe 'grid fragment endpoint' do
    it 'returns grid HTML without layout' do
      visitor = create_persona('Visitor')
      browse = create_activity('Browse', for_personas: [visitor])
      create_task('Search', under_activity: browse)

      resp = driver.visit_map_grid(@map)

      assert_equal 200, resp.status
      refute_includes resp.body, '<html'
      refute_includes resp.body, '<nav>'
      assert_includes resp.body, 'map-grid-container'
      assert_includes resp.body, 'Browse'
    end
  end

  describe 'HTMX story actions return grid fragment' do
    before do
      @visitor = create_persona('Visitor')
      @browse = create_activity('Browse', for_personas: [@visitor])
      @search = create_task('Search', under_activity: @browse)
      @bob = add_person(name: 'Bob')
    end

    it 'deploy via HTMX returns grid' do
      story = create_story('Find things', under_task: @search)
      assign_person(story, person: @alice)
      assign_person(story, person: @bob)
      story.refresh

      resp = driver.htmx_deploy_story(@map, story)

      assert_equal 200, resp.status
      assert_includes resp.body, 'map-grid-container'
      refute_includes resp.body, '<html'
    end

    it 'release via HTMX returns grid' do
      story = create_story('Find things', under_task: @search)
      assign_person(story, person: @alice)
      assign_person(story, person: @bob)
      story.refresh

      driver.submit_deploy_story(@map, story)
      resp = driver.htmx_release_story(@map, story)

      assert_equal 200, resp.status
      assert_includes resp.body, 'map-grid-container'
      refute_includes resp.body, '<html'
    end

    it 'archive story via HTMX returns grid' do
      story = create_story('Find things', under_task: @search)

      resp = driver.htmx_archive_story(@map, story)

      assert_equal 200, resp.status
      assert_includes resp.body, 'map-grid-container'
      refute_includes resp.body, '<html'
    end

    it 'archive task via HTMX returns grid' do
      resp = driver.htmx_archive_task(@map, @search)

      assert_equal 200, resp.status
      assert_includes resp.body, 'map-grid-container'
      refute_includes resp.body, '<html'
    end

    it 'unassign via HTMX returns grid' do
      story = create_story('Find things', under_task: @search)
      assign_person(story, person: @alice)
      assign_person(story, person: @bob)
      story.refresh
      assignment = StoryAssignment.where(story_id: story.id).first

      resp = driver.htmx_unassign_person(@map, story, assignment)

      assert_equal 200, resp.status
      assert_includes resp.body, 'map-grid-container'
      refute_includes resp.body, '<html'
    end
  end

  describe 'every action is traced to a named human' do
    it 'records the actor on every event' do
      visitor = create_persona('Visitor')
      browse  = create_activity('Browse', for_personas: [visitor])
      search  = create_task('Search', under_activity: browse)
      create_story('Find things', under_task: search)

      events = Event.where(map_id: @map.id).all

      refute_empty events
      events.each do |e|
        refute_nil e.actor_id,
          "Event #{e.entity_type}/#{e.action} has no actor"
      end
    end
  end
end
