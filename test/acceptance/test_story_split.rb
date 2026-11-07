# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Story split' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob = add_person(name: 'Bob')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @search = create_task('Search', under_activity: @browse)
    @story = create_story('Tune the radio', under_task: @search)
    %w[static tuning presets favourites].each do |topic|
      create_scenario(@story, given_text: "a radio with #{topic}",
        when_text: "the player uses #{topic}", then_text: "#{topic} behaves")
    end
    create_scenario(@story, given_text: 'a weak signal',
      when_text: 'the player moves around', then_text: 'a gradient shows strength')
    @scenarios = Scenario.where(story_id: @story.id).order(:position).all
    @gradient = @scenarios.last
    @scenarios[0..3].each { |sc| mark_scenario_done(@story, sc) }
  end

  it 'splits remaining scenarios into a named new story' do
    split_story(@story, title: 'Signal strength gradient', scenario_ids: [@gradient.id])

    child = Story.where(split_from_id: @story.id).first

    refute_nil child
    assert_equal 'Signal strength gradient', child.title
    assert_equal 'planned', child.status
    assert_equal @search.id, child.task_id
    assert_nil child.release_slice_id
    assert_equal [@gradient.id], Scenario.where(story_id: child.id).select_map(:id)
    assert_equal 4, Scenario.where(story_id: @story.id).count
  end

  it 'assembles the new story title from the connextra template' do
    split_story(@story, template: 'connextra',
      fields: { role: 'Player', goal: 'see signal strength while tuning', benefit: 'tuning feels physical' },
      scenario_ids: [@gradient.id])

    child = Story.where(split_from_id: @story.id).first

    refute_nil child
    assert_equal 'As a Player, I want to see signal strength while tuning, so that tuning feels physical', child.title
  end

  it 'requires every template field when splitting with a template' do
    split_story(@story, template: 'connextra',
      fields: { role: 'Player', goal: 'see signal strength while tuning' },
      scenario_ids: [@gradient.id])

    assert_nil Story.where(split_from_id: @story.id).first
    assert_equal 5, Scenario.where(story_id: @story.id).count
  end

  it 'places the new story immediately after the original' do
    other = create_story('Another story', under_task: @search)

    split_story(@story, title: 'Signal strength gradient',
      scenario_ids: [@gradient.id])

    child = Story.where(split_from_id: @story.id).first
    ordered = Story.where(task_id: @search.id).order(:position).select_map(:id)

    assert_equal [@story.id, child.id, other.id], ordered
  end

  it 'requires a title for the new story' do
    split_story(@story, title: '', scenario_ids: [@gradient.id])

    assert_nil Story.where(split_from_id: @story.id).first
  end

  it 'requires at least one scenario' do
    split_story(@story, title: 'Signal strength gradient', scenario_ids: [])

    assert_nil Story.where(split_from_id: @story.id).first
  end

  it 'allows editing moved scenarios during the split' do
    split_story(@story, title: 'Signal strength gradient',
      scenario_ids: [@gradient.id],
      scenario_edits: { @gradient.id => { given: 'a weak or strong signal',
                                          when: 'the player tunes', then: 'a gradient reflects strength' } })

    @gradient.refresh

    assert_equal 'a weak or strong signal', @gradient.given_text
  end

  it 'records split events on both stories' do
    split_story(@story, title: 'Signal strength gradient',
      scenario_ids: [@gradient.id])

    child = Story.where(split_from_id: @story.id).first
    out_event = Event.where(entity_id: @story.id, action: 'split_out').first
    created = Event.where(entity_id: child.id, action: 'created').first

    refute_nil out_event
    assert_equal child.id, out_event.after_state['split_to_id']
    refute_nil created
    assert_equal @story.id, created.after_state['split_from_id']
  end

  it 'cannot split a released story' do
    bare = create_story('Done story', under_task: @search)
    assign_person(bare, person: @alice)
    assign_person(bare, person: @bob)
    deploy_story(bare)
    release_story(bare)

    split_story(bare, title: 'Should not exist', scenario_ids: [])

    assert_nil Story.where(split_from_id: bare.id).first
  end

  it 'round-trips the dogfood case: check off, split, release clean' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)

    release_story(@story)
    @story.reload

    refute_equal 'released', @story.status

    split_story(@story, title: 'Signal strength gradient',
      scenario_ids: [@gradient.id])

    release_story(@story)
    @story.reload

    assert_equal 'released', @story.status

    child = Story.where(split_from_id: @story.id).first

    assert_equal 'planned', child.status
    assert_equal 1, Scenario.where(story_id: child.id).count
  end

  it 'cannot split an archived story' do
    archive_story(@story)

    split_story(@story, title: 'Should not exist', scenario_ids: [@gradient.id])

    assert_nil Story.where(split_from_id: @story.id).first
  end

  it 'rejects scenario edits over 100 characters instead of dropping them' do
    long_text = 'x' * 120

    split_story(@story, title: 'Signal strength gradient',
      scenario_ids: [@gradient.id],
      scenario_edits: { @gradient.id => { given: long_text, when: 'w', then: 't' } })

    assert_nil Story.where(split_from_id: @story.id).first
    assert_equal 5, Scenario.where(story_id: @story.id).count
  end

  it 'rejects template titles longer than the story title limit' do
    split_story(@story, template: 'connextra',
      fields: { role: 'r' * 80, goal: 'g' * 80, benefit: 'b' * 80 },
      scenario_ids: [@gradient.id])

    refute_equal 500, driver.last_response.status
    assert_nil Story.where(split_from_id: @story.id).first
  end

  it 'records the acting person as the creator of the split-off story' do
    login_as(@bob)

    split_story(@story, title: 'Signal strength gradient', scenario_ids: [@gradient.id])

    child = Story.where(split_from_id: @story.id).first

    assert_equal @bob.id, child.created_by_id
  end

  it 'release on a planned story does not blame unverified scenarios' do
    planned = create_story('Not started', under_task: @search)
    create_scenario(planned, given_text: 'g', when_text: 'w', then_text: 't')

    driver.submit_release(@map, planned)
    driver.follow_redirect! if driver.last_response.redirect?

    refute_refused_because('unverified-scenarios')
    planned.reload

    refute_equal 'released', planned.status
  end

  it 'release on an already-released story with legacy unverified scenarios does not dead-end' do
    bare = create_story('Legacy', under_task: @search)
    assign_person(bare, person: @alice)
    assign_person(bare, person: @bob)
    deploy_story(bare)
    release_story(bare)
    Scenario.create(story_id: bare.id, given_text: 'g', when_text: 'w', then_text: 't', position: 1000)

    driver.submit_release(@map, bare)
    driver.follow_redirect! if driver.last_response.redirect?

    refute_refused_because('unverified-scenarios')
  end

  it 'keeps user input when split validation fails' do
    resp = driver.submit_split_story(@map, @story, template: 'behaviour',
      fields: { beh_context: 'tuning the radio', beh_persona: 'Player' },
      scenario_ids: [@gradient.id],
      scenario_edits: { @gradient.id => { given: 'an edited given', when: 'w', then: 't' } })

    body = resp.body

    assert_includes body, 'value="behaviour" selected'
    assert_includes body, 'value="tuning the radio"'
    assert_includes body, 'value="an edited given"'
  end

  it 'shows provenance links from both stories' do
    split_story(@story, title: 'Signal strength gradient',
      scenario_ids: [@gradient.id])

    child = Story.where(split_from_id: @story.id).first

    visit_story_panel(@story)

    assert_page_includes('data-test-id="split-to-link"')
    assert_page_includes(child.id)

    visit_story_panel(child)

    assert_page_includes('data-test-id="split-from-link"')
    assert_page_includes(@story.id)
  end
end
