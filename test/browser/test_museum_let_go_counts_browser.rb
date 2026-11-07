# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

describe 'Ticket Museum let go counts (browser)' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
    recent = (Date.today - 30).strftime('%d/%b/%y 10:15 AM')
    old = (10..16).map { |n| { key: "OLD-#{n}", id: n.to_s, summary: "Old ticket about thing #{n}" } }
    twins = [{ key: 'NEW-1', id: '1', summary: 'Trailing whitespace breaks the search', created: recent },
             { key: 'NEW-2', id: '2', summary: 'Trailing whitespace breaks the search', created: recent }]
    import_jira_csv(JiraExport.csv(*old, *twins))
    let_the_curator_look
    use_browser!
    visit "/teams/#{@team.id}/museum/let-go"
  end

  def group(id)
    %([data-test-id="let-go-group"][data-group="#{id}"])
  end

  def row(key)
    %([data-test-id="let-go-row"][data-key="#{key}"])
  end

  def assert_counts(selected:, going:, staying:)
    assert_selector %(#{group('stale')} [data-test-id="let-go-selected"][data-count="#{selected}"])
    assert_selector %([data-test-id="let-go-going"][data-count="#{going}"])
    assert_selector %([data-test-id="let-go-staying"][data-count="#{staying}"])
    assert_selector %([data-test-id="let-go-submit"][data-count="#{going}"])
  end

  it 'counts as rows are unticked and ticked again, marking the group as partly chosen' do
    assert_counts(selected: 7, going: 8, staying: 1)

    find("#{row('OLD-10')} input[type='checkbox']").click

    assert_counts(selected: 6, going: 7, staying: 2)
    assert evaluate_script(%(document.querySelector('#{group('stale')} [data-test-id="let-go-group-tick"]').indeterminate))

    find("#{row('OLD-10')} input[type='checkbox']").click

    assert_counts(selected: 7, going: 8, staying: 1)
    refute evaluate_script(%(document.querySelector('#{group('stale')} [data-test-id="let-go-group-tick"]').indeterminate))
  end

  it 'marks a partly chosen group with one glyph' do
    find("#{row('OLD-10')} input[type='checkbox']").click

    tick = "#{group('stale')} [data-test-id=\"let-go-group-tick\"]"
    content = evaluate_script(%(getComputedStyle(document.querySelector('#{tick}'), '::after').content))

    assert_equal 3, content.length, "expected one glyph in quotes, got #{content}"
  end

  it 'counts the rest of a group with its box, and all of it once shown' do
    find('[data-test-id="let-go-rest"]').click

    assert_counts(selected: 5, going: 6, staying: 3)

    find('[data-test-id="let-go-show-all"]').click

    assert_selector '[data-test-id="let-go-row"]', count: 7
    assert_counts(selected: 5, going: 6, staying: 3)
  end

  it 'takes a kept row out of the group, and puts it back' do
    within(row('OLD-10')) { find('[data-test-id="let-go-keep"]').click }

    assert_counts(selected: 6, going: 7, staying: 2)

    within(row('OLD-10')) { find('[data-test-id="let-go-kept"]').click }

    assert_counts(selected: 7, going: 8, staying: 1)
  end

  it 'ticks and unticks a whole group, rest included, and turns the button off at nothing' do
    find("#{group('stale')} [data-test-id='let-go-group-tick']").click

    assert_counts(selected: 0, going: 1, staying: 8)
    assert_no_selector "#{row('OLD-10')} input[type='checkbox']:checked"

    find("#{group('dupes')} [data-test-id='let-go-group-tick']").click

    assert_selector '[data-test-id="let-go-submit"]:disabled'

    find("#{group('dupes')} [data-test-id='let-go-group-tick']").click
    find("#{group('stale')} [data-test-id='let-go-group-tick']").click

    assert_counts(selected: 7, going: 8, staying: 1)
    assert_selector '[data-test-id="let-go-rest"]:checked'
    assert_selector '[data-test-id="let-go-submit"]:not(:disabled)'
  end

  it 'lets the page be sent with nothing going when a pair is to be kept' do
    find("#{group('stale')} [data-test-id='let-go-group-tick']").click
    find('[data-test-id="let-go-keep-both"]').click

    assert_counts(selected: 0, going: 0, staying: 9)
    assert_selector '[data-test-id="let-go-submit"]:not(:disabled)'
  end

  it 'folds a group away and still counts what is in it' do
    find("#{group('stale')} [data-test-id='let-go-fold']").click

    assert_no_selector row('OLD-10')
    assert_counts(selected: 7, going: 8, staying: 1)

    find("#{group('stale')} [data-test-id='let-go-fold']").click

    assert_selector row('OLD-10')
  end
end
