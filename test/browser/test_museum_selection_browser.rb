# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

describe 'Ticket Museum selection (browser)' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
    import_jira_csv(JiraExport.csv(
      { key: 'SHOP-1', id: '1', summary: 'Guest checkout' },
      { key: 'SHOP-2', id: '2', summary: 'Gift cards at the till' },
      { key: 'SHOP-3', id: '3', type: 'Bug', summary: 'Refunds fail' },
      { key: 'SHOP-4', id: '4', type: 'Sub-task', parent: '1', summary: 'Store the guest email' }
    ))
  end

  def tick(key)
    find(%([data-test-id="museum-select"][data-key="#{key}"])).click
  end

  def row(key)
    %([data-test-id="museum-item"][data-key="#{key}"])
  end

  it 'takes an exhibit out of the set even when there is nowhere to promote to yet' do
    use_browser!
    visit "/teams/#{@team.id}/museum"
    tick('SHOP-1')
    tick('SHOP-2')
    find('[data-test-id="museum-selection-together"]').click

    assert_selector '[data-test-id="museum-no-tasks"]'
    find('[data-test-id="museum-together-card"][data-key="SHOP-2"] [data-test-id="museum-together-remove"]').click

    assert_selector '[data-test-id="museum-together-card"]', count: 1
    assert_no_selector '[data-test-id="museum-together-remove"]'
  end

  it 'adds what is ticked to a story found by searching' do
    create_map(name: 'Shop')
    task = create_task('Pay', under_activity: create_activity('Checkout', for_personas: [create_persona('Shopper')]))
    import_jira_csv(JiraExport.csv({ key: 'SHOP-9', id: '9', summary: 'A ticket to promote' }))
    promote_museum_item('SHOP-9', title: 'Buy without an account', task: task)
    use_browser!
    visit "/teams/#{@team.id}/museum"
    tick('SHOP-1')
    tick('SHOP-2')

    find('[data-test-id="museum-selection-add"]').click

    assert_selector '[data-test-id="museum-add-form"]'
    find('[data-test-id="museum-story-search"]').set('account')
    find('[data-test-id="museum-story-hit"]').click
    find('[data-test-id="museum-add-submit"]').click

    assert_selector '[data-test-id="museum-toast-undo"]'
    assert_equal 3, story_exhibits('Buy without an account')
    assert_no_selector '[data-test-id="museum-selection"]'
  end

  it 'promotes what is ticked as one story, leaving out any taken off the page' do
    create_map(name: 'Shop')
    create_task('Pay', under_activity: create_activity('Checkout', for_personas: [create_persona('Shopper')]))
    use_browser!
    visit "/teams/#{@team.id}/museum"
    tick('SHOP-1')
    tick('SHOP-2')
    tick('SHOP-3')

    find('[data-test-id="museum-selection-together"]').click

    assert_selector '[data-test-id="museum-together-card"]', count: 3
    assert_selector '[data-test-id="museum-leaving"] [data-leaving]', count: 4

    find('[data-test-id="museum-together-card"][data-key="SHOP-3"] [data-test-id="museum-together-remove"]').click

    assert_selector '[data-test-id="museum-together-card"]', count: 2
    assert_selector '[data-test-id="museum-leaving"] [data-leaving]', count: 3
    assert_selector '[data-test-id="museum-promote-submit"][data-count="2"]'

    find('[data-test-id="museum-promote-form"] input[name="title"]').set('Guests can check out without an account')
    find('[data-test-id="museum-promote-submit"]').click

    assert_selector '[data-test-id="museum-toast-undo"]'
    assert_equal 2, story_exhibits('Guests can check out without an account')
    assert_nil museum_item('SHOP-3').story_id
    assert_no_selector '[data-test-id="museum-selection"]'
  end

  it 'keeps ticked exhibits through filters and visits, then stores them together' do
    use_browser!
    visit "/teams/#{@team.id}/museum"

    tick('SHOP-1')

    assert_selector '[data-test-id="museum-selection"][data-count="2"]'

    find('[data-test-id="museum-filter-type"] option[value="Bug"]').select_option

    assert_no_selector row('SHOP-1')
    tick('SHOP-3')

    assert_selector '[data-test-id="museum-selection"][data-count="3"]'

    visit "/teams/#{@team.id}/museum"

    assert_selector '[data-test-id="museum-selection"][data-count="3"]'
    find('[data-test-id="museum-selection-store"]').click

    assert_selector row('SHOP-2')
    assert_no_selector row('SHOP-1')
    assert_no_selector row('SHOP-3')
    assert_no_selector '[data-test-id="museum-selection"]'
  end

  it 'clears the selection' do
    use_browser!
    visit "/teams/#{@team.id}/museum"
    tick('SHOP-2')

    find('[data-test-id="museum-selection-clear"]').click

    assert_no_selector '[data-test-id="museum-selection"]'
    refute_predicate find(%([data-test-id="museum-select"][data-key="SHOP-2"])), :checked?
  end
end
