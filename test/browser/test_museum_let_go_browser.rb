# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

describe 'Ticket Museum let go review (browser)' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
    import_jira_csv(JiraExport.csv(*(10..16).map { |n| { key: "OLD-#{n}", id: n.to_s, summary: "Old ticket about thing #{n}" } }))
    let_the_curator_look
    use_browser!
    visit "/teams/#{@team.id}/museum/let-go"
  end

  def row(key)
    %([data-test-id="let-go-row"][data-key="#{key}"])
  end

  it 'keeps a row where it is, and takes that back' do
    within(row('OLD-10')) { find('[data-test-id="let-go-keep"]').click }

    assert_selector "#{row('OLD-10')} [data-test-id='let-go-kept']"
    assert_no_selector "#{row('OLD-10')} input[type='checkbox']"

    within(row('OLD-10')) { find('[data-test-id="let-go-kept"]').click }

    assert_selector "#{row('OLD-10')} input[type='checkbox']:checked"
  end

  it 'shows the rest of a group ticked, and sends all of it to storage' do
    find('[data-test-id="let-go-show-all"]').click

    assert_selector '[data-test-id="let-go-row"]', count: 7
    assert_no_selector '[data-test-id="let-go-rest"]'

    find('[data-test-id="let-go-submit"]').click

    assert_selector '[data-test-id="let-go-done"]'
    assert_equal 7, MuseumItem.where(team_id: @team.id).exclude(discarded_at: nil).count
  end

  it 'shows the rest of a group unticked if the rest was unticked' do
    find('[data-test-id="let-go-rest"]').click
    find('[data-test-id="let-go-show-all"]').click

    assert_selector '[data-test-id="let-go-row"]', count: 7
    assert_selector '[data-test-id="let-go-row"] input[type="checkbox"]:checked', count: 5
  end

  it 'lets a row go without taking the one that slid up after a keep' do
    within(row('OLD-10')) { find('[data-test-id="let-go-keep"]').click }

    assert_selector "#{row('OLD-10')} [data-test-id='let-go-kept']"

    find('[data-test-id="let-go-rest"]').click
    find('[data-test-id="let-go-submit"]').click

    assert_selector '[data-test-id="let-go-done"]'
    assert_equal %w[OLD-11 OLD-12 OLD-13 OLD-14],
      MuseumItem.where(team_id: @team.id).exclude(discarded_at: nil).select_order_map(:source_key)
  end
end
