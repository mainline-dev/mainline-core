# frozen_string_literal: true

module BypassRLS
  def self.call(&block)
    DB.transaction(savepoint: true) do
      DB["SELECT set_config('app.rls_bypass', 'true', true)"].get
      block.call
    end
  ensure
    begin
      DB["SELECT set_config('app.rls_bypass', 'false', true)"].get
    rescue Sequel::DatabaseError => e
      warn "BypassRLS ensure failed: #{e.message}"
    end
  end
end
