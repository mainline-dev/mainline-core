# frozen_string_literal: true

# The refresh tokens a coding agent's app swaps for new tokens. One belongs to
# its grant, as the grant's codes and access tokens do, and goes with it. It
# lasts 60 days and works once: each use spends it and gives a new one, and a
# spent one used again revokes the grant. Only its SHA-256 digest is kept.
Sequel.migration do
  up do
    create_table(:oauth_refresh_tokens) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      foreign_key :grant_id, :oauth_grants, type: :uuid, null: false, on_delete: :cascade
      String :token_hash, size: 64, null: false, unique: true
      column :expires_at, 'timestamptz', null: false
      column :used_at, 'timestamptz'
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      index :grant_id
    end

    run 'GRANT SELECT, INSERT, UPDATE, DELETE ON oauth_refresh_tokens TO mainline_app'
  end

  down do
    drop_table(:oauth_refresh_tokens)
  end
end
