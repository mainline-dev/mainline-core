# frozen_string_literal: true

require_relative 'record_event'

# Saves a story's title, step, release slice and how it is decoupled, and
# records what each was and became. A story moved to another step goes after
# the stories already there. A label is kept only with a strategy, and at
# most 50 characters of it. A released story changes only how it was
# decoupled, so its flags can still be cleaned up after release.
module EditStory
  Result = Struct.new(:success?, :errors, keyword_init: true)
  TITLE_LENGTH = 200
  LABEL_LENGTH = 50

  def self.call(story:, actor:, title:, task_id:, release_slice_id:, decoupling_strategy:, decoupling_label:)
    decoupling = decoupling(decoupling_strategy, decoupling_label)
    return save(story, actor, decoupling) if story.status == 'released'

    errors = errors(title, task_id)
    return Result.new(success?: false, errors: errors) unless errors.empty?

    updates = { title: title, task_id: task_id }
    updates[:position] = (Story.where(task_id: task_id, archived_at: nil).max(:position) || 0) + 1000 if task_id != story.task_id
    updates[:release_slice_id] = release_slice_id.to_s.empty? ? nil : release_slice_id
    save(story, actor, updates.merge(decoupling))
  end

  def self.decoupling(strategy, label)
    strategy = nil if strategy.to_s.empty?
    label = strategy && !label.to_s.empty? ? label[0, LABEL_LENGTH] : nil
    { decoupling_strategy: strategy, decoupling_label: label }
  end

  def self.errors(title, task_id)
    errors = []
    errors << 'Title is required' unless title
    errors << "Title must be #{TITLE_LENGTH} characters or fewer" if title && title.length > TITLE_LENGTH
    errors << 'Step is required' unless task_id
    errors
  end

  # What changed, recorded with what each field was before. Where the story
  # sits in its step is recorded as it became, never as it was.
  def self.save(story, actor, updates)
    DB.transaction do
      before = updates.except(:position).to_h { |field, _| [field, story[field]] }
      story.update(updates)
      RecordEvent.call(actor_id: actor.id, entity: story, action: 'edited', before_state: before, after_state: updates)
    end
    Result.new(success?: true, errors: [])
  end
  private_class_method :decoupling, :errors, :save
end
