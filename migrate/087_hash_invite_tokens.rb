# frozen_string_literal: true

Sequel.migration do
  up do
    run "SELECT set_config('app.rls_bypass', 'true', true)"
    run "UPDATE invitations SET token = encode(sha256(token::bytea), 'hex')"
  end

  down do
    # Plaintext tokens cannot be recovered from digests. Outstanding
    # invitations expire within 7 days; nothing to restore.
  end
end
