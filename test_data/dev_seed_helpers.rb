# frozen_string_literal: true

module DevSeedHelpers
  private

  def start_paired(title, task, person1, person2)
    story = create_story_timed(title, task)
    assign_person(story, person: @people[person1])
    assign_person(story, person: @people[person2])
    story
  end

  def start_solo(title, task, person_key)
    story = create_story_timed(title, task)
    assign_person(story, person: @people[person_key])
    story
  end

  def start_ensemble(title, task, *person_keys)
    story = create_story_timed(title, task)
    person_keys.each { |k| assign_person(story, person: @people[k]) }
    story
  end

  def create_story_timed(title, task)
    story = create_story(title, under_task: task)
    DB[:stories].where(id: story.id).update(created_at: Time.now)
    story
  end

  def deploy(title)
    deploy_story(find_story(title))
  end

  def release(title)
    release_story(find_story(title))
  end

  def leave_story(title, person_key)
    story = find_story(title)
    sa = story.story_assignments.detect { |a| a.person_id == @people[person_key].id }
    unassign_person(story, sa)
  end

  def tag_decoupling(title, strategy:, label: nil)
    story = find_story(title)
    edit_story(story, title: story.title, task_id: story.task_id,
      decoupling_strategy: strategy, decoupling_label: label)
  end

  def note_story(title, note_type:)
    add_story_note(find_story(title), note_type: note_type)
  end

  def dismiss_note(title, note_type:, person_key:)
    story = find_story(title)
    note = StoryNote.where(story_id: story.id, note_type: note_type, dismissed_at: nil).first
    dismiss_story_note(note, person: @people[person_key])
  end

  def find_story(title)
    Story.where(title: title).first
  end

  def advance_days(days)
    Timecop.travel(Time.now + (days * 24 * 3600)) if days.positive?
  end
end
