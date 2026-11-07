Sequel.migration do
  up do
    add_column :team_memberships, :working, TrueClass, null: false, default: true
  end

  down do
    drop_column :team_memberships, :working
  end
end
