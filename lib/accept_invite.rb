# frozen_string_literal: true

require_relative 'bypass_rls'
require_relative 'invite_token'

# An invitation to a team taken up by the person it was sent to. The pending
# invitation for a link counts only for the email address it went to, and
# taking it up makes that person a working member of its team: someone who
# left comes back, and someone still on the team stays as they are. Whether
# the team has room is the app's to check between the two.
module AcceptInvite
  def self.invitation_for(token:, email:)
    invitation = Invitation.pending(token)
    invitation if invitation && invitation.email_bidx == BlindIndex.generate_bidx(email, key: Lockbox.master_key)
  end

  def self.join(invitation:, person:, now:)
    existing = TeamMembership.where(team_id: invitation.team_id, person_id: person.id).first
    if existing
      existing.update(left_at: nil, working: true) if existing.left_at
    else
      TeamMembership.create(team_id: invitation.team_id, person_id: person.id, working: true)
    end
    BypassRLS.call { invitation.update(accepted_at: now) }
  end
end
