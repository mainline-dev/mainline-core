# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/record_event'
require_relative '../../lib/two_person_rule'

describe TwoPersonRule do
  cover 'TwoPersonRule*'

  before do
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @bob   = Person.create(name: 'Bob', email: 'bob@test.mainline')
    TeamMembership.create(team_id: @team.id, person_id: @alice.id)
    @map = Map.create(team_id: @team.id, name: 'Map', position: 1000)
    persona = Persona.create(map_id: @map.id, team_id: @team.id, name: 'User', position: 1000)
    activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
    ActivityPersona.create(activity_id: activity.id, persona_id: persona.id, team_id: @team.id)
    @task = Task.create(activity_id: activity.id, map_id: @map.id, team_id: @team.id, name: 'Search', position: 1000)
    @story = create_story('Find things')
  end

  def create_story(title, **attrs)
    position = (Story.where(task_id: @task.id).max(:position) || 0) + 1000
    Story.create(task_id: @task.id, map_id: @map.id, team_id: @team.id, title: title, position: position,
      created_by_id: @alice.id, **attrs)
  end

  # An active story, deployed once.
  def deployed(title, at: Time.now, **attrs)
    create_story(title, status: 'active', deploy_count: 1, first_deployed_at: at, last_deployed_at: at, **attrs)
  end

  def awaiting
    TwoPersonRule.awaiting(@team).map(&:title)
  end

  def event(action, story: @story, **after_state)
    RecordEvent.call(actor_id: @alice.actor.id, entity: story, action: action, after_state: after_state)
  end

  describe 'which teams it holds to the rule' do
    it 'leaves a team with one working member alone' do
      refute TwoPersonRule.applies?(@team)
    end

    it 'holds a team with two working members to it' do
      TeamMembership.create(team_id: @team.id, person_id: @bob.id)

      assert TwoPersonRule.applies?(@team)
    end

    it 'holds a team with three working members to it' do
      carol = Person.create(name: 'Carol', email: 'carol@test.mainline')
      [@bob, carol].each { |person| TeamMembership.create(team_id: @team.id, person_id: person.id) }

      assert TwoPersonRule.applies?(@team)
    end

    it 'does not count a member who is not working on the team' do
      TeamMembership.create(team_id: @team.id, person_id: @bob.id, working: false)

      refute TwoPersonRule.applies?(@team)
    end

    it 'does not count a member who has left' do
      TeamMembership.create(team_id: @team.id, person_id: @bob.id, left_at: Time.now)

      refute TwoPersonRule.applies?(@team)
    end

    it 'does not count the members of another team' do
      other = Team.create(name: 'Other')
      TeamMembership.create(team_id: other.id, person_id: @alice.id)
      TeamMembership.create(team_id: other.id, person_id: @bob.id)

      refute TwoPersonRule.applies?(@team)
    end
  end

  describe 'on a team of two' do
    before do
      TeamMembership.create(team_id: @team.id, person_id: @bob.id)
    end

    it 'blocks the release of a story nobody has worked on with someone else' do
      assert TwoPersonRule.blocks_release?(@story, @team)
    end

    it 'blocks the release of a story one person worked on' do
      event('collaboration_changed', mode: 'solo')

      assert TwoPersonRule.blocks_release?(@story, @team)
    end

    it 'lets a story be released that was paired at some point' do
      event('collaboration_changed', mode: 'paired')
      event('collaboration_changed', mode: 'solo')

      refute TwoPersonRule.blocks_release?(@story, @team)
    end

    it 'lets a story be released that was an ensemble at some point' do
      event('collaboration_changed', mode: 'ensemble')

      refute TwoPersonRule.blocks_release?(@story, @team)
    end

    it 'lets a story be released that has been walked through' do
      event('collaboration_changed', mode: 'solo')
      event('walked_through', attendee_ids: [@bob.id])

      refute TwoPersonRule.blocks_release?(@story, @team)
    end

    it 'takes two people only from the events that say who was on the story' do
      event('edited', mode: 'paired')

      assert TwoPersonRule.blocks_release?(@story, @team)
    end

    it 'takes no notice of what happened on another story' do
      other = create_story('Pay')
      event('collaboration_changed', story: other, mode: 'paired')
      event('walked_through', story: other, attendee_ids: [@bob.id])

      assert TwoPersonRule.blocks_release?(@story, @team)
    end
  end

  describe 'the stories awaiting a walkthrough, on a team of two' do
    before do
      TeamMembership.create(team_id: @team.id, person_id: @bob.id)
    end

    it 'are the active, deployed stories one person worked on, longest since their last deploy first' do
      deployed('Pay', at: Time.now - 60)
      deployed('Browse', at: Time.now - 3600)

      assert_equal %w[Browse Pay], awaiting
    end

    it 'leave out a story that has not been deployed, and one that is still planned' do
      create_story('Started', status: 'active')
      create_story('Planned')

      assert_empty awaiting
    end

    it 'leave out a released story and an archived one' do
      deployed('Released', status: 'released', released_at: Time.now)
      deployed('Archived', archived_at: Time.now)

      assert_empty awaiting
    end

    it 'leave out a story that had two people on it' do
      event('collaboration_changed', story: deployed('Paired'), mode: 'paired')
      event('collaboration_changed', story: deployed('Mobbed'), mode: 'ensemble')
      event('collaboration_changed', story: deployed('Alone'), mode: 'solo')

      assert_equal ['Alone'], awaiting
    end

    it 'leave out a story that has been walked through' do
      event('walked_through', story: deployed('Walked'), attendee_ids: [@bob.id])
      deployed('Waiting')

      assert_equal ['Waiting'], awaiting
    end
  end

  describe 'the team turning it off and on' do
    before do
      TeamMembership.create(team_id: @team.id, person_id: @bob.id)
    end

    def rule_saved_as(value)
      TeamConstraint.create(team_id: @team.id, constraint_key: 'two_person_rule', value: value,
        min_value: 0, max_value: 1, default_value: 1)
    end

    it 'is on until the team says otherwise' do
      assert TwoPersonRule.on?(@team)
    end

    it 'is off once the team has turned it off, and then holds the team to nothing' do
      rule_saved_as(0)

      refute TwoPersonRule.on?(@team)
      refute TwoPersonRule.applies?(@team)
    end

    it 'blocks no release and has no story awaiting a walkthrough while it is off' do
      rule_saved_as(0)
      deployed('Pay')

      refute TwoPersonRule.blocks_release?(@story, @team)
      assert_empty awaiting
    end

    it 'holds the team to it again once it is turned back on' do
      rule_saved_as(1)

      assert TwoPersonRule.on?(@team)
      assert TwoPersonRule.applies?(@team)
    end
  end

  describe 'the limit on stories awaiting a walkthrough' do
    before do
      TeamMembership.create(team_id: @team.id, person_id: @bob.id)
    end

    def limit_saved_as(value)
      TeamConstraint.create(team_id: @team.id, constraint_key: 'walkthrough_limit', value: value,
        min_value: 1, max_value: 10, default_value: 3)
    end

    def waiting(count)
      count.times { |number| deployed("Story #{number}") }
    end

    it 'is three until the team changes it' do
      assert_equal 3, TwoPersonRule.limit(@team)
    end

    it 'is what the team has set it to' do
      limit_saved_as(5)

      assert_equal 5, TwoPersonRule.limit(@team)
    end

    it 'is not reached while fewer stories are waiting than it allows' do
      waiting(2)

      refute TwoPersonRule.at_limit?(@team)
    end

    it 'is reached when as many stories are waiting as it allows, and stays reached with more' do
      waiting(3)

      assert TwoPersonRule.at_limit?(@team)
      waiting(1)

      assert TwoPersonRule.at_limit?(@team)
    end

    it 'is reached sooner when the team lowers it' do
      limit_saved_as(1)
      waiting(1)

      assert TwoPersonRule.at_limit?(@team)
    end

    it 'is never reached while the rule is off' do
      TeamConstraint.create(team_id: @team.id, constraint_key: 'two_person_rule', value: 0,
        min_value: 0, max_value: 1, default_value: 1)
      waiting(3)

      refute TwoPersonRule.at_limit?(@team)
    end

    it 'says how many stories are waiting, in the words for one or for several' do
      waiting(1)
      one = TwoPersonRule.limit_refusal(@team)
      waiting(2)
      several = TwoPersonRule.limit_refusal(@team)

      assert_match(/\A1 story /, one)
      assert_match(/\A3 stories /, several)
    end
  end

  it 'never reaches the limit on a team of one' do
    3.times { |number| deployed("Story #{number}") }

    refute TwoPersonRule.at_limit?(@team)
  end

  it 'has no story awaiting a walkthrough on a team of one' do
    deployed('Pay')

    assert_empty awaiting
  end

  it 'blocks nothing on a team of one' do
    event('collaboration_changed', mode: 'solo')

    refute TwoPersonRule.blocks_release?(@story, @team)
  end
end
