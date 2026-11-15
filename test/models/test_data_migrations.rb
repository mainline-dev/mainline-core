# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/agent_reads'

Sequel.extension :migration

# Data migrations change rows that are already there, so each is applied here
# to rows like the ones it will meet.
describe 'Data migrations' do
  def apply_migration(name)
    load Dir[File.expand_path("../../migrate/*_#{name}.rb", __dir__)].fetch(0)
    Sequel::Migration.descendants.pop.apply(DB, :up)
  end

  describe 'backfilling agent reads' do
    before do
      @team = Team.create(name: 'Backfill Team')
      SetTeamContext.call(@team.id)
      person = Person.create(name: 'Alice', email: 'alice@backfill.co')
      @map = Map.create(team_id: @team.id, name: 'Product', position: 1000)
      activity = Activity.create(map_id: @map.id, team_id: @team.id, name: 'Browse', position: 1000)
      @story = lambda { |title, flagged|
        Story.create(map_id: @map.id, team_id: @team.id, title: title, position: 1000, created_by_id: person.id,
          task_id: Task.create(map_id: @map.id, team_id: @team.id, activity_id: activity.id, name: title,
            position: 1000).id, agent_assisted: flagged)
      }
    end

    def reads_of(story)
      Event.where(entity_id: story.id, action: 'agent_read').all
    end

    it 'gives a story flagged before reads were logged one read, by its coding agent, marked as backfilled' do
      flagged = @story.call('Flagged', true)

      apply_migration('backfill_agent_reads')

      reads = reads_of(flagged)

      assert_equal [@team.mcp_actor_id], reads.map(&:actor_id)
      assert reads.first.after_state['backfilled']
      assert AgentReads.read?(flagged.id)
    end

    it 'leaves a flagged story that already has a read as it was' do
      flagged = @story.call('Read since', true)
      RecordEvent.call(actor_id: @team.mcp_actor_id, entity: flagged, action: 'agent_read')

      apply_migration('backfill_agent_reads')

      assert_equal 1, reads_of(flagged).size
    end

    it 'gives a story no coding agent read nothing' do
      unflagged = @story.call('Never read', false)

      apply_migration('backfill_agent_reads')

      assert_empty reads_of(unflagged)
    end
  end
end
