# frozen_string_literal: true

require 'uri'
require_relative 'bypass_rls'
require_relative 'map_access'
require_relative 'oauth_setting'
require_relative 'personal_token'
require_relative 'story_id'

# Who an MCP request reads as, and which teams it may read. A personal token
# reads the teams its person ticked and can still open, as that person, and so
# does an app's sign-in. No team is chosen for the request: each tool asks
# where a map or story is before reading it.
#
# A team is open (given, and not suspended), suspended (given, and
# suspended), withheld (one of the person's own teams they did not give) or
# unknown (anything else), so a refusal says why for the person's own teams
# and never confirms that another team's story exists. The person's own teams
# are those whose maps they can open.
class McpAccess
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  attr_reader :team_ids, :person_id, :client, :grant_id

  def initialize(team_ids:, person_id: nil, client: nil, grant_id: nil, own_team_ids: team_ids)
    @team_ids = team_ids
    @person_id = person_id
    @client = client
    @grant_id = grant_id
    @own_team_ids = own_team_ids
  end

  # What a personal token reads, or nil for anything that is not a live one.
  def self.for_token(token, now:)
    return unless token

    grant_id, person_id, client_id = live_grant(PersonalToken.digest(token), now)
    return unless grant_id

    open = MapAccess.team_ids_for(person_id)
    given = BypassRLS.call { DB[:oauth_grant_teams].where(grant_id: grant_id).select_map(:team_id) }
    new(team_ids: given & open, person_id: person_id, client: client_id ? URI(client_id).host : 'personal token',
      grant_id: grant_id, own_team_ids: open)
  end

  # The grant of a token Mainline issued, live or not: an expired or revoked
  # one counts against its own grant, never against the address it came from.
  def self.grant_of(token)
    return unless token

    DB[:oauth_access_tokens].where(token_hash: PersonalToken.digest(token)).get(:grant_id)
  end

  # The grant, person and app behind a token that has not expired, if the
  # grant itself has neither expired nor been revoked. A personal token's
  # grant has no app; an app's is read only while OAuth is on.
  def self.live_grant(digest, now)
    grants = Sequel[:oauth_grants]
    tokens = DB[:oauth_access_tokens].join(:oauth_grants, id: :grant_id)
    tokens = tokens.where(client_id: nil) unless OauthSetting.on?
    tokens
      .where(token_hash: digest, revoked_at: nil)
      .where(Sequel[:oauth_access_tokens][:expires_at] > now)
      .where(Sequel.|({ grants[:expires_at] => nil }, grants[:expires_at] > now))
      .get([grants[:id], :person_id, :client_id])
  end

  def used(now)
    DB[:oauth_grants].where(id: @grant_id).update(last_used_at: now) if @grant_id
  end

  # The teams it may read now: given, and not suspended.
  def readable_team_ids
    Team.where(id: team_ids, suspended_at: nil).order(:name).select_map(:id)
  end

  def readable?
    readable_team_ids.any?
  end

  def place(team_id)
    if team_ids.include?(team_id)
      [Team.where(id: team_id, suspended_at: nil).empty? ? :suspended : :open, team_id]
    elsif @own_team_ids.include?(team_id)
      [:withheld, team_id]
    else
      [:unknown, nil]
    end
  end

  # Where the story the ID names is, among the person's own teams: by its
  # whole ID, or the start of it shown on its card. The story's ID comes back
  # only when it may be read.
  def story(given)
    found = BypassRLS.call { StoryId.matching(Story.where(team_id: @own_team_ids), given).select_map(%i[id team_id]) }
    return [:ambiguous, nil, nil] if found.size > 1

    id, team_id = found.first
    status, team_id = place(team_id)
    [status, team_id, (id if status == :open)]
  end

  # Where the map with this whole ID is.
  def map(map_id)
    return [:unknown, nil] unless map_id.to_s.match?(UUID)

    place(BypassRLS.call { Map.where(id: map_id).get(:team_id) })
  end
end
