# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/kickoff'

describe Kickoff do
  cover 'Kickoff*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice, @bob, @carol = %w[Alice Bob Carol].map { |name|
      Person.create(name: name, email: "#{name.downcase}@test.mainline").tap { |person|
        TeamMembership.create(team_id: @team.id, person_id: person.id)
      }
    }
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'User', position: 1000)
    activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    ActivityPersona.create(activity_id: activity.id, persona_id: persona.id, team_id: @team.id)
    @task = Task.create(activity_id: activity.id, map_id: @map.id, team_id: @team.id, name: 'Search', position: 1000)
    @story = Story.create(task_id: @task.id, map_id: @map.id, team_id: @team.id, title: 'Find things', position: 1000,
      created_by_id: @alice.id)
    Scenario.create(story_id: @story.id, name: 'Matches', given_text: 'a shop', when_text: 'a search',
      then_text: 'matches', position: 1000)
    event('scenario_added', by: @alice)
  end

  def event(action, by:, **after_state)
    RecordEvent.call(actor_id: by.actor.id, entity: @story, action: action, after_state: after_state)
  end

  def kickoff
    Kickoff.for(@story)
  end

  describe 'of a story one person works on' do
    it 'has not happened until someone else agrees the scenarios' do
      assert_equal :none, kickoff.kind
      assert_empty kickoff.people
    end

    it 'is the person who agreed the scenarios' do
      result = Kickoff.agree(story: @story, person: @bob)

      assert_predicate result, :success?
      assert_equal :agreed, kickoff.kind
      assert_equal [@bob.id], kickoff.people.map(&:id)
    end

    it "records the agreement on the story, in that person's name" do
      Kickoff.agree(story: @story, person: @bob)

      agreed = Event.where(entity_id: @story.id, action: 'scenarios_agreed').all

      assert_equal [@bob.actor.id], agreed.map(&:actor_id)
      assert_equal [@team.id], agreed.map(&:team_id)
    end

    it 'is the latest person to agree, when more than one has' do
      Kickoff.agree(story: @story, person: @bob)
      Kickoff.agree(story: @story, person: @carol)

      assert_equal [@carol.id], kickoff.people.map(&:id)
    end

    describe 'once the scenarios change after it' do
      before do
        Kickoff.agree(story: @story, person: @bob)
      end

      %w[scenario_added scenario_edited scenario_removed].each do |change|
        it "reads as changed since that person agreed, after a #{change.tr('_', ' ')}" do
          event(change, by: @alice)

          assert_equal :changed, kickoff.kind
          assert_equal [@bob.id], kickoff.people.map(&:id)
        end
      end

      it 'stays agreed through what is not a change to the scenarios' do
        event('scenario_done', by: @alice)
        event('edited', by: @alice)

        assert_equal :agreed, kickoff.kind
      end

      it 'reads as changed once some of the scenarios are split out to another story' do
        event('split_out', by: @alice)

        assert_equal :changed, kickoff.kind
      end

      it 'is agreed again once someone agrees the changed scenarios' do
        event('scenario_edited', by: @alice)
        Kickoff.agree(story: @story, person: @carol)

        assert_equal :agreed, kickoff.kind
        assert_equal [@carol.id], kickoff.people.map(&:id)
      end
    end

    describe 'who can agree the scenarios' do
      def agreements
        Event.where(entity_id: @story.id, action: 'scenarios_agreed').count
      end

      def refused(person, reason)
        result = Kickoff.agree(story: @story, person: person)

        refute_predicate result, :success?
        assert_equal reason, result.reason
        refute_nil result.error
        refute Kickoff.can_agree?(@story, person)
        assert_equal 0, agreements
      end

      it 'is anyone working on the team other than whoever last changed them' do
        assert Kickoff.can_agree?(@story, @bob)
        assert Kickoff.can_agree?(@story, @carol)
      end

      it 'is not the person who added the latest scenario' do
        refused(@alice, 'own-change')
      end

      it 'is not the person who last edited or removed one, though the one before them now can' do
        event('scenario_edited', by: @bob)

        refused(@bob, 'own-change')

        assert Kickoff.can_agree?(@story, @alice)
        event('scenario_removed', by: @carol)

        refused(@carol, 'own-change')

        assert Kickoff.can_agree?(@story, @bob)
      end

      it 'is not someone who is on the team without working on it, or who has left it' do
        TeamMembership.where(team_id: @team.id, person_id: @bob.id).update(working: false)
        TeamMembership.where(team_id: @team.id, person_id: @carol.id).update(left_at: Time.now)

        refused(@bob, 'not-working')
        refused(@carol, 'not-working')
      end

      it 'is nobody once the story is released' do
        now = Time.now
        @story.update(status: 'released', released_at: now, deploy_count: 1, first_deployed_at: now, last_deployed_at: now)

        refused(@bob, 'released')
      end

      it 'is nobody while the story has no scenarios, whatever other stories have' do
        other = Story.create(task_id: @task.id, map_id: @map.id, team_id: @team.id, title: 'Pay', position: 2000,
          created_by_id: @alice.id)
        Scenario.where(story_id: @story.id).update(story_id: other.id)

        refused(@bob, 'no-scenarios')
      end

      it 'is not someone who works on another team only' do
        dana = Person.create(name: 'Dana', email: 'dana@test.mainline')
        TeamMembership.create(team_id: Team.create(name: 'Other').id, person_id: dana.id)

        refused(dana, 'not-working')
      end

      it 'is not the person who split scenarios out of the story' do
        event('split_out', by: @carol)

        refused(@carol, 'own-change')

        assert Kickoff.can_agree?(@story, @alice)
      end

      it 'is not the person who made a story that arrived with its scenarios, as one split from another does' do
        event('created', by: @carol)

        refused(@carol, 'own-change')

        assert Kickoff.can_agree?(@story, @alice)
      end

      it 'takes the last change from this story only' do
        other = Story.create(task_id: @task.id, map_id: @map.id, team_id: @team.id, title: 'Pay', position: 2000,
          created_by_id: @alice.id)
        RecordEvent.call(actor_id: @bob.actor.id, entity: other, action: 'scenario_edited')

        assert Kickoff.can_agree?(@story, @bob)
      end
    end

    it "takes no notice of another story's agreement" do
      other = Story.create(task_id: @task.id, map_id: @map.id, team_id: @team.id, title: 'Pay', position: 2000,
        created_by_id: @alice.id)
      Kickoff.agree(story: other, person: @bob)

      assert_equal :none, kickoff.kind
    end
  end

  describe 'of a story two or more people started together' do
    def together(mode, *people)
      event('collaboration_changed', by: people.first, mode: mode, person_ids: people.map(&:id))
    end

    def names
      kickoff.people.map(&:name)
    end

    it 'is the people who were on it when it first had two' do
      together('paired', @bob, @alice)

      assert_equal :together, kickoff.kind
      assert_equal %w[Alice Bob], names
    end

    it 'is all of them when it started as an ensemble' do
      together('ensemble', @alice, @bob, @carol)

      assert_equal :together, kickoff.kind
      assert_equal %w[Alice Bob Carol], names
    end

    it 'stays those people after one leaves or another joins' do
      together('paired', @alice, @bob)
      together('ensemble', @alice, @bob, @carol)
      event('collaboration_changed', by: @alice, mode: 'solo', person_ids: [@alice.id])

      assert_equal :together, kickoff.kind
      assert_equal %w[Alice Bob], names
    end

    it 'has not happened while one person is on the story' do
      event('collaboration_changed', by: @alice, mode: 'solo', person_ids: [@alice.id])

      assert_equal :none, kickoff.kind
    end

    it 'stands whatever is agreed or changed afterwards' do
      together('paired', @alice, @bob)
      Kickoff.agree(story: @story, person: @carol)
      event('scenario_edited', by: @alice)

      assert_equal :together, kickoff.kind
      assert_equal %w[Alice Bob], names
    end
  end
end
