# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/release_block'
require_relative '../../lib/record_event'
require_relative '../../lib/urgent_story'

describe ReleaseBlock do
  cover 'ReleaseBlock*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
    map = Map.create(team_id: @team.id, name: 'Shop', position: 1000)
    activity = Activity.create(map_id: map.id, team_id: @team.id, name: 'Browse', position: 1000)
    @task = Task.create(activity_id: activity.id, map_id: map.id, team_id: @team.id, name: 'Search', position: 1000)
  end

  def story(title)
    Story.create(task_id: @task.id, map_id: @task.map_id, team_id: @team.id, title: title,
      position: (Story.max(:position) || 0) + 1000, created_by_id: @person.id, status: 'active')
  end

  def scenario(story, done:)
    Scenario.create(story_id: story.id, given_text: 'a shopper', when_text: 'they search', then_text: 'they see results',
      position: (Scenario.max(:position) || 0) + 1000, done_at: done ? Time.now : nil)
  end

  def urgent(story)
    RecordEvent.call(actor_id: @person.actor.id, entity: story, action: UrgentStory::ACTION, after_state: { reason: 'Leak' })
    story
  end

  describe 'a story on its own' do
    it 'is held back with no scenarios' do
      assert_equal 'no-scenarios', ReleaseBlock.of(story('Find things'))
    end

    it 'is held back while any scenario is not done' do
      find = story('Find things')
      scenario(find, done: true)
      scenario(find, done: false)

      assert_equal 'unverified-scenarios', ReleaseBlock.of(find)
    end

    it 'goes once every scenario is done' do
      find = story('Find things')
      scenario(find, done: true)
      scenario(find, done: true)

      assert_nil ReleaseBlock.of(find)
    end

    it 'goes with no scenarios when it is urgent' do
      assert_nil ReleaseBlock.of(urgent(story('Rotate the key')))
    end

    it 'is held back by a scenario not done even when it is urgent' do
      patch = urgent(story('Rotate the key'))
      scenario(patch, done: false)

      assert_equal 'unverified-scenarios', ReleaseBlock.of(patch)
    end

    it 'counts only its own scenarios' do
      find = story('Find things')
      scenario(story('Filter results'), done: false)

      assert_equal 'no-scenarios', ReleaseBlock.of(find)
    end
  end

  describe 'many stories at once' do
    it 'gives each held-back story its block, leaving out those that can go' do
      bare = story('Find things')
      unfinished = story('Filter results')
      scenario(unfinished, done: false)
      finished = story('Sort results')
      scenario(finished, done: true)

      assert_equal({ bare.id => 'no-scenarios', unfinished.id => 'unverified-scenarios' },
        ReleaseBlock.blocks([bare, unfinished, finished], urgent: nil))
    end

    it 'lets the urgent story go with no scenarios' do
      bare = story('Find things')
      patch = story('Rotate the key')

      assert_equal({ bare.id => 'no-scenarios' }, ReleaseBlock.blocks([bare, patch], urgent: Story[patch.id]))
    end

    it 'holds back the urgent story while a scenario is not done' do
      patch = story('Rotate the key')
      scenario(patch, done: false)

      assert_equal({ patch.id => 'unverified-scenarios' }, ReleaseBlock.blocks([patch], urgent: patch))
    end

    it 'has nothing to say of no stories' do
      assert_empty ReleaseBlock.blocks([], urgent: nil)
    end
  end

  describe 'a release asked for' do
    it 'is refused for a story with no scenarios when nobody says why' do
      assert_equal 'no-scenarios', ReleaseBlock.refusal(story('Find things'), reason: nil)
    end

    it 'goes ahead for a story with no scenarios, given a reason' do
      assert_nil ReleaseBlock.refusal(story('Find things'), reason: 'A copy change')
    end

    it 'needs the reason to say something' do
      assert_equal 'reason-needed', ReleaseBlock.refusal(story('Find things'), reason: " \n ")
    end

    it 'is refused while a scenario is not done, whatever the reason' do
      find = story('Find things')
      scenario(find, done: false)

      assert_equal 'unverified-scenarios', ReleaseBlock.refusal(find, reason: 'Shipping the rest now')
    end

    it 'goes ahead once every scenario is done, with or without a reason' do
      find = story('Find things')
      scenario(find, done: true)

      assert_nil ReleaseBlock.refusal(find, reason: nil)
      assert_nil ReleaseBlock.refusal(find, reason: '')
    end
  end

  describe 'what the release records' do
    it 'records a story released without scenarios, and why' do
      scenario(story('Filter results'), done: true)

      assert_equal({ 'without_scenarios' => true, 'reason' => 'A copy change' },
        ReleaseBlock.recorded(story('Find things'), reason: '  A copy change '))
    end

    it 'records an urgent story released without scenarios, with no reason asked' do
      assert_equal({ 'without_scenarios' => true }, ReleaseBlock.recorded(urgent(story('Rotate the key')), reason: nil))
    end

    it 'records nothing more for a story with scenarios' do
      find = story('Find things')
      scenario(find, done: true)

      assert_empty ReleaseBlock.recorded(find, reason: 'Ignored')
    end
  end
end
