# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/add_to_story'
require_relative '../../lib/unpromote_museum_item'

describe AddToStory do
  cover 'AddToStory*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @person.id)
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Checkout', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Pay', position: 1000)
    @story = story('Buy without an account')
    @item = museum_item('SHOP-10')
  end

  def story(title)
    Story.create(task_id: @task.id, map_id: @task.map_id, team_id: @team.id, title: title,
      position: (Story.where(team_id: @team.id).count + 1) * 1000, created_by_id: @person.id)
  end

  def museum_item(key, type: 'Story')
    MuseumItem.create(team_id: @team.id, source_key: key, issue_type: type, summary: 'Guest checkout')
  end

  def add(items, story_id: @story.id)
    AddToStory.call(items: items, story_id: story_id, team: @team, actor: @person.actor)
  end

  it 'links each exhibit to the story and leaves the story as it was' do
    other = museum_item('SHOP-14')

    result = add([@item, other])

    assert_predicate result, :success?
    assert_equal @story.id, result.story.id
    assert_equal [@story.id] * 2, [@item.refresh.story_id, other.refresh.story_id]
    assert @item.promoted_at
    assert_equal 'Buy without an account', @story.refresh.title
    assert_empty Event.where(entity_id: @story.id).all
  end

  it 'adds none of them when one cannot go' do
    stored = museum_item('SHOP-14')
    stored.update(discarded_at: Time.now)

    refute_predicate add([@item, stored]), :success?
    assert_nil @item.refresh.story_id
  end

  it 'refuses an exhibit already promoted, an epic and a sub-task' do
    add([@item])

    refute_predicate add([@item]), :success?
    refute_predicate add([museum_item('SHOP-20', type: 'Epic')]), :success?
    refute_predicate add([museum_item('SHOP-21', type: 'Sub-task')]), :success?
  end

  it 'refuses when no story is chosen, or one that is archived' do
    gone = story('Old idea')
    gone.update(archived_at: Time.now)

    refute_predicate add([@item], story_id: nil), :success?
    refute_predicate add([@item], story_id: gone.id), :success?
  end

  it "refuses another team's story" do
    other = Team.create(name: 'Other')

    result = AddToStory.call(items: [@item], story_id: @story.id, team: other, actor: @person.actor)

    refute_predicate result, :success?
  end

  it 'refuses an empty set' do
    refute_predicate add([]), :success?
  end

  it 'never archives a story when an added exhibit is sent back' do
    add([@item])

    UnpromoteMuseumItem.call(item: @item.refresh, actor: @person.actor)

    assert_nil @item.refresh.story_id
    assert_nil @story.refresh.archived_at
  end

  it 'sends back only what was added together' do
    already = museum_item('SHOP-14')
    add([already])
    batch = add([@item]).batch

    assert_equal 1, AddToStory.undo(team_id: @team.id, actor: @person.actor, batch: batch)
    assert_nil @item.refresh.story_id
    assert_equal @story.id, already.refresh.story_id
  end
end
