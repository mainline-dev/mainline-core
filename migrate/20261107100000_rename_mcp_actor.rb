# frozen_string_literal: true

# The actor each team's MCP reads are recorded under keeps its name in the
# table, so teams that already have one need the new name as well.
Sequel.migration do
  up do
    from(:actors).where(kind: 'system', name: 'AI Agent').update(name: 'Coding agent')
  end

  down do
    from(:actors).where(kind: 'system', name: 'Coding agent').update(name: 'AI Agent')
  end
end
