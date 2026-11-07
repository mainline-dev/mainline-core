# frozen_string_literal: true

require 'csv'

# Builds a Jira CSV export the way Jira writes one: one row per issue, with
# the Labels and Comment headers repeated once per value. Each issue is a
# hash of overrides on a plain open story.
module JiraExport
  HEADERS = [
    'Summary', 'Issue key', 'Issue id', 'Issue Type', 'Status', 'Status Category', 'Resolution',
    'Assignee', 'Reporter', 'Created', 'Updated', 'Labels', 'Labels', 'Description', 'Comment', 'Comment',
    'Parent', 'Inward issue link (Blocks)', 'Outward issue link (Relates)'
  ].freeze

  ISSUE = {
    summary: 'Search by postcode', key: 'SHOP-1', id: '10001', type: 'Story', status: 'To Do',
    category: 'To Do', resolution: '', assignee: 'Alice Smith', reporter: 'Bob Jones',
    created: '02/Jan/24 10:15 AM', updated: '', labels: [], description: 'As a shopper', comments: [],
    parent: '', blocked_by: '', relates_to: ''
  }.freeze

  def self.csv(*issues, headers: HEADERS, col_sep: ',')
    CSV.generate(col_sep: col_sep) { |csv|
      csv << headers
      issues.each { |issue| csv << row(issue) }
    }
  end

  def self.row(issue)
    i = ISSUE.merge(issue)
    labels = (i[:labels] + ['', ''])[0, 2]
    comments = (i[:comments] + ['', ''])[0, 2]
    [i[:summary], i[:key], i[:id], i[:type], i[:status], i[:category], i[:resolution],
     i[:assignee], i[:reporter], i[:created], i[:updated], *labels, i[:description], *comments,
     i[:parent], i[:blocked_by], i[:relates_to]]
  end
end
