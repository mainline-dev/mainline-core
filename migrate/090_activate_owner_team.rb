# frozen_string_literal: true

Sequel.migration do
  up do
    next if ENV['RACK_ENV'] == 'test'

    from(:teams)
      .where(id: '959664cf-45b6-4020-ae2a-c4bb362ac569')
      .update(billing_state: 'active', paddle_subscription_id: nil)
  end

  down do
    nil
  end
end
