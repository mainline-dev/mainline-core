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
end
