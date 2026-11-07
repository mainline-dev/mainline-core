# frozen_string_literal: true

class Mainline
  hash_branch('teams', 'inventory') do |r|
    r.get do
      @inventory = Inventory.call(team_id: @team.id)
      @page_title = 'Inventory - Mainline'
      view 'inventory'
    end
  end
end
