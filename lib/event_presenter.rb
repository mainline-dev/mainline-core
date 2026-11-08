# frozen_string_literal: true

module EventPresenter
  FIXED_DESCRIPTIONS = {
    'deployed'  => 'marked as deployed',
    'released'  => 'marked as released',
    'archived'  => 'archived',
    'reordered' => 'reordered'
  }.freeze

  DESCRIBERS = {
    'created'               => :describe_created,
    'deleted'               => :describe_deleted,
    'person_assigned'       => :describe_person_assigned,
    'person_unassigned'     => :describe_person_unassigned,
    'activated'             => :describe_activated,
    'deactivated'           => :describe_deactivated,
    'slice_changed'         => :describe_slice_change,
    'edited'                => :describe_edit,
    'task_changed'          => :describe_task_change,
    'collaboration_changed' => :describe_collaboration_change,
    'agent_read'            => :describe_agent_read,
    'split_out'             => :describe_split_out
  }.freeze

  STRATEGY_NAMES = {
    'flag'        => 'Feature flag',
    'bba'         => 'BBA',
    'dark_launch' => 'Dark launch'
  }.freeze

  def self.describe(event, lookup, include_name: true)
    return FIXED_DESCRIPTIONS[event.action] if FIXED_DESCRIPTIONS.key?(event.action)

    describer = DESCRIBERS[event.action]
    return event.action.tr('_', ' ') unless describer

    send(describer, event, lookup, include_name)
  end

  def self.describe_created(event, _lookup, include_name)
    label = event.after_state['title'] || event.after_state['name']
    label && include_name ? "created \"#{label}\"" : 'created'
  end

  def self.describe_deleted(event, _lookup, include_name)
    label = event.before_state['name'] || event.before_state['title']
    label && include_name ? "deleted \"#{label}\"" : 'deleted'
  end

  def self.describe_person_assigned(event, lookup, _include_name)
    name = resolve(lookup, :people, event.after_state['person_id']) || 'someone'
    "assigned #{name}"
  end

  def self.describe_person_unassigned(event, lookup, _include_name)
    name = resolve(lookup, :people, event.before_state['person_id']) || 'someone'
    reason = event.before_state['reason']
    reason ? "unassigned #{name} (#{reason})" : "unassigned #{name}"
  end

  def self.describe_activated(event, _lookup, _include_name)
    "activated (#{event.after_state['reason']}, #{event.after_state['assignment_count']} assignees)"
  end

  def self.describe_deactivated(event, _lookup, _include_name)
    "deactivated (#{event.after_state['reason']})"
  end

  def self.describe_task_change(event, lookup, _include_name)
    from_name = resolve(lookup, :tasks, event.before_state['task_id']) || 'unknown'
    to_name = resolve(lookup, :tasks, event.after_state['task_id']) || 'unknown'
    "moved from step: #{from_name} to step: #{to_name}"
  end

  def self.describe_collaboration_change(event, _lookup, _include_name)
    "#{event.before_state['mode'] || 'unknown'} to #{event.after_state['mode'] || 'unknown'}"
  end

  def self.describe_agent_read(event, _lookup, _include_name)
    ua = event.after_state['user_agent']
    ua ? "read by coding agent (#{ua})" : 'read by coding agent'
  end

  def self.describe_split_out(event, _lookup, _include_name)
    n = event.after_state['scenario_count']
    return 'split scenarios out to a new story' unless n

    "split #{n} #{n == 1 ? 'scenario' : 'scenarios'} out to a new story"
  end

  def self.describe_slice_change(event, lookup, _include_name)
    from_name = slice_name(lookup, event.before_state['release_slice_id'])
    to_name = slice_name(lookup, event.after_state['release_slice_id'])

    if from_name && to_name
      "moved from slice: #{from_name} to slice: #{to_name}"
    elsif to_name
      "moved to slice: #{to_name}"
    elsif from_name
      "removed from slice: #{from_name}"
    else
      'removed from slice'
    end
  end

  def self.slice_name(lookup, id)
    id ? (resolve(lookup, :slices, id) || 'unknown') : nil
  end

  def self.describe_edit(event, lookup, include_name)
    changes = [
      edit_task_change(event, lookup),
      edit_title_change(event, include_name),
      edit_name_change(event, include_name),
      edit_decoupling_change(event),
      edit_description_change(event, include_name)
    ].compact
    changes += association_changes(event, lookup, 'persona_ids', :personas, 'persona')
    changes += association_changes(event, lookup, 'activity_ids', :activities, 'activity')
    changes.empty? ? 'edited' : changes.join(', ')
  end

  def self.edit_task_change(event, lookup)
    return if event.before_state['task_id'] == event.after_state['task_id']

    describe_task_change(event, lookup, nil)
  end

  def self.edit_title_change(event, include_name)
    return if event.before_state['title'] == event.after_state['title']

    include_name ? "renamed to \"#{event.after_state['title']}\"" : 'renamed'
  end

  def self.edit_name_change(event, include_name)
    return if event.before_state['name'] == event.after_state['name'] || !event.after_state.key?('name')

    include_name ? "renamed \"#{event.before_state['name']}\" to \"#{event.after_state['name']}\"" : 'renamed'
  end

  def self.edit_decoupling_change(event)
    if event.before_state['decoupling_strategy'] != event.after_state['decoupling_strategy']
      decoupling_strategy_change(event.after_state)
    elsif event.before_state['decoupling_label'] != event.after_state['decoupling_label']
      decoupling_label_change(event.before_state['decoupling_label'], event.after_state['decoupling_label'])
    end
  end

  def self.decoupling_strategy_change(after_state)
    strat = after_state['decoupling_strategy']
    return 'decoupling tag removed' unless strat

    name = STRATEGY_NAMES[strat] || strat
    label = after_state['decoupling_label']
    label ? "tagged #{name} (#{label})" : "tagged #{name}"
  end

  def self.decoupling_label_change(from_label, to_label)
    return "label \"#{from_label}\" removed" unless to_label

    from_label ? "label changed from \"#{from_label}\" to \"#{to_label}\"" : "label set to \"#{to_label}\""
  end

  def self.edit_description_change(event, include_name)
    return if event.before_state['description'] == event.after_state['description']
    return unless event.after_state.key?('description')

    label = event.after_state['name'] || event.after_state['title']
    label && include_name ? "updated \"#{label}\" description" : 'description updated'
  end

  def self.association_changes(event, lookup, key, lookup_key, label)
    before_ids = Array(event.before_state[key])
    after_ids  = Array(event.after_state[key])
    group = lookup[lookup_key] || {}

    (after_ids - before_ids).map { |id| "added #{label} #{group[id]&.name || 'unknown'}" } +
      (before_ids - after_ids).map { |id| "removed #{label} #{group[id]&.name || 'unknown'}" }
  end

  def self.resolve(lookup, key, id)
    lookup[key]&.dig(id)&.name
  end

  private_class_method(*DESCRIBERS.values, :slice_name, :edit_task_change, :edit_title_change,
    :edit_name_change, :edit_decoupling_change, :decoupling_strategy_change, :decoupling_label_change,
    :edit_description_change, :association_changes, :resolve)
end
