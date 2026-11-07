# frozen_string_literal: true

class TeamInstallation < Sequel::Model
  many_to_one :team
end
