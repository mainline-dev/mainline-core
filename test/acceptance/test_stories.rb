# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Stories' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
  end

  it 'creates a story under a task' do
    visitor = create_persona('Visitor')
    browse  = create_activity('Browse', for_personas: [visitor])
    search  = create_task('Search', under_activity: browse)
    create_story('Keyword search', under_task: search)

    assert_map_shows 'Keyword search'
  end

  it 'shows the agent chip on a story a coding agent has read' do
    visitor = create_persona('Visitor')
    browse  = create_activity('Browse', for_personas: [visitor])
    search  = create_task('Search', under_activity: browse)
    story   = create_story('Keyword search', under_task: search)
    story.update(agent_assisted: true)

    visit_map

    assert_page_includes('data-test-id="agent-chip"')
  end

  it 'shows no agent chip on a story no agent has read' do
    visitor = create_persona('Visitor')
    browse  = create_activity('Browse', for_personas: [visitor])
    search  = create_task('Search', under_activity: browse)
    create_story('Keyword search', under_task: search)

    visit_map

    refute_page_includes('data-test-id="agent-chip"')
  end

  it 'requires a title' do
    visitor = create_persona('Visitor')
    browse  = create_activity('Browse', for_personas: [visitor])
    search  = create_task('Search', under_activity: browse)

    submit_create_story(title: '', task_id: search.id, description: '')

    assert_equal(0, BypassRLS.call { Story.where(map_id: @map.id).count })
    assert_error_shown
  end

  it 'rejects a non-existent task' do
    submit_create_story(title: 'Orphan', task_id: SecureRandom.uuid, description: '')

    assert_equal(0, BypassRLS.call { Story.where(map_id: @map.id).count })
    assert_error_shown
  end
end

describe 'Stories - Edit' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @search = create_task('Search', under_activity: @browse)
    @checkout = create_task('Checkout', under_activity: @browse)
  end

  it 'shows pre-filled edit form' do
    story = Story.create(
      task_id: @search.id, map_id: @map.id, team_id: @team.id,
      title: 'As a Visitor, I want to search items, so that I find products',
      position: 1000, created_by_id: @alice.id
    )

    visit_edit_story(story)

    assert_page_includes('As a Visitor, I want to search items, so that I find products')
  end

  it 'updates the title' do
    story = Story.create(
      task_id: @search.id, map_id: @map.id, team_id: @team.id,
      title: 'As a Visitor, I want to search, so that I find stuff',
      position: 1000, created_by_id: @alice.id
    )

    submit_edit_story(story,
      title:   'As a Customer, I want to filter, so that I save time',
      task_id: @search.id)

    story.reload

    assert_equal 'As a Customer, I want to filter, so that I save time', story.title

    event = assert_event_recorded(entity: story, action: 'edited')

    assert_equal 'As a Visitor, I want to search, so that I find stuff', event.before_state['title']
    assert_equal 'As a Customer, I want to filter, so that I save time', event.after_state['title']
  end

  it 'moves story to another task' do
    story = Story.create(
      task_id: @search.id, map_id: @map.id, team_id: @team.id,
      title: 'As a Visitor, I want to search, so that I find stuff',
      position: 1000, created_by_id: @alice.id
    )

    submit_edit_story(story,
      title:   'As a Visitor, I want to search, so that I find stuff',
      task_id: @checkout.id)

    story.reload

    assert_equal @checkout.id, story.task_id
  end

  it 'moves story to a task that already has stories' do
    create_story('Existing story', under_task: @checkout)
    story = create_story('Moving story', under_task: @search)

    submit_edit_story(story,
      title:   'Moving story',
      task_id: @checkout.id)

    story.reload

    assert_equal @checkout.id, story.task_id
  end

  it 'assigns story to a release slice' do
    slice = create_release_slice('MVP')
    story = Story.create(
      task_id: @search.id, map_id: @map.id, team_id: @team.id,
      title: 'As a Visitor, I want to search, so that I find stuff',
      position: 1000, created_by_id: @alice.id
    )

    submit_edit_story(story,
      title: 'As a Visitor, I want to search, so that I find stuff',
      task_id: @search.id, release_slice_id: slice.id)

    story.reload

    assert_equal slice.id, story.release_slice_id
  end

  it 'requires a title' do
    story = Story.create(
      task_id: @search.id, map_id: @map.id, team_id: @team.id,
      title: 'As a Visitor, I want to search, so that I find stuff',
      position: 1000, created_by_id: @alice.id
    )

    submit_edit_story(story, title: '', task_id: @search.id)

    assert_error_shown

    story.reload

    assert_equal 'As a Visitor, I want to search, so that I find stuff', story.title
  end

  it 'rejects title over 200 characters' do
    story = Story.create(
      task_id: @search.id, map_id: @map.id, team_id: @team.id,
      title: 'Short title',
      position: 1000, created_by_id: @alice.id
    )

    submit_edit_story(story, title: 'x' * 201, task_id: @search.id)

    assert_error_shown

    story.reload

    assert_equal 'Short title', story.title
  end
end

