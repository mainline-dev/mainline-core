# frozen_string_literal: true

# Who worked with whom in the window: a pair's story count and days since
# they last paired. The team's AI agent takes a column too, once it has read
# a story over MCP: its pair with a person counts the stories it read while
# that person was on them.
module PairingMatrix
  Result = Struct.new(
    :people, :agent, :pairs, :story_counts, :current_pairs, :current_solos, keyword_init: true
  ) do
    def columns
      people + [agent].compact
    end

    # The person's id when one of the two is the agent, else nil.
    def agent_with(row, col)
      return unless agent
      return col.id if row.id == agent.id

      row.id if col.id == agent.id
    end
  end
  Agent = Struct.new(:id, :name)

  ONE_DAY = 86_400
  COLLABORATIVE_MODES = %w[paired ensemble].freeze

  def self.call(team_id:, days: 180)
    cutoff = Time.now - (days * ONE_DAY)
    qualified = qualified_stories(collaboration_events(team_id, cutoff), deployed_story_ids(team_id, cutoff))
    reads = agent_reads(team_id, cutoff)
    last_paired_at, story_counts = tally_pairs(qualified.values + reads)
    current_pairs, current_solos = current_pairs_and_solos(team_id)

    Result.new(
      people: team_people(team_id),
      agent: agent_of(reads),
      pairs: last_paired_at.transform_values { |t| ((Time.now - t) / ONE_DAY).floor },
      story_counts: story_counts,
      current_pairs: current_pairs, current_solos: current_solos
    )
  end

  def self.tally_pairs(events)
    last_paired_at = {}
    stories = Hash.new { |h, k| h[k] = Set.new }
    events.each do |event|
      pair_ids(event).combination(2).each do |id_a, id_b|
        key = [id_a, id_b].sort
        last_paired_at[key] = [last_paired_at[key], event.occurred_at].compact.max
        stories[key] << event.entity_id
      end
    end
    [last_paired_at, stories.transform_values(&:size)]
  end

  def self.pair_ids(event)
    return person_ids(event) unless event.action == 'agent_read'

    person_ids(event) + [event.actor_id]
  end

  def self.agent_reads(team_id, cutoff)
    Event
      .where(team_id: team_id, action: 'agent_read')
      .where { occurred_at >= cutoff }
      .order(:occurred_at)
      .all
  end

  def self.agent_of(reads)
    actor = reads.first&.actor
    Agent.new(actor.id, actor.name) if actor
  end

  def self.team_people(team_id)
    Person
      .join(:team_memberships, person_id: :id)
      .where(Sequel[:team_memberships][:team_id] => team_id)
      .where(Sequel[:team_memberships][:working] => true)
      .where(Sequel[:team_memberships][:left_at] => nil)
      .select_all(:people)
      .order(Sequel[:people][:name])
      .all
  end

  def self.collaboration_events(team_id, cutoff)
    Event
      .where(team_id: team_id, action: 'collaboration_changed')
      .where { occurred_at >= cutoff }
      .order(:entity_id, :event_no)
      .all
  end

  def self.qualified_stories(events, deploy_stories)
    events.group_by(&:entity_id).each_with_object({}) do |(story_id, story_events), result|
      story_events = story_events.select(&:after_state)
      peak = peak_event(story_events)
      next unless peak && counts_as_paired?(story_id, story_events, deploy_stories)

      result[story_id] = peak
    end
  end

  def self.peak_event(story_events)
    story_events
      .select { |e| collaborative?(e) }
      .max_by { |e| person_ids(e).length }
  end

  def self.counts_as_paired?(story_id, story_events, deploy_stories)
    collaborative?(story_events.last) ||
      deploy_stories.include?(story_id) ||
      transient_duration(story_events) >= ONE_DAY
  end

  def self.collaborative?(event)
    COLLABORATIVE_MODES.include?(event.after_state['mode'])
  end

  def self.person_ids(event)
    event.after_state['person_ids'] || []
  end

  def self.transient_duration(story_events)
    started = nil
    total = 0
    story_events.each do |event|
      next unless event.after_state

      if collaborative?(event)
        started ||= event.occurred_at
      elsif started
        total += event.occurred_at - started
        started = nil
      end
    end
    total += Time.now - started if started
    total
  end

  def self.deployed_story_ids(team_id, cutoff)
    Event
      .where(team_id: team_id, action: 'deployed')
      .where { occurred_at >= cutoff }
      .select_map(:entity_id)
      .to_set
  end

  def self.current_pairs_and_solos(team_id)
    assignments = StoryAssignment.where(team_id: team_id).select(:story_id, :person_id).all
    by_story = assignments.group_by(&:story_id)
    pairs = {}
    solos = Set.new
    by_story.each_value do |sas|
      if sas.length == 1
        solos << sas.first.person_id
      else
        sas.map(&:person_id).combination(2).each do |pid_a, pid_b|
          pairs[[pid_a, pid_b].sort] = true
        end
      end
    end
    [pairs, solos]
  end

  private_class_method :tally_pairs, :pair_ids, :agent_reads, :agent_of,
    :team_people, :collaboration_events, :qualified_stories,
    :peak_event, :counts_as_paired?, :collaborative?, :person_ids,
    :transient_duration, :deployed_story_ids, :current_pairs_and_solos
end
