# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/let_go'
require_relative '../../lib/let_go_prompt'

describe LetGoPrompt do
  cover 'LetGoPrompt*'

  before do
    Timecop.freeze(Time.utc(2026, 6, 15, 12, 0, 0))
    @team = Team.create(name: 'Test')
    SetTeamContext.call(@team.id)
    @person = Person.create(name: 'Alice', email: 'alice@test.mainline')
  end

  after do
    Timecop.return
  end

  def add(key, summary: "Shoppers can do the thing numbered #{key}", created: Time.utc(2026, 5, 1))
    MuseumItem.create(team_id: @team.id, source_key: key, issue_type: 'Story', summary: summary, description: 'Some detail',
      source_created_at: created, comments: Sequel.pg_jsonb([]), links: Sequel.pg_jsonb([]), labels: Sequel.pg_jsonb([]))
  end

  def stale(key)
    add(key, created: Time.utc(2024, 8, 1))
  end

  def prompt
    LetGo.detect(team_id: @team.id)
    LetGoPrompt.call(team: @team.refresh)
  end

  it 'asks once there are ten suggestions' do
    (1..10).each { |number| stale("SHOP-#{number}") }

    assert_equal 10, prompt.total
  end

  it 'keeps quiet under ten suggestions' do
    (1..9).each { |number| stale("SHOP-#{number}") }

    assert_nil prompt
  end

  it 'keeps quiet when suggestions are under a tenth of what is on display' do
    (1..10).each { |number| stale("SHOP-#{number}") }
    stored = (1..91).map { |number| "Wanted item number #{number}" }
    stored.each_with_index { |summary, index| add("WANT-#{index}", summary: "#{summary} #{'y' * (index % 7)}") }
    LetGo.detect(team_id: @team.id)
    MuseumItem.where(team_id: @team.id, let_go_group: 'dupes').update(let_go_group: nil, let_go_pair_key: nil)

    assert_nil LetGoPrompt.call(team: @team.refresh)
  end

  it 'counts a pair as one' do
    (1..9).each { |number| stale("SHOP-#{number}") }
    add('SHOP-20', summary: 'Guests can check out without an account')
    add('SHOP-21', summary: 'Guests can check out without an account')

    assert_equal 10, prompt.total
  end

  it 'stays quiet for thirty days after Not now' do
    (1..10).each { |number| stale("SHOP-#{number}") }

    LetGoPrompt.snooze(team: @team, actor: @person.actor)

    assert_nil prompt
    Timecop.freeze(Time.now + (29 * 24 * 60 * 60)) { assert_nil prompt }
    Timecop.freeze(Time.now + (31 * 24 * 60 * 60)) { assert_equal 10, prompt.total }
  end

  it 'records Not now' do
    LetGoPrompt.snooze(team: @team, actor: @person.actor)

    assert_equal ['let_go_snoozed'], Event.where(entity_id: @team.id).select_map(:action)
  end

  it 'breaks the total down by group, folding the small ones together' do
    counts = { 'stale' => 64, 'dupes' => 9, 'repro' => 11, 'vague' => 12, 'covered' => 7 }

    expected = '64 untouched for over a year, 9 duplicates, 11 bugs nobody could reproduce, ' \
               'and 19 that are too vague or already covered'

    assert_equal expected, LetGoPrompt::Prompt.new(counts: counts).breakdown
  end

  it 'names only the groups with something in them, in the singular where it fits' do
    two = LetGoPrompt::Prompt.new(counts: { 'dupes' => 1, 'repro' => 1 })

    assert_equal '1 duplicate and 1 bug nobody could reproduce', two.breakdown
    assert_equal '1 that is too vague or already covered', LetGoPrompt::Prompt.new(counts: { 'vague' => 1 }).breakdown
  end
end
