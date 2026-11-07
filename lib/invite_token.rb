# frozen_string_literal: true

require 'digest'

module InviteToken
  def self.digest(token)
    Digest::SHA256.hexdigest(token)
  end
end
