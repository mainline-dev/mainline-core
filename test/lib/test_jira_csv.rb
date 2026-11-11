# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/jira_csv'
require_relative '../dsl/jira_export'

describe JiraCsv do
  cover 'JiraCsv*'

  def problems_of(csv)
    read = JiraCsv.read(csv)
    JiraCsv.problems_csv(header: read.header, problems: read.problems)
  end

  it 'writes the rows it could not read back out, with the problem first and the columns as they were' do
    csv = problems_of(JiraExport.csv({ key: 'SHOP-1' }, { key: 'SHOP-2', summary: '' }, { key: 'n/a' }))
    header, *rows = CSV.parse(csv.delete_prefix(JiraCsv::BYTE_ORDER_MARK))

    assert_equal ['Problem', *JiraExport::HEADERS], header
    assert_equal [%w[SHOP-2 n/a], 2], [rows.map { |row| row[2] }, rows.size]
    assert(rows.all? { |row| !row[0].empty? })
  end

  it 'reads a fixed problems file back in' do
    csv = problems_of(JiraExport.csv({ key: 'SHOP-2', summary: '' }))
    read = JiraCsv.read(csv.sub(/^No summary,,/, 'No summary,Fixed summary,'))
    keys_and_summaries = read.items.map { |item| item.values_at(:source_key, :summary) }

    assert_equal [['SHOP-2', 'Fixed summary']], keys_and_summaries
    assert_empty read.problems
  end

  it 'keeps spreadsheets from running cells as formulas, and reads them back as written' do
    csv = problems_of(JiraExport.csv({ key: 'SHOP-2', summary: '', description: '=HYPERLINK("http://evil")' }))
    _header, row = CSV.parse(csv.delete_prefix(JiraCsv::BYTE_ORDER_MARK))

    assert_equal %('=HYPERLINK("http://evil")), row[JiraExport::HEADERS.index('Description') + 1]

    fixed = csv.sub(/^No summary,,/, 'No summary,Fixed,')

    assert_equal '=HYPERLINK("http://evil")', JiraCsv.read(fixed).items.first[:description]
  end
  it 'guards a header cell a spreadsheet would run as a formula' do
    headers = JiraExport::HEADERS + ['=HYPERLINK("http://evil")']
    csv = problems_of(JiraExport.csv({ key: 'SHOP-2', summary: '' }, headers: headers))
    header, = CSV.parse(csv.delete_prefix(JiraCsv::BYTE_ORDER_MARK))

    assert_equal %('=HYPERLINK("http://evil")), header.last
  end

  it 'guards a cell that hides its formula behind a tab or a carriage return' do
    csv = problems_of(JiraExport.csv({ key: 'SHOP-2', summary: '', description: "\t=1+1", labels: ["\r@SUM(1)"] }))
    _header, row = CSV.parse(csv.delete_prefix(JiraCsv::BYTE_ORDER_MARK))

    assert_equal %('\t=1+1), row[JiraExport::HEADERS.index('Description') + 1]
    assert_equal %('\r@SUM(1)), row[JiraExport::HEADERS.index('Labels') + 1]
  end

  describe 'a stories.csv from a Mainline export, which has no issue key column' do
    def exported(*rows)
      CSV.generate { |csv|
        csv << ['Summary', 'Issue Type', 'Description', 'Status', 'Labels', 'Labels', 'Mainline ID', 'Original Jira Key']
        rows.each { |row| csv << row }
      }
    end

    it 'takes each row by its Mainline ID' do
      id = '0df61399-a739-4c09-8a9d-7630be0236bb'
      read = JiraCsv.read(exported(['Guests can check out', 'Story', 'Scenario: A guest pays', 'To Do', 'Purchase', 'Checkout', id,
                                    'SHOP-7']))

      assert_predicate read, :success?
      assert_equal([[id, 'Guests can check out', 'Scenario: A guest pays', %w[Purchase Checkout]]],
        read.items.map { |item| item.values_at(:source_key, :summary, :description, :labels) })
    end

    it 'turns away a row whose Mainline ID is not one' do
      read = JiraCsv.read(exported(['Guests can check out', 'Story', '', 'To Do', '', '', 'not-an-id', '']))

      assert_equal(['not_a_key'], read.problems.map { |problem| problem[:reason] })
    end

    it 'takes how far a row has got from Status, there being no status category' do
      read = JiraCsv.read(exported(
        ['Planned', 'Story', '', 'To Do', '', '', '11111111-1111-4111-8111-111111111111', ''],
        ['Started', 'Story', '', 'In Progress', '', '', '22222222-2222-4222-8222-222222222222', ''],
        ['Released', 'Story', '', 'Done', '', '', '33333333-3333-4333-8333-333333333333', '']
      ))

      assert_equal 1, read.finished
      assert_equal({ 'Planned' => false, 'Started' => true }, read.items.to_h { |item| item.values_at(:summary, :in_progress) })
    end

    it 'still asks for an issue key when a file has neither' do
      read = JiraCsv.read(CSV.generate { |csv| csv << ['Summary', 'Issue Type'] << %w[Something Story] })

      assert_equal ['Issue key'], read.missing_columns
    end
  end
end
