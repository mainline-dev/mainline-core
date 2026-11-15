# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/release_notes'

describe ReleaseNotes do
  cover 'ReleaseNotes*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: @map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @slice = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'Checkout', position: 1000)
  end

  def story(title, released_on: nil, slice: @slice, **attrs)
    state = released_on ? { status: 'released', released_at: released_on } : { status: 'active' }
    Story.create(task_id: @task.id, map_id: @map.id, team_id: @team.id, title: title, release_slice_id: slice&.id,
      position: (Story.max(:position) || 0) + 1000, created_by_id: @person.id, **state, **attrs)
  end

  def scenario(story, given, act, outcome, position: nil)
    Scenario.create(story_id: story.id, given_text: given, when_text: act, then_text: outcome,
      position: position || ((Scenario.where(story_id: story.id).max(:position) || 0) + 1000))
  end

  it 'writes the slice, then each released story with its release day and scenarios, oldest release first' do
    card = story('Shoppers can save a card', released_on: Time.utc(2026, 11, 15, 9))
    guest = story('Guests can pay without an account', released_on: Time.utc(2026, 11, 14, 9))
    scenario(guest, 'a guest order', 'I sign up with its email', 'the order is in my history', position: 2000)
    scenario(guest, 'a basket and no account', 'I continue as a guest', 'I can pay with my email', position: 1000)
    scenario(card, 'a saved card', 'I check out', 'I can pay with it')

    assert_equal <<~NOTES, ReleaseNotes.for(@slice)
      # Checkout

      ## Guests can pay without an account
      Released 14 November 2026

      - Given a basket and no account, when I continue as a guest, then I can pay with my email
      - Given a guest order, when I sign up with its email, then the order is in my history

      ## Shoppers can save a card
      Released 15 November 2026

      - Given a saved card, when I check out, then I can pay with it
    NOTES
  end

  it 'writes a story with no scenarios as its title and release day' do
    story('Shoppers can save a card', released_on: Time.utc(2026, 11, 15, 9))

    assert_equal <<~NOTES, ReleaseNotes.for(@slice)
      # Checkout

      ## Shoppers can save a card
      Released 15 November 2026
    NOTES
  end

  it 'leaves out stories not released, archived, or in another slice' do
    later = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'Later', position: 2000)
    story('Still going')
    story('Put away', released_on: Time.utc(2026, 11, 14, 9), archived_at: Time.now)
    story('Gift cards', released_on: Time.utc(2026, 11, 14, 9), slice: later)
    story('Shoppers can save a card', released_on: Time.utc(2026, 11, 15, 9))

    assert_equal ['## Shoppers can save a card'], ReleaseNotes.for(@slice).lines.grep(/^## /).map(&:chomp)
  end

  it 'keeps each name, title and step on one line' do
    @slice.update(name: "Check\nout")
    guest = story("Guests can pay\nwithout an account", released_on: Time.utc(2026, 11, 14, 9))
    scenario(guest, "a basket\nand no account", "I continue\nas a guest", "I can pay\nwith my email")

    lines = ReleaseNotes.for(@slice).lines.map(&:chomp)

    assert_equal '# Check out', lines.first
    assert_includes lines, '## Guests can pay without an account'
    assert_includes lines, '- Given a basket and no account, when I continue as a guest, then I can pay with my email'
  end

  it 'names the file after the slice' do
    @slice.update(name: '(Release 2: Checkout)')

    assert_equal 'release-2-checkout-release-notes.md', ReleaseNotes.file_name(@slice)
  end

  it 'names the file plainly when the slice name has no letters or numbers' do
    @slice.update(name: '!!!')

    assert_equal 'release-notes.md', ReleaseNotes.file_name(@slice)
  end

  it 'offers notes for the slices that have a released story, and no others' do
    later = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'Later', position: 2000)
    empty = ReleaseSlice.create(map_id: @map.id, team_id: @team.id, name: 'Empty', position: 3000)
    story('Shoppers can save a card', released_on: Time.utc(2026, 11, 15, 9))
    story('Still going', slice: later)
    story('Put away', released_on: Time.utc(2026, 11, 14, 9), slice: later, archived_at: Time.now)

    assert_equal Set[@slice.id], ReleaseNotes.offered([@slice, later, empty])
  end
end
