# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :people, :email_verified_at, 'timestamptz'

    from(:people).update(email_verified_at: Sequel.lit('now()'))
  end

  down do
    drop_column :people, :email_verified_at
  end
end
