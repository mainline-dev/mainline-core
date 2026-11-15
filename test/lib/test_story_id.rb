# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/story_id'

describe StoryId do
  cover 'StoryId*'

  before do
    @team = Team.create(name: 'ID Team')
    SetTeamContext.call(@team.id)
    person = Person.create(name: 'Alice', email: 'alice@ids.co')
    map = Map.create(team_id: @team.id, name: 'Product', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Browse', position: 1000)
    task = Task.create(map_id: map.id, team_id: @team.id, activity_id: activity.id, name: 'Search', position: 1000)
    @story = Story.create(map_id: map.id, team_id: @team.id, task_id: task.id, title: 'Search', position: 1000,
      created_by_id: person.id)
    Story.create(map_id: map.id, team_id: @team.id, task_id: task.id, title: 'Filter', position: 2000,
      created_by_id: person.id)
    @stories = Story.where(team_id: @team.id)
  end

  def found(given, stories = @stories)
    StoryId.matching(stories, given).select_map(:id)
  end

  it 'finds a story by its full ID' do
    assert_equal [@story.id], found(@story.id)
  end

  it 'finds a story by its full ID in capitals' do
    assert_equal [@story.id], found(@story.id.upcase)
  end

  it 'finds a story by the 8-character ID on its card, in capitals or not' do
    assert_equal [@story.id], found(@story.id[0, 8].upcase)
    assert_equal [@story.id], found(@story.id[0, 8])
  end

  it 'finds a story by a longer start of its ID' do
    assert_equal [@story.id], found(@story.id[0, 13])
  end

  it 'finds nothing by fewer than 8 characters' do
    assert_empty found(@story.id[0, 7])
  end

  it 'finds nothing by something that is not an ID, even one as long as an ID' do
    assert_empty found('YOUR_STORY_ID')
    assert_empty found("#{@story.id[0, 8]}%")
    assert_empty found('-' * 36)
    assert_empty found(nil)
  end

  it 'looks only among the stories it is given' do
    assert_empty found(@story.id[0, 8], Story.where(id: nil))
  end
end
