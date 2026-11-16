# frozen_string_literal: true

# Revokes one of the person's grants, a personal token or an OAuth sign-in, so
# no coding agent can use it again. Only the person's own grant, and only
# once; anything that is not a grant ID is turned away before the database.
module RevokeGrant
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  def self.call(person:, grant_id:, now: Time.now)
    return false unless grant_id.to_s.match?(UUID)

    OauthGrant.where(id: grant_id, person_id: person.id, revoked_at: nil).update(revoked_at: now) == 1
  end
end
