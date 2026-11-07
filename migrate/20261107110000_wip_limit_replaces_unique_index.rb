# frozen_string_literal: true

# A team's WIP limit can now be above one, so a unique index can no longer
# hold it. AssignPerson enforces the limit in the transaction that assigns a
# story. The new index keeps counting a person's stories fast. Going down
# fails if anyone is on two stories.
Sequel.migration do
  up do
    run 'DROP INDEX idx_one_active_story_per_person'
    run 'CREATE INDEX idx_story_assignments_person_team ON story_assignments (person_id, team_id)'
  end

  down do
    run 'DROP INDEX idx_story_assignments_person_team'
    run 'CREATE UNIQUE INDEX idx_one_active_story_per_person ON story_assignments (person_id, team_id)'
  end
end
