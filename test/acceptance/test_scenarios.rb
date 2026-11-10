# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

describe 'Scenarios' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @search = create_task('Search', under_activity: @browse)
    @story = create_story('Find products', under_task: @search)
  end

  it 'creates a scenario' do
    create_scenario(@story, given_text: 'a product exists',
      when_text: 'I search for it',
      then_text: 'I see it in results')

    scenarios = Scenario.where(story_id: @story.id).order(:position).all

    assert_equal 1, scenarios.size
    assert_equal 'a product exists', scenarios[0].given_text
    assert_equal 'I search for it', scenarios[0].when_text
    assert_equal 'I see it in results', scenarios[0].then_text

    event = Event.where(entity_id: @story.id, action: 'scenario_added').first

    refute_nil event
  end

  it 'creates multiple scenarios in order' do
    create_scenario(@story,
      given_text: 'first', when_text: 'first', then_text: 'first')
    create_scenario(@story,
      given_text: 'second', when_text: 'second', then_text: 'second')

    scenarios = Scenario.where(story_id: @story.id).order(:position).all

    assert_equal 2, scenarios.size
    assert_equal 'first', scenarios[0].given_text
    assert_equal 'second', scenarios[1].given_text
    assert_operator scenarios[0].position, :<, scenarios[1].position
  end

  it 'updates an existing scenario' do
    create_scenario(@story,
      given_text: 'old', when_text: 'old', then_text: 'old')
    scenario = Scenario.where(story_id: @story.id).first

    update_scenario(@story, scenario,
      given_text: 'new given', when_text: 'new when', then_text: 'new then')

    scenario.reload

    assert_equal 'new given', scenario.given_text
    assert_equal 'new when', scenario.when_text
    assert_equal 'new then', scenario.then_text
  end

  it 'deletes a scenario' do
    create_scenario(@story,
      given_text: 'doomed', when_text: 'doomed', then_text: 'doomed')
    scenario = Scenario.where(story_id: @story.id).first

    delete_scenario(@story, scenario)

    assert_equal(0, BypassRLS.call { Scenario.where(story_id: @story.id).count })
    event = Event.where(entity_id: @story.id, action: 'scenario_removed').first

    refute_nil event
  end

  it 'rejects scenario with empty fields' do
    create_scenario(@story,
      given_text: '', when_text: 'something', then_text: 'something')

    assert_equal(0, BypassRLS.call { Scenario.where(story_id: @story.id).count })
    assert_error_shown
  end

  it 'rejects scenario fields over 100 characters' do
    create_scenario(@story,
      given_text: 'x' * 101, when_text: 'something', then_text: 'something')

    assert_equal(0, BypassRLS.call { Scenario.where(story_id: @story.id).count })
    assert_error_shown
  end

  it 'shows existing scenarios on edit page' do
    Scenario.create(
      story_id: @story.id, given_text: 'a user logs in',
      when_text: 'they click search', then_text: 'results appear',
      position: 1000
    )

    visit_edit_story(@story)

    assert_page_includes('a user logs in')
    assert_page_includes('they click search')
    assert_page_includes('results appear')
  end

  it 'needs a name for a new scenario' do
    create_scenario(@story, name: '', given_text: 'a product exists', when_text: 'I search for it',
      then_text: 'I see it in results')

    assert_equal(0, BypassRLS.call { Scenario.where(story_id: @story.id).count })
    assert_error_shown
  end

  it 'keeps the name a scenario is given' do
    create_scenario(@story, name: 'Search finds a product by name', given_text: 'a product exists',
      when_text: 'I search for it', then_text: 'I see it in results')

    assert_equal 'Search finds a product by name', Scenario.where(story_id: @story.id).get(:name)
  end

  it 'refuses a scenario name over 80 characters' do
    create_scenario(@story, name: 'x' * 81, given_text: 'a', when_text: 'b', then_text: 'c')

    assert_equal(0, BypassRLS.call { Scenario.where(story_id: @story.id).count })
    assert_error_shown
  end

  it 'needs a name when a scenario written before names is edited' do
    scenario = Scenario.create(story_id: @story.id, given_text: 'old', when_text: 'old', then_text: 'old', position: 1000)

    update_scenario(@story, scenario, name: '', given_text: 'new', when_text: 'new', then_text: 'new')

    assert_error_shown
    assert_equal 'old', scenario.reload.given_text
  end

  it "shows each scenario's name, and the Then line for one written before names" do
    Scenario.create(story_id: @story.id, given_text: 'a user logs in', when_text: 'they click search',
      then_text: 'results appear', position: 1000)
    create_scenario(@story, name: 'Search by product name', given_text: 'a product exists',
      when_text: 'I search for it', then_text: 'I see it in results')

    visit_edit_story(@story)

    assert_equal ['results appear', 'Search by product name'], scenario_names_shown
  end

  it 'downloads the scenarios as a feature file named after the story' do
    create_scenario(@story, name: 'Search by product name', given_text: 'a product exists',
      when_text: 'I search for it', then_text: 'I see it in results')

    resp = download_feature_file(@story)

    assert_equal 200, resp.status
    assert_includes resp['Content-Disposition'], 'filename="find-products.feature"'
    assert_includes resp.body, 'Feature: Find products'
    assert_includes resp.body, 'Scenario: Search by product name'
  end

  it 'offers the feature file once a story has a scenario' do
    visit_edit_story(@story)

    refute driver.response_includes?('data-test-id="feature-download"')

    create_scenario(@story, given_text: 'a product exists', when_text: 'I search for it', then_text: 'I see it in results')
    visit_edit_story(@story)

    assert driver.response_includes?('data-test-id="feature-download"')
    assert driver.response_includes?('data-test-id="feature-copy"')
    assert_equal StepStubs::LANGUAGES.keys, driver.attributes_of('stub-download', 'data-language')
  end

  it 'downloads step stubs in a chosen language, named for it' do
    create_scenario(@story, given_text: 'a product exists', when_text: 'I search for it', then_text: 'I see it in results')

    resp = download_step_stubs(@story, 'kotlin')

    assert_equal 200, resp.status
    assert_includes resp['Content-Disposition'], 'filename="FindProductsSteps.kt"'
    assert_includes resp.body, '@Given("a product exists")'
  end

  it 'has no step stubs in a language it does not know' do
    create_scenario(@story, given_text: 'a product exists', when_text: 'I search for it', then_text: 'I see it in results')

    err = assert_raises(RuntimeError) { download_step_stubs(@story, 'cobol') }

    assert_match(/404/, err.message)
  end
