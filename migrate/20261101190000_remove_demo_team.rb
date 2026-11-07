# frozen_string_literal: true

# The demo is gone: the 14-day trial replaces it. Delete the demo team, its
# data, its people and the demo system actor the way the demo wipe did, then
# drop the system team flag, which only marked the demo team.
Sequel.migration do
  up do
    team_id = '00000000-0000-4000-8000-000000000001'
    system_actor_id = 'a1a1a1a1-0000-4000-8000-000000000001'

    run "SELECT set_config('app.rls_bypass', 'true', true)"
    run "SELECT set_config('app.current_team_id', '#{team_id}', true)"

    if from(:teams).where(id: team_id).any?
      from(:teams).where(id: team_id).update(creator_id: nil)
      run "SELECT delete_team_data('#{team_id}')"

      repo_ids = from(:monitored_repos).where(team_id: team_id).select(:id)
      from(:integration_events).where(monitored_repo_id: repo_ids).delete
      from(:tracked_branches).where(monitored_repo_id: repo_ids).delete
      from(:monitored_repos).where(team_id: team_id).delete
      from(:team_installations).where(team_id: team_id).delete
      from(:team_subscriptions).where(team_id: team_id).delete

      person_ids = from(:team_memberships).where(team_id: team_id).select_map(:person_id)
      from(:team_memberships).where(team_id: team_id).delete
      from(:invitations).where(team_id: team_id).delete

      person_ids.each do |pid|
        next if from(:team_memberships).where(person_id: pid).any?
        next if from(:teams).where(creator_id: pid).any?

        from(:person_identities).where(person_id: pid).delete
        from(:signup_attributions).where(person_id: pid).delete
        from(:feedbacks).where(person_id: pid).delete
        from(:invitations).where(invited_by: pid).delete

        actor_id = from(:people).where(id: pid).get(:actor_id)
        from(:people).where(id: pid).delete
        from(:actors).where(id: actor_id).delete if actor_id
      end

      from(:teams).where(id: team_id).delete
    end

    from(:actors).where(id: system_actor_id).delete

    alter_table(:teams) do
      drop_column :system_team
    end
  end

  down do
    alter_table(:teams) do
      add_column :system_team, TrueClass, null: false, default: false
    end
  end
end
