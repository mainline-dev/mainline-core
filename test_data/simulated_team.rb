# frozen_string_literal: true

class SimulatedTeam # rubocop:disable Metrics/ClassLength
  include MainlineDSL
  include Minitest::Assertions
  include DevSeedHelpers

  attr_accessor :assertions

  SECONDS_PER_DAY = 86_400

  def initialize(persona, name:, duration: nil, map_name: nil, team: nil, current_work: true)
    @persona = persona
    @team_name = name
    @map_name = map_name
    @duration_override = duration
    @existing_team = team
    @start_current_work = current_work
    @assertions = 0
    @rng = Random.new
    @pair_history = Hash.new(0)
    @pair_index = 0
  end

  def seed
    @duration = @duration_override || @rng.rand(@persona.project_duration)
    start = Time.now - ((@duration + 2) * SECONDS_PER_DAY)
    Timecop.freeze(start)
    if @existing_team
      @team = @existing_team
      load_existing_people
    else
      setup_team(name: @team_name)
      generate_people
    end
    DB["SELECT set_config('app.current_team_id', ?, false)", @team.id.to_s].get
    generate_map
    generate_backlog
    simulate_work
    Timecop.return
    puts "  #{@team_name} (#{@persona.label}): #{@people.size} people, " \
         "#{@duration} days, #{Story.where(map_id: @map.id).count} stories"
  end

  private

  def load_existing_people
    @people = Person
      .join(:team_memberships, person_id: :id)
      .where(Sequel[:team_memberships][:team_id] => @team.id)
      .where(Sequel[:team_memberships][:working] => true)
      .select_all(:people)
      .all
    login_as(@people.first) if @people.any?
  end

  def generate_people
    count = @rng.rand(@persona.team_size)
    names = NamePools::PEOPLE.sample(count, random: @rng)
    @people = names.map { |name|
      add_person(name: name, email: "#{name.downcase.gsub(/\s+/, '.')}@#{@team_name.downcase.gsub(/\s+/, '')}.dev")
    }
  end

  def generate_map
    create_map(name: @map_name || "#{@team_name} Map")
    @persona_obj = create_persona('User')

    domain_count = @rng.rand(@persona.activity_count)
    domains = NamePools::DOMAINS.sample(domain_count, random: @rng)

    @tasks_list = []
    domains.each do |domain|
      activity = create_activity(domain[:activity], for_personas: [@persona_obj])
      task_count = @rng.rand(@persona.tasks_per_activity)
      tasks = domain[:tasks].sample(task_count, random: @rng)
      tasks.each do |task_name|
        task = create_task(task_name, under_activity: activity)
        @tasks_list << { task: task, domain: domain }
      end
    end
  end

  def generate_backlog
    stories_needed = estimate_stories_needed
    @story_queue = []
    @title_counts = Hash.new(0)

    stories_needed.times do
      slot = @tasks_list.sample(random: @rng)
      base_title = slot[:domain][:stories].sample(random: @rng)
      title = unique_title(base_title)
      @story_queue << { title: title, task: slot[:task] }
    end
  end

  def unique_title(base)
    @title_counts[base] += 1
    count = @title_counts[base]
    count == 1 ? base : "#{base} v#{count}"
  end

  def estimate_stories_needed
    avg_cycle = ((@persona.cycle_time.min + @persona.cycle_time.max) / 2.0).ceil
    throughput = (@duration.to_f / avg_cycle * @persona.max_wip).ceil
    backlog_end = @rng.rand(@persona.planned_backlog)
    current_wip = @persona.max_wip
    throughput + backlog_end + current_wip + 5
  end

  def simulate_work
    @current_reserve = @start_current_work ? @story_queue.pop(@persona.max_wip) : []
    day = 0
    active = []
    completed = 0

    while day <= @duration && (@story_queue.any? || active.any?)
      active, released_today = release_ready(active, day)
      completed += released_today

      active = deploy_ready(active, day)

      active = start_new_work(active, day)

      advance_days(1)
      day += 1
    end

    leave_stale_deployed(active)
    start_current_work
  end

  def start_current_work
    return if @current_reserve.empty?

    Timecop.return
    Timecop.freeze(Time.now - SECONDS_PER_DAY)

    busy_ids = StoryAssignment.where(team_id: @team.id).select_map(:person_id).to_set
    @current_reserve.each do |entry|
      available = @people.reject { |p| busy_ids.include?(p.id) }
      break if available.size < 2

      story = create_story_timed(entry[:title], entry[:task])
      assignees = pick_assignees_from(available, @duration + 1)
      assignees.each { |person| assign_person(story, person: person) }
      busy_ids.merge(assignees.map(&:id))
    end
  end

  def release_ready(active, day)
    released_count = 0
    remaining = []

    active.each do |item|
      if item[:deploy_day] && (day - item[:deploy_day]) >= pick_release_gap
        release_story(item[:story])
        released_count += 1
      else
        remaining << item
      end
    end

    [remaining, released_count]
  end

  def deploy_ready(active, day)
    active.each do |item|
      next if item[:deploy_day]

      if (day - item[:started_day]) >= item[:cycle_time]
        deploy_story(item[:story])
        item[:deploy_day] = day
      end
    end
    active
  end

  def start_new_work(active, day)
    active_wip = active.count { |s| !s[:deploy_day] }
    busy_ids = active.flat_map { |s| s[:pair].map(&:id) }.to_set

    while active_wip < @persona.max_wip && @story_queue.any?
      available = @people.reject { |p| busy_ids.include?(p.id) }
      break if available.size < 2

      item = start_one_story(available, day)
      busy_ids.merge(item[:pair].map(&:id))
      active << item
      active_wip += 1
    end

    active
  end

  def start_one_story(available, day)
    entry = @story_queue.shift
    story = create_story_timed(entry[:title], entry[:task])
    assignees = pick_assignees_from(available, day)
    assignees.each { |person| assign_person(story, person: person) }
    maybe_go_solo(story, assignees)
    cycle = @rng.rand(@persona.cycle_time)
    { story: story, pair: assignees, started_day: day, deploy_day: nil, cycle_time: cycle }
  end

  def maybe_go_solo(story, assignees)
    return unless solo_story?(assignees)

    leaver = assignees.pop
    sa = StoryAssignment.where(story_id: story.id, person_id: leaver.id).first
    unassign_person(story, sa)
  end

  def pick_assignees_from(available, day)
    if @rng.rand < @persona.ensemble_chance && available.size >= 3
      available.sample(3, random: @rng)
    else
      pick_pair_from(available, day)
    end
  end

  def solo_story?(assignees)
    @persona.solo_chance.positive? && assignees.size == 2 && @rng.rand < @persona.solo_chance
  end

  def pick_pair_from(available, _day)
    case @persona.rotation
    when :full
      pick_pair_round_robin(available)
    when :moderate
      pick_pair_moderate(available)
    when :clique
      pick_pair_clique(available)
    end
  end

  def pick_pair_round_robin(available)
    all_pairs = available.combination(2).to_a.shuffle(random: @rng)
    pair = all_pairs[@pair_index % all_pairs.size]
    @pair_index += 1
    pair
  end

  def pick_pair_moderate(available)
    all_pairs = available.combination(2).to_a
    weights = all_pairs.map { |p| 1.0 / ((@pair_history[pair_key(p)] || 0) + 1) }
    pair = weighted_sample(all_pairs, weights)
    @pair_history[pair_key(pair)] += 1
    pair
  end

  def pick_pair_clique(available)
    if available.size < 4
      available.sample(2, random: @rng)
    else
      clique_a = available[0..1]
      clique_b = available[2..3]
      if @rng.rand < 0.85
        [clique_a, clique_b].sample(random: @rng)
      else
        available.sample(2, random: @rng)
      end
    end
  end

  def pair_key(pair)
    pair.map(&:id).sort.join('-')
  end

  def weighted_sample(items, weights)
    total = weights.sum
    r = @rng.rand * total
    cumulative = 0.0
    items.zip(weights).each do |item, weight|
      cumulative += weight
      return item if r <= cumulative
    end
    items.last
  end

  def pick_release_gap
    @rng.rand(@persona.release_gap)
  end

  def leave_stale_deployed(active)
    stale_target = @persona.stale_deployed.is_a?(Range) ? @rng.rand(@persona.stale_deployed) : @persona.stale_deployed

    active.each do |item|
      deploy_story(item[:story]) unless item[:deploy_day]
    end

    to_release = [active.size - stale_target, 0].max
    active.first(to_release).each do |item|
      release_story(item[:story])
    end
  end
end
