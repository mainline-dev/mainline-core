# frozen_string_literal: true

require_relative 'business_days'

module Inventory
  Entry = Struct.new(:story, :band, :business_days_since_deploy, keyword_init: true)
  Summary = Struct.new(:in_flight, :aging, :stale, :items, :cleanup, keyword_init: true)

  def self.call(team_id:)
    entries = entries(team_id)
    counts = entries.map(&:band).tally

    Summary.new(
      in_flight: counts.fetch(:in_flight, 0),
      aging:     counts.fetch(:aging, 0),
      stale:     counts.fetch(:stale, 0),
      items:     entries,
      cleanup:   cleanup_stories(team_id)
    )
  end

  def self.entries(team_id)
    aging_threshold = TeamConstraint.for_team(team_id, 'inventory_aging_days', default: 4)
    stale_threshold = TeamConstraint.for_team(team_id, 'inventory_stale_days', default: 10)
    now = Time.now

    deployed_stories(team_id).reject { |s| s.last_deployed_at.nil? }.map { |story|
      biz_days = BusinessDays.between(story.last_deployed_at, now)
      Entry.new(story: story, band: band_for(biz_days, aging_threshold, stale_threshold),
        business_days_since_deploy: biz_days)
    }
  end
  private_class_method :entries

  def self.band_for(biz_days, aging_threshold, stale_threshold)
    if biz_days >= stale_threshold
      :stale
    elsif biz_days >= aging_threshold
      :aging
    else
      :in_flight
    end
  end
  private_class_method :band_for

  # Released stories still carrying a decoupling tag, whose scaffolding needs cleaning up.
  def self.cleanup_stories(team_id)
    Story
      .where(team_id: team_id, status: 'released')
      .exclude(decoupling_strategy: nil)
      .order(:released_at)
      .all
  end
  private_class_method :cleanup_stories

  def self.deployed_stories(team_id)
    Story
      .where(team_id: team_id, status: 'active')
      .where { deploy_count > 0 } # rubocop:disable Style/NumericPredicate -- Sequel virtual row
      .order(:last_deployed_at)
      .all
  end
  private_class_method :deployed_stories
end
