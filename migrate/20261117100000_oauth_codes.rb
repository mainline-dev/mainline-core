# frozen_string_literal: true

# The codes a coding agent's app exchanges for its tokens once its person has
# approved a sign-in. A code belongs to its grant, as the grant's tokens do,
# and goes with it. It works once, for a minute, and only for the app,
# address, PKCE challenge and resource it was given for. Only its SHA-256
# digest is kept, looked up by digest.
Sequel.migration do
  up do
    create_table(:oauth_codes) do
      column :id, :uuid, default: Sequel.lit('gen_random_uuid()'), primary_key: true
      foreign_key :grant_id, :oauth_grants, type: :uuid, null: false, on_delete: :cascade
      String :code_hash, size: 64, null: false, unique: true
      String :client_id, size: 2048, null: false
      String :redirect_uri, size: 2048, null: false
      String :code_challenge, size: 128, null: false
      String :resource, size: 2048, null: false
      column :expires_at, 'timestamptz', null: false
      column :used_at, 'timestamptz'
      column :created_at, 'timestamptz', null: false, default: Sequel.lit('now()')

      index :grant_id
    end

    run 'GRANT SELECT, INSERT, UPDATE, DELETE ON oauth_codes TO mainline_app'
  end

  down do
    drop_table(:oauth_codes)
  end
end
