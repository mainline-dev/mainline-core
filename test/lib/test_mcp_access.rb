# frozen_string_literal: true

require 'date'
require_relative '../model_spec_helper'
require_relative '../../lib/mcp_access'
require_relative '../../lib/create_personal_token'

describe McpAccess do
  cover 'McpAccess*'

  before do
    @now = Time.now
    @alice = Person.create(name: 'Alice', email: 'alice@test.mainline')
    @payments = team_with(@alice, 'Payments')
    @mobile = team_with(@alice, 'Mobile')
    @ops = Team.create(name: 'Ops')
  end

  def team_with(person, name)
    team = Team.create(name: name)
    TeamMembership.create(team_id: team.id, person_id: person.id, working: true)
    team
  end

  def token_for(*teams, expires_on: Date.today + 30)
    CreatePersonalToken.call(person: @alice, name: 'runner', team_ids: teams.map(&:id), expires_on: expires_on).token
  end

  def grant_of(token)
    OauthGrant[OauthAccessToken.first(token_hash: PersonalToken.digest(token)).grant_id]
  end

  def story_on(team, id: nil)
    SetTeamContext.call(team.id)
    map = Map.create(team_id: team.id, name: 'Shop', position: (Map.where(team_id: team.id).max(:position) || 0) + 1000)
    activity = Activity.create(map_id: map.id, team_id: team.id, name: 'Check out', position: 1000)
    task = Task.create(activity_id: activity.id, map_id: map.id, team_id: team.id, name: 'Pay', position: 1000)
    story = Story.new(task_id: task.id, map_id: map.id, team_id: team.id, title: 'Pay', position: 1000, created_by_id: @alice.id)
    story.id = id if id
    story.save_changes
  end

  def map_of(story)
    BypassRLS.call { Story[story.id].map_id }
  end

  describe 'a personal token' do
    it 'reads the teams it was given, as its person, from a personal token' do
      access = McpAccess.for_token(token_for(@payments, @mobile), now: @now)

      assert_equal [@mobile.id, @payments.id].sort, access.team_ids.sort
      assert_equal @alice.id, access.person_id
      assert_equal 'personal token', access.client
    end

    it 'reads only the teams of its own token, whatever else its person has given' do
      token = token_for(@payments)
      token_for(@mobile)

      assert_equal [@payments.id], McpAccess.for_token(token, now: @now).team_ids
    end

    it 'leaves out a team its person can no longer open' do
      token = token_for(@payments, @mobile)
      TeamMembership.where(team_id: @mobile.id, person_id: @alice.id).update(left_at: @now)

      assert_equal [@payments.id], McpAccess.for_token(token, now: @now).team_ids
    end

    it 'is nothing for a token that is not one, was never made, is revoked or has expired' do
      revoked = token_for(@payments)
      grant_of(revoked).update(revoked_at: @now)
      expiring = token_for(@payments, expires_on: Date.today + 1)

      assert_nil McpAccess.for_token('not-a-token', now: @now)
      assert_nil McpAccess.for_token(nil, now: @now)
      assert_nil McpAccess.for_token(PersonalToken.generate, now: @now)
      assert_nil McpAccess.for_token(revoked, now: @now)
      assert_nil McpAccess.for_token(expiring, now: Time.now + (3 * 86_400))
      refute_nil McpAccess.for_token(expiring, now: @now)
    end

    it 'is nothing once its grant has expired, whatever the token says' do
      token = token_for(@payments)
      grant_of(token).update(expires_at: @now - 1)

      assert_nil McpAccess.for_token(token, now: @now)
    end

    it 'is nothing once the token has expired, though its grant goes on' do
      token = token_for(@payments)
      OauthAccessToken.where(token_hash: PersonalToken.digest(token)).update(expires_at: @now - 1)

      assert_nil McpAccess.for_token(token, now: @now)
    end

    it 'lives as long as its token when its grant has no end' do
      token = token_for(@payments)
      grant_of(token).update(expires_at: nil)

      refute_nil McpAccess.for_token(token, now: @now)
    end

    it "reads an app's sign-in as its person, through the app's site, while OAuth is on" do
      token = token_for(@payments)
      grant_of(token).update(client_id: 'https://claude.ai/oauth/claude-code-client-metadata')
      ENV['OAUTH_ENABLED'] = 'true'

      access = McpAccess.for_token(token, now: @now)

      assert_equal [[@payments.id], @alice.id, 'claude.ai'], [access.team_ids, access.person_id, access.client]
    ensure
      ENV.delete('OAUTH_ENABLED')
    end

    it "reads no app's sign-in while OAuth is off, and still a personal token" do
      app = token_for(@payments)
      grant_of(app).update(client_id: 'https://claude.ai/oauth/claude-code-client-metadata')

      assert_nil McpAccess.for_token(app, now: @now)
      refute_nil McpAccess.for_token(token_for(@payments), now: @now)
    end

    it 'gives its grant, for counting calls against' do
      token = token_for(@payments)

      assert_equal grant_of(token).id, McpAccess.for_token(token, now: @now).grant_id
    end

    it 'recognises a token it issued, however it ended, and only those' do
      token = token_for(@payments, expires_on: Date.today + 1)
      grant_of(token).update(revoked_at: @now)

      assert_equal grant_of(token).id, McpAccess.grant_of(token)
      assert_nil McpAccess.grant_of(PersonalToken.generate)
      assert_nil McpAccess.grant_of(nil)
    end

    it 'records when it was used, on its own grant only' do
      token = token_for(@payments)
      other = token_for(@payments)

      McpAccess.for_token(token, now: @now).used(@now)

      assert_in_delta @now.to_f, grant_of(token).last_used_at.to_f, 1
      assert_nil grant_of(other).last_used_at
    end

    it 'gives the teams it can read in the order of their names' do
      assert_equal [@mobile.id, @payments.id], McpAccess.for_token(token_for(@payments, @mobile), now: @now).readable_team_ids
    end

    it 'can read something while one of its teams is open and not suspended' do
      access = McpAccess.for_token(token_for(@payments, @mobile), now: @now)
      @mobile.update(suspended_at: @now)

      assert_predicate access, :readable?
      assert_equal [@payments.id], access.readable_team_ids
      @payments.update(suspended_at: @now)

      refute_predicate access, :readable?
    end

    it 'can read nothing when its person is on none of its teams any more' do
      token = token_for(@mobile)
      TeamMembership.where(team_id: @mobile.id, person_id: @alice.id).update(left_at: @now)

      refute_predicate McpAccess.for_token(token, now: @now), :readable?
    end
  end

  describe 'where a team stands' do
    before { @access = McpAccess.for_token(token_for(@payments), now: @now) }

    it 'is open when it was given and is not suspended' do
      assert_equal [:open, @payments.id], @access.place(@payments.id)
    end

    it 'is suspended when it was given and is suspended' do
      @payments.update(suspended_at: @now)

      assert_equal [:suspended, @payments.id], @access.place(@payments.id)
    end

    it "is withheld when it is one of the person's teams that was not given" do
      assert_equal [:withheld, @mobile.id], @access.place(@mobile.id)
    end

    it 'is unknown for any other team, or none' do
      assert_equal [:unknown, nil], @access.place(@ops.id)
      assert_equal [:unknown, nil], @access.place(nil)
    end
  end

  describe 'finding a story or a map' do
    before do
      @card = story_on(@payments)
      @app = story_on(@mobile)
      @theirs = story_on(@ops)
      @access = McpAccess.for_token(token_for(@payments), now: @now)
    end

    it 'finds a story on a team it was given, by its ID or the start of it' do
      assert_equal [:open, @payments.id, @card.id], @access.story(@card.id)
      assert_equal [:open, @payments.id, @card.id], @access.story(@card.id[0, 8].upcase)
    end

    it "places a story on one of the person's teams that was not given" do
      assert_equal [:withheld, @mobile.id, nil], @access.story(@app.id)
    end

    it 'knows nothing of a story on a team the person is not on, or one that does not exist' do
      assert_equal [:unknown, nil, nil], @access.story(@theirs.id)
      assert_equal [:unknown, nil, nil], @access.story('00000000-0000-4000-8000-000000000000')
      assert_equal [:unknown, nil, nil], @access.story('YOUR_STORY_ID')
    end

    it 'asks for the whole ID when the start of one matches two stories' do
      first = story_on(@payments, id: 'abcdef12-0000-4000-8000-000000000001')
      story_on(@payments, id: 'abcdef12-0000-4000-8000-000000000002')

      assert_equal [:ambiguous, nil, nil], @access.story('ABCDEF12')
      assert_equal [:open, @payments.id, first.id], @access.story(first.id)
    end

    it 'finds a map the same way, by its whole ID only' do
      assert_equal [:open, @payments.id], @access.map(map_of(@card))
      assert_equal [:withheld, @mobile.id], @access.map(map_of(@app))
      assert_equal [:unknown, nil], @access.map(map_of(@theirs))
      assert_equal [:unknown, nil], @access.map(map_of(@card)[0, 8])
      assert_equal [:unknown, nil], @access.map(nil)
    end
  end
end
