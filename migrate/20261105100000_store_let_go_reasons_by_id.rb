# frozen_string_literal: true

# An exhibit let go keeps the reason as the group's id, not its title on
# screen, so the wording can change without splitting storage into two reasons.
Sequel.migration do
  reasons = {
    'stale'   => 'Untouched for over a year',
    'dupes'   => 'Probably the same ticket twice',
    'repro'   => 'Bugs nobody could reproduce',
    'vague'   => 'Too vague to act on',
    'covered' => 'Already covered by a promoted story'
  }

  up do
    reasons.each { |id, title| from(:museum_items).where(storage_note: title).update(storage_note: id) }
  end

  down do
    reasons.each { |id, title| from(:museum_items).where(storage_note: id).update(storage_note: title) }
  end
end