end

describe 'Scenarios - Released Story' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob = add_person(name: 'Bob')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @search = create_task('Search', under_activity: @browse)
    @story = create_story('Find products', under_task: @search)
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)
    release_story(@story)
    @story.reload
  end

  it 'released story blocks scenario creation' do
    create_scenario(@story,
      given_text: 'hacked', when_text: 'hacked', then_text: 'hacked')

    assert_equal(0, BypassRLS.call { Scenario.where(story_id: @story.id).count })
  end

  it 'released story blocks scenario deletion' do
    Scenario.create(
      story_id: @story.id, given_text: 'original',
      when_text: 'original', then_text: 'original', position: 1000
    )
    scenario = Scenario.where(story_id: @story.id).first

    delete_scenario(@story, scenario)

    assert_equal 1, Scenario.where(story_id: @story.id).count
  end
end

describe 'Scenario check-off' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob = add_person(name: 'Bob')
    create_map
    @visitor = create_persona('Visitor')
    @browse = create_activity('Browse', for_personas: [@visitor])
    @search = create_task('Search', under_activity: @browse)
    @story = create_story('Find products', under_task: @search)
    create_scenario(@story, given_text: 'a product exists',
      when_text: 'I search for it', then_text: 'I see it in results')
    @scenario = Scenario.where(story_id: @story.id).first
  end

  it 'marks a scenario done' do
    mark_scenario_done(@story, @scenario)

    @scenario.refresh

    refute_nil @scenario.done_at
  end

  it 'unmarks a done scenario' do
    mark_scenario_done(@story, @scenario)
    unmark_scenario_done(@story, @scenario)

    @scenario.refresh

    assert_nil @scenario.done_at
  end

  it 'records events for check-off and un-check' do
    mark_scenario_done(@story, @scenario)
    unmark_scenario_done(@story, @scenario)

    actions = Event.where(entity_id: @story.id).order(:event_no).select_map(:action)

    assert_includes actions, 'scenario_done'
    assert_includes actions, 'scenario_undone'
  end

  it 'blocks release while a scenario is not done' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)

    release_story(@story)
    driver.follow_redirect! if driver.last_response.redirect?

    assert_refused_because('unverified-scenarios')
    @story.reload

    refute_equal 'released', @story.status
  end

  it 'releases when every scenario is done' do
    assign_person(@story, person: @alice)
    assign_person(@story, person: @bob)
    deploy_story(@story)
    mark_scenario_done(@story, @scenario)

    release_story(@story)

    @story.reload

    assert_equal 'released', @story.status
  end

  it 'releases a story that never had scenarios' do
    bare = create_story('No criteria', under_task: @search)
    assign_person(bare, person: @alice)
    assign_person(bare, person: @bob)
    deploy_story(bare)

    release_story(bare)

    bare.reload

    assert_equal 'released', bare.status
  end
end
