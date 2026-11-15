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

  describe 'the stories walked through and not yet released' do
    def walk(story, *people, deploy_count: nil)
      RecordEvent.call(actor_id: @alice.actor.id, entity: story, action: 'walked_through',
        after_state: { attendee_ids: people.map(&:id), deploy_count: deploy_count }.compact)
    end

    def attended_names(row)
      row.attended.map(&:name)
    end

    it 'has nothing when no story has been walked through' do
      deployed('Find things', on_it: [@alice])

      assert_empty Walkthroughs.walked(@team)
    end

    it 'gives each active story that has been walked through, with who attended' do
      story = deployed('Find things', on_it: [@alice])
      walk(story, @bob)

      walked = Walkthroughs.walked(@team)

      assert_equal([story.id], walked.map { |row| row.story.id })
      assert_equal ['Bob'], attended_names(walked.first)
    end

    it 'gathers who attended every walkthrough of a story, each once and by name' do
      TeamMembership.create(team_id: @team.id, person_id: @carol.id)
      story = deployed('Find things', on_it: [@alice])
      walk(story, @carol)
      walk(story, @bob, @carol)

      assert_equal %w[Bob Carol], attended_names(Walkthroughs.walked(@team).first)
    end

    it 'says when a story has been deployed again since its latest walkthrough' do
      story = deployed('Find things', on_it: [@alice])
      walk(story, @bob, deploy_count: 1)
      story.update(deploy_count: 2)

      assert Walkthroughs.walked(@team).first.deployed_since
    end

    it 'says nothing of a deploy before its latest walkthrough' do
      story = deployed('Find things', on_it: [@alice])
      walk(story, @bob, deploy_count: 1)
      story.update(deploy_count: 2)
      walk(story, @bob, deploy_count: 2)

      refute Walkthroughs.walked(@team).first.deployed_since
    end

    it 'says nothing of deploys for a walkthrough that did not record its deploy count' do
      story = deployed('Find things', on_it: [@alice])
      walk(story, @bob)

      refute Walkthroughs.walked(@team).first.deployed_since
    end

    it 'leaves out a story that has other events and no walkthrough' do
      story = deployed('Find things', on_it: [@alice])
      RecordEvent.call(actor_id: @alice.actor.id, entity: story, action: 'collaboration_changed', after_state: { mode: 'solo' })

      assert_empty Walkthroughs.walked(@team)
    end

    it 'names who attended in order of name, whatever order they joined the team in' do
      aaron = Person.create(name: 'Aaron', email: 'aaron@test.mainline')
      TeamMembership.create(team_id: @team.id, person_id: aaron.id)
      story = deployed('Find things', on_it: [@alice])
      walk(story, @bob, aaron)

      assert_equal %w[Aaron Bob], attended_names(Walkthroughs.walked(@team).first)
    end

    it 'lists the stories longest since their last deploy first' do
      walk(deployed('Recent', on_it: [@alice]), @bob)
      older = deployed('Older', on_it: [@bob])
      older.update(first_deployed_at: Time.now - 3600, last_deployed_at: Time.now - 3600)
      walk(older, @alice)

      assert_equal(%w[Older Recent], Walkthroughs.walked(@team).map { |row| row.story.title })
    end

    it 'leaves out a story that has been archived' do
      story = deployed('Find things', on_it: [@alice])
      walk(story, @bob)
      story.update(archived_at: Time.now)

      assert_empty Walkthroughs.walked(@team)
    end

    it 'leaves out a story once it is released' do
      story = deployed('Find things', on_it: [@alice])
      walk(story, @bob)
      story.update(status: 'released', released_at: Time.now)

      assert_empty Walkthroughs.walked(@team)
    end

    it 'keeps each story to its own walkthroughs' do
      TeamMembership.create(team_id: @team.id, person_id: @carol.id)
      walk(deployed('Find things', on_it: [@alice]), @bob)
      walk(deployed('Pay', on_it: [@bob]), @carol)

      rows = Walkthroughs.walked(@team).to_h { |row| [row.story.title, attended_names(row)] }

      assert_equal({ 'Find things' => ['Bob'], 'Pay' => ['Carol'] }, rows)
    end
  end

  describe 'the deployed stories two people have seen' do
    def together(story, mode = 'paired')
      RecordEvent.call(actor_id: @alice.actor.id, entity: story, action: 'collaboration_changed', after_state: { mode: mode })
    end

    def seen
      Walkthroughs.seen_together(@team)
    end

    it 'has nothing while no deployed story has had two people on it' do
      RecordEvent.call(actor_id: @alice.actor.id, entity: deployed('Find things', on_it: [@alice]),
        action: 'collaboration_changed', after_state: { mode: 'solo' })

      assert_empty seen
    end

    it 'gives each one with who is on it and who could attend a walkthrough of it' do
      TeamMembership.create(team_id: @team.id, person_id: @carol.id)
      together(deployed('Find things', on_it: [@alice, @bob]))

      row = seen.first

      assert_equal 'Find things', row.story.title
      assert_equal %w[Alice Bob], names(row.on_it)
      assert_equal ['Carol'], names(row.could_attend)
    end

    it 'counts a story an ensemble worked on' do
      together(deployed('Find things', on_it: [@alice]), 'ensemble')

      assert_equal 1, seen.size
    end

    it 'leaves out a story once it has been walked through' do
      story = deployed('Find things', on_it: [@alice, @bob])
      together(story)
      RecordEvent.call(actor_id: @alice.actor.id, entity: story, action: 'walked_through', after_state: { attendee_ids: [] })

      assert_empty seen
    end

    it 'leaves out a story not yet deployed, one released and one archived' do
      together(Story.create(task_id: @task.id, map_id: @map.id, team_id: @team.id, title: 'Not deployed',
        position: 9000, created_by_id: @alice.id, status: 'active'))
      released = deployed('Released', on_it: [@alice])
      released.update(status: 'released', released_at: Time.now)
      together(released)
      archived = deployed('Archived', on_it: [@bob])
      archived.update(archived_at: Time.now)
      together(archived)

      assert_empty seen
    end

    it 'lists the stories longest since their last deploy first' do
      together(deployed('Recent', on_it: [@alice]))
      older = deployed('Older', on_it: [@bob])
      older.update(first_deployed_at: Time.now - 3600, last_deployed_at: Time.now - 3600)
      together(older)

      assert_equal(%w[Older Recent], seen.map { |row| row.story.title })
    end
  end
end
