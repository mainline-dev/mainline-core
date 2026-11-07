# frozen_string_literal: true

class Actor < Sequel::Model
  one_to_one :person

  def validate
    super
    validates_includes %w[person system], :kind
  end
end
