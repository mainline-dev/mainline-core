# models/invitation.rb
# frozen_string_literal: true

class Invitation < Sequel::Model
  include EncryptedEmail

  many_to_one :team

  # The unaccepted, unexpired invitation for a token, on any team: whoever
  # holds the link has no team context yet.
  def self.pending(token)
    return unless token

    BypassRLS.call { where(token: InviteToken.digest(token), accepted_at: nil).where { expires_at > Time.now }.first }
  end
end