describe 'Stories - Archive' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @task = create_task('Search', under_activity: @browse)
  end

  it 'archives a planned story' do
    story = create_story('Throwaway', under_task: @task)

    archive_story(story)

    story.reload

    refute_nil story.archived_at
    assert_event_recorded(entity: story, action: 'archived')
    assert_map_does_not_show('Throwaway')
  end

  it 'rejects archiving a released story' do
    story = create_story('Done story', under_task: @task)
    bob = add_person(name: 'Bob')
    assign_person(story, person: @alice)
    assign_person(story, person: bob)
    deploy_story(story)
    release_story(story)

    archive_story(story)

    story.reload

    refute_nil story.released_at
    assert_nil story.archived_at
  end

  it 'rejects archiving a story with people assigned' do
    story = create_story('Busy story', under_task: @task)
    assign_person(story, person: @alice)

    archive_story(story)

    story.reload

    assert_nil story.archived_at
  end
end

describe 'Stories - Deploy' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob = add_person(name: 'Bob')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @task = create_task('Search', under_activity: @browse)
  end

  it 'deploys an active story' do
    story = create_story('Deploy me', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    story.reload

    assert_equal 'active', story.status

    deploy_story(story)

    story.reload

    assert_equal 1, story.deploy_count
    refute_nil story.first_deployed_at
    assert_event_recorded(entity: story, action: 'deployed')
  end

  it 'increments deploy count on subsequent deploys' do
    story = create_story('Multi deploy', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    deploy_story(story)
    deploy_story(story)

    story.reload

    assert_equal 2, story.deploy_count
  end

  it 'rejects deploying a planned story' do
    story = create_story('Not ready', under_task: @task)

    deploy_story(story)

    story.reload

    assert_equal 0, story.deploy_count
  end
end

describe 'Stories - Release' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob = add_person(name: 'Bob')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @task = create_task('Search', under_activity: @browse)
  end

  it 'releases an active story' do
    story = create_story('Ship it', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    story.reload

    assert_equal 'active', story.status

    deploy_story(story)
    release_story(story)

    story.reload

    assert_equal 'released', story.status
    refute_nil story.released_at
    assert_event_recorded(entity: story, action: 'released')
  end

  it 'unassigns all people when releasing' do
    story = create_story('Ship it', under_task: @task)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)

    deploy_story(story)
    release_story(story)

    assert_equal(0, BypassRLS.call { StoryAssignment.where(story_id: story.id).count })
    assert_event_recorded(entity: story, action: 'person_unassigned')
  end

  it 'rejects releasing a planned story' do
    story = create_story('Not started', under_task: @task)

    deploy_story(story)
    release_story(story)

    story.reload

    assert_equal 'planned', story.status
    assert_nil story.released_at
  end
end

describe 'Stories - Solo Activation' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @task = create_task('Search', under_activity: @browse)
  end

  it 'solo member activates story on first assignment' do
    story = create_story('Solo work', under_task: @task)
    assign_person(story, person: @alice)

    story.reload

    assert_equal 'active', story.status

    event = assert_event_recorded(entity: story, action: 'activated')

    assert_equal 'solo', event.after_state['reason']
    assert_equal 1, event.after_state['assignment_count']
  end

  it 'solo story deactivates when unassigned' do
    story = create_story('Solo work', under_task: @task)
    assign_person(story, person: @alice)

    story.reload

    assert_equal 'active', story.status

    assignment = StoryAssignment.where(story_id: story.id, person_id: @alice.id).first
    unassign_person(story, assignment)

    story.reload

    assert_equal 'planned', story.status
  end

  it 'two-member team still requires pair to activate' do
    @bob = add_person(name: 'Bob')
    story = create_story('Pair work', under_task: @task)
    assign_person(story, person: @alice)

    story.reload

    assert_equal 'planned', story.status
    assert_no_events_for(entity: story, action: 'activated')
  end
end

describe 'Stories - Released Readonly' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob = add_person(name: 'Bob')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @task = create_task('Search', under_activity: @browse)
    @checkout = create_task('Checkout', under_activity: @browse)
    @story = create_story('Ship it', under_task: @task)
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)
    release_story(@story)
    @story.reload
  end

  it 'released story edit only changes decoupling fields' do
    edit_story(@story,
      title:               'Hacked title',
      task_id:             @checkout.id,
      decoupling_strategy: 'flag',
      decoupling_label:    'FF_SHIP')

    @story.reload

    assert_equal 'Ship it', @story.title
    assert_equal @task.id, @story.task_id
    assert_equal 'flag', @story.decoupling_strategy
    assert_equal 'FF_SHIP', @story.decoupling_label
  end

  it 'released story can clear decoupling tags' do
    @story.update(decoupling_strategy: 'bba', decoupling_label: 'OLD')

    edit_story(@story,
      title:               @story.title,
      task_id:             @task.id,
      decoupling_strategy: '',
      decoupling_label:    '')

    @story.reload

    assert_nil @story.decoupling_strategy
    assert_nil @story.decoupling_label
  end

  it 'released story rejects title change' do
    edit_story(@story,
      title:   'New title',
      task_id: @task.id)

    @story.reload

    assert_equal 'Ship it', @story.title
  end
end
