# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/walkthroughs'

describe Walkthroughs do
  cover 'Walkthroughs*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice, @bob, @carol = %w[Alice Bob Carol].map { |name| Person.create(name: name, email: "#{name.downcase}@test.mainline") }
    [@alice, @bob].each { |person| TeamMembership.create(team_id: @team.id, person_id: person.id) }
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'User', position: 1000)
    activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    ActivityPersona.create(activity_id: activity.id, persona_id: persona.id, team_id: @team.id)
    @task = Task.create(activity_id: activity.id, map_id: @map.id, team_id: @team.id, name: 'Search', position: 1000)
  end

  # An active story these people are on, deployed once.
  def deployed(title, on_it:)
    position = (Story.where(task_id: @task.id).max(:position) || 0) + 1000
    story = Story.create(task_id: @task.id, map_id: @map.id, team_id: @team.id, title: title, position: position,
      created_by_id: @alice.id, status: 'active', deploy_count: 1, first_deployed_at: Time.now,
      last_deployed_at: Time.now)
    on_it.each { |person| StoryAssignment.create(story_id: story.id, person_id: person.id, team_id: @team.id) }
    story
  end

  def names(people)
    people.map(&:name).sort
  end

  describe 'the stories needing a walkthrough' do
    it 'has nothing when no story is waiting for one' do
      assert_empty Walkthroughs.needed(@team)
    end

    it 'gives each waiting story with the people on it' do
      story = deployed('Find things', on_it: [@alice])

      needed = Walkthroughs.needed(@team)

      assert_equal([story.id], needed.map { |row| row.story.id })
      assert_equal ['Alice'], names(needed.first.on_it)
    end

    it 'offers the working members who are not on the story as attending, by name' do
      zed = Person.create(name: 'Zed', email: 'zed@test.mainline')
      [zed, @carol].each { |person| TeamMembership.create(team_id: @team.id, person_id: person.id) }
      deployed('Find things', on_it: [@alice])

      assert_equal %w[Bob Carol Zed], Walkthroughs.needed(@team).first.could_attend.map(&:name)
    end

    it 'does not offer someone who works on another team only' do
      other = Team.create(name: 'Other')
      TeamMembership.create(team_id: other.id, person_id: @carol.id)
      deployed('Find things', on_it: [@alice])

      assert_equal ['Bob'], names(Walkthroughs.needed(@team).first.could_attend)
    end

    it 'does not offer a member who is not working on the team, or one who has left' do
      dana = Person.create(name: 'Dana', email: 'dana@test.mainline')
      TeamMembership.create(team_id: @team.id, person_id: @carol.id, working: false)
      TeamMembership.create(team_id: @team.id, person_id: dana.id, left_at: Time.now)
      deployed('Find things', on_it: [@alice])

      assert_equal ['Bob'], names(Walkthroughs.needed(@team).first.could_attend)
    end

    it 'counts the scenarios each story has' do
      two = deployed('Find things', on_it: [@alice])
      deployed('Pay', on_it: [@bob])
      %w[first second].each_with_index do |name, index|
        Scenario.create(story_id: two.id, name: name, given_text: 'a shop', when_text: 'a search', then_text: name,
          position: (index + 1) * 1000)
      end

      counts = Walkthroughs.needed(@team).to_h { |row| [row.story.title, row.scenario_count] }

      assert_equal({ 'Find things' => 2, 'Pay' => 0 }, counts)
    end

    it 'says where the kickoff of each story stands' do
      agreed = deployed('Find things', on_it: [@alice])
      deployed('Pay', on_it: [@bob])
      RecordEvent.call(actor_id: @bob.actor.id, entity: agreed, action: 'scenarios_agreed')

      kickoffs = Walkthroughs.needed(@team).to_h { |row| [row.story.title, row.kickoff] }

      assert_equal({ 'Find things' => :agreed, 'Pay' => :none }, kickoffs)
    end

    it 'keeps each story to its own people' do
      deployed('Find things', on_it: [@alice])
      deployed('Pay', on_it: [@bob])

      rows = Walkthroughs.needed(@team).to_h { |row| [row.story.title, row] }

      assert_equal ['Alice'], names(rows['Find things'].on_it)
      assert_equal ['Alice'], names(rows['Pay'].could_attend)
    end
  end
end
