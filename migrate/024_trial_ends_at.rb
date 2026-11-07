# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :teams, :trial_ends_at, DateTime

    from(:teams).where(billing_state: 'trialing').update(
      Sequel.lit("trial_ends_at = created_at + interval '14 days'")
    )
  end

  down do
    drop_column :teams, :trial_ends_at
  end
end
