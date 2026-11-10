# frozen_string_literal: true

# Whether someone signing up with an email address has to prove it is theirs.
# A development install sends no mail, so there it would only be a link to
# click on the same screen; everywhere else it is required.
module EmailVerification
  def self.required?
    ENV.fetch('RACK_ENV', nil) != 'development'
  end
end
