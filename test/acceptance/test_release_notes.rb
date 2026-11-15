# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# A slice's release notes: the stories released in it, oldest release first,
# each with its scenarios, as a markdown file for people outside the team.
describe 'Release notes' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    @bob   = add_person(name: 'Bob')
    create_map
    @task  = create_task('Pay', under_activity: create_activity('Checkout', for_personas: [create_persona('Shopper')]))
    @slice = create_release_slice('Checkout')
  end

  def story_in(slice, title)
    story = create_story(title, under_task: @task)
    move_story_to_slice(story, release_slice_id: slice.id)
    story
  end

  def start(story)
    assign_person(story, person: @alice)
    assign_person(story, person: @bob)
  end

  def ship(story)
    start(story)
    deploy_story(story)
    scenarios_on(story).each { |scenario| mark_scenario_done(story, scenario) }
    release_story(story)
  end

  it 'lists the stories released in the slice, oldest release first, each with its scenarios' do
    saved_card = story_in(@slice, 'Shoppers can save a card')
    guest = story_in(@slice, 'Guests can pay without an account')
    create_scenario(guest, given_text: 'a basket and no account', when_text: 'I continue as a guest',
      then_text: 'I can pay with my email')
    ship(guest)
    ship(saved_card)
    visit_release_slices_index

    download_release_notes(@slice)

    assert_match(/\.md\z/, release_notes_file_name)
    assert_equal ['Guests can pay without an account', 'Shoppers can save a card'], release_notes_stories
    assert_equal 1, release_notes_scenarios('Guests can pay without an account').size
    assert_includes release_notes_scenarios('Guests can pay without an account').first, 'a basket and no account'
  end

  it 'leaves out stories not yet released and stories released in another slice' do
    later = create_release_slice('Later')
    ship(story_in(later, 'Gift cards'))
    ship(story_in(@slice, 'Shoppers can save a card'))
    start(story_in(@slice, 'Guests can pay without an account'))
    visit_release_slices_index

    download_release_notes(@slice)

    assert_equal ['Shoppers can save a card'], release_notes_stories
  end

  it 'offers release notes only for a slice with a released story' do
    later = create_release_slice('Later')
    ship(story_in(@slice, 'Shoppers can save a card'))

    visit_release_slices_index

    assert release_notes_offered?(@slice)
    refute release_notes_offered?(later)
  end

  it 'still offers the release notes after the slice is renamed in place' do
    ship(story_in(@slice, 'Shoppers can save a card'))

    rename_release_slice(@slice, name: 'Checkout, first cut')

    assert release_notes_offered?(@slice)
  end
end
