# frozen_string_literal: true

require_relative 'deploy_story'
require_relative 'story_id'

# A build pipeline's report of the stories it deployed. Each active story of
# the team's that the report names is marked deployed once, however many
# times or ways the report names it; anything else it names is passed over.
# A report naming more than MOST stories is refused whole, so one request
# cannot ask for unbounded work.
module ReportDeploys
  MOST = 100
  TOO_MANY = "at most #{MOST} story_ids in one request".freeze
  Result = Struct.new(:success?, :error, :deployed, keyword_init: true)

  def self.call(team:, actor:, story_ids:, now:)
    return Result.new(success?: false, error: TOO_MANY) if story_ids.length > MOST

    stories = named(team, story_ids)
    stories.each { |story| DeployStory.call(story: story, actor: actor, now: now) }
    Result.new(success?: true, deployed: stories.length)
  end

  # The team's active stories among those named, each once.
  def self.named(team, story_ids)
    active = Story.where(map_id: Map.where(team_id: team.id).select(:id), status: 'active')
    story_ids.filter_map { |id| StoryId.matching(active, id).first }.uniq
  end
end
