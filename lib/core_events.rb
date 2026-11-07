# frozen_string_literal: true

# Core announces what happened; code in its own files subscribes. Subscribers
# run straight away, inside the request or transaction that published, in
# the order they subscribed. Published so far:
#   :team_created  team_id:, creator_id:
#   :team_deleted  team_id:
module CoreEvents
  Subscription = Data.define(:event, :block)

  @subscriptions = []

  class << self
    def subscribe(event, &block)
      Subscription.new(event: event, block: block).tap { |sub| @subscriptions << sub }
    end

    def unsubscribe(subscription)
      @subscriptions.delete(subscription)
    end

    def publish(event, **payload)
      @subscriptions.select { |sub| sub.event == event }.each { |sub| sub.block.call(payload) }
    end
  end
end
