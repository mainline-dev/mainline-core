# frozen_string_literal: true

require 'csv'
require 'date'

# Reads a Jira CSV export into items the Ticket Museum can hold, without
# touching the database. Finished issues are counted and left out. No person
# comes in: person columns are never read, comment authors are dropped, and
# @mentions and email addresses are removed. Every cell is cleaned of control
# characters and Windows line endings, and keys are upper-cased. Rows the
# museum cannot hold come back as problems, with the reason and the row as it
# was, so they can be fixed and imported again.
module JiraCsv
  Read = Struct.new(:success?, :errors, :missing_columns, :header, :items, :problems, :finished, keyword_init: true)

  MAX_BYTES = 10 * 1024 * 1024
  MAX_ISSUES_PER_FILE = 1000
  DELIMITERS = [',', ';', "\t"].freeze
  REQUIRED_HEADERS = ['Issue key', 'Summary', 'Issue Type'].freeze
  # The stories.csv in a Mainline export has no issue key column, so that
  # Jira cannot overwrite an issue with it. Its rows are known by Mainline ID.
  MAINLINE_ID_HEADER = 'Mainline ID'
  MAINLINE_ID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  LINK_HEADER = /\A(Inward|Outward) issue link \((.+)\)\z/
  ISSUE_KEY = /\A[A-Z][A-Z0-9_]*-\d+\z/
  BYTE_ORDER_MARK = "\uFEFF"
  MENTION = / ?\[~[^\]]*\]/
  MAILTO = / ?\[(?:[^\]|]*\|)?mailto:[^\]]*\]/
  EMAIL = / ?[\w.%+-]+@[\w-]+(?:\.[\w-]+)*\.[A-Za-z]{2,}\b/
  CONTROL = /[\x00-\x08\x0B-\x1F\x7F]/
  PARENT_COLUMNS = ['Parent', 'Parent id', 'Custom field (Epic Link)'].freeze
  # Jira's own formats, then what a spreadsheet writes when it re-saves one.
  DATE_FORMATS = [
    '%d/%b/%y %I:%M %p', '%d/%b/%Y %I:%M %p', '%d/%b/%y %H:%M', '%d/%b/%Y %H:%M',
    '%Y-%m-%d %H:%M', '%Y-%m-%d %H:%M:%S', '%Y-%m-%dT%H:%M:%S'
  ].freeze
  NUMERIC_DATE = %r{\A\d{1,2}/(\d{1,2})/\d{4} }
  # A cell a spreadsheet would run as a formula (a tab or carriage return in
  # front does not stop it), and the same cell once guarded with an apostrophe.
  FORMULA = /\A[\t\r=+\-@]/
  GUARDED_FORMULA = /\A'(?=[\t\r=+\-@])/
  PROBLEMS = {
    'no_key'           => 'No issue key',
    'not_a_key'        => 'The issue key is not a Jira key like ABC-123',
    'key_too_long'     => 'The issue key is over 50 characters',
    'no_type'          => 'No issue type',
    'type_too_long'    => 'The issue type is over 50 characters',
    'no_summary'       => 'No summary',
    'summary_too_long' => 'The summary is over 255 characters'
  }.freeze

  def self.read(csv)
    return failure('This file is over 10 MB') if csv.bytesize > MAX_BYTES

    rows = parse(csv)
    return failure('This file could not be read as CSV') unless rows

    header, *body = rows
    missing = REQUIRED_HEADERS - header.to_a
    missing.delete('Issue key') if header.to_a.include?(MAINLINE_ID_HEADER)
    return missing_columns(missing) unless missing.empty?

    numbered = body.each_with_index.map { |row, index| [row, index + 2] }.reject { |row, _number| row.compact.empty? }
    return failure("This file has #{numbered.size} issues. Export at most 1000 per file.") if numbered.size > MAX_ISSUES_PER_FILE

    export = Export.new(header, numbered)
    Read.new(success?: true, errors: [], missing_columns: [], header: header.map { |cell| cell.to_s.delete("\u0000") },
      items: export.open_items, problems: export.problems, finished: export.finished_count)
  end

  # The rows that could not be read, as a CSV to fix and import again: the
  # problem first, then the file's own columns as they were. Cells a
  # spreadsheet would run as formulas are guarded; reading takes the guard off.
  def self.problems_csv(header:, problems:)
    BYTE_ORDER_MARK + CSV.generate { |csv|
      csv << ['Problem', *header.map { |cell| guard(cell.to_s) }]
      problems.each { |problem|
        problem = problem.to_h.transform_keys(&:to_s)
        csv << [PROBLEMS[problem['reason']], *problem['cells'].map { |cell| guard(cell) }]
      }
    }
  end

  def self.guard(cell)
    return if cell.empty?

    cell.match?(FORMULA) ? "'#{cell}" : cell
  end

  def self.parse(csv)
    text = csv.dup.force_encoding(Encoding::UTF_8).delete_prefix(BYTE_ORDER_MARK)
    CSV.parse(text, col_sep: delimiter(text)) if text.valid_encoding?
  rescue CSV::MalformedCSVError
    nil
  end

  # Whichever of comma, semicolon or tab the header line uses most.
  def self.delimiter(text)
    header = text[/\A[^\n]*/]
    DELIMITERS.max_by { |delimiter| header.count(delimiter) }
  end

  def self.missing_columns(missing)
    Read.new(success?: false, missing_columns: missing,
      errors: ["This is not a Jira CSV export: it has no #{missing.join(' or ')} column. Export from Jira with CSV (all fields)."])
  end

  def self.failure(message)
    Read.new(success?: false, errors: [message], missing_columns: [])
  end
  private_class_method :guard, :parse, :delimiter, :missing_columns, :failure

  # One export file: reads cells by header name, since Jira repeats a header
  # once per label, comment and link.
  class Export
    attr_reader :open_items, :problems, :finished_count

    # rows are [cells, row number in the file] pairs.
    def initialize(header, rows)
      @columns = header.each_index.group_by { |index| header[index] }
      @by_mainline_id = !@columns.key?('Issue key')
      # A Jira export says how far an issue has got in Status Category. A
      # Mainline export has only Status, in the same three words.
      @progress = @columns.key?('Status Category') ? 'Status Category' : 'Status'
      @links = header.each_index.filter_map { |index|
        match = LINK_HEADER.match(header[index])
        [index, match[1].downcase, match[2]] if match
      }
      @keys_by_id = rows.filter_map { |row, _number|
        id = first(row, 'Issue id')
        [id, first(row, 'Issue key')&.upcase] if id
      }.to_h
      @date_formats = DATE_FORMATS + [numeric_date_format(rows.map(&:first))]
      read(rows)
    end

    private

    # Open rows become items, or problems when the museum cannot hold them.
    # A key listed twice keeps its last row.
    def read(rows)
      open = rows.reject { |row, _number| finished?(row) }
      @finished_count = rows.size - open.size
      @problems = []
      @open_items = open.each_with_object({}) { |(row, number), items|
        item = item(row)
        reason = problem(item)
        if reason
          @problems << { row: number, reason: reason, cells: row.map { |cell| cell.to_s.delete("\u0000") } }
        else
          items[item[:source_key]] = item
        end
      }.values
    end

    def key(row)
      @by_mainline_id ? first(row, MAINLINE_ID_HEADER)&.downcase : first(row, 'Issue key')&.upcase
    end

    def item(row)
      {
        source_key:        key(row),
        issue_type:        first(row, 'Issue Type'),
        summary:           without_people(first(row, 'Summary').to_s).gsub(/\s+/, ' '),
        description:       without_people(first(row, 'Description').to_s),
        in_progress:       first(row, @progress) == 'In Progress',
        parent_key:        parent_key(PARENT_COLUMNS.lazy.filter_map { |column| first(row, column) }.first),
        labels:            cells(row, 'Labels').uniq,
        comments:          cells(row, 'Comment').map { |comment| comment(comment) },
        links:             links(row),
        source_created_at: time(first(row, 'Created'))&.iso8601,
        source_updated_at: time(first(row, 'Updated'))&.iso8601
      }
    end

    # Why the museum's columns cannot hold an item, if they cannot.
    def problem(item)
      key = item[:source_key]
      return 'no_key' unless key
      return 'not_a_key' unless key.match?(@by_mainline_id ? MAINLINE_ID : ISSUE_KEY)
      return 'key_too_long' if key.length > 50

      type_or_summary_problem(item[:issue_type], item[:summary])
    end

    def type_or_summary_problem(type, summary)
      if type.nil? then 'no_type'
      elsif type.length > 50 then 'type_too_long'
      elsif summary.empty? then 'no_summary'
      elsif summary.length > 255 then 'summary_too_long'
      end
    end

    def finished?(row)
      first(row, 'Resolution') || first(row, @progress) == 'Done'
    end

    def parent_key(parent)
      @keys_by_id[parent] || parent&.upcase&.slice(ISSUE_KEY)
    end

    # Jira writes each comment as "date;author;text". Anything else is kept
    # whole, as text without a date.
    def comment(comment)
      at, _author, text = comment.split(';', 3)
      time = time(at)
      return { 'at' => nil, 'text' => without_people(comment) } unless time

      { 'at' => time.iso8601, 'text' => without_people(text.to_s) }
    end

    def links(row)
      @links.filter_map { |index, direction, type|
        key = clean(row[index]).upcase
        { 'type' => type, 'direction' => direction, 'key' => key } if key.match?(ISSUE_KEY)
      }
    end

    def without_people(text)
      text.gsub(MAILTO, '').gsub(MENTION, '').gsub(EMAIL, '').strip
    end

    # Numeric dates are day first, as Jira writes them, unless a date in the
    # file can only be month first.
    def numeric_date_format(rows)
      dates = rows.flat_map { |row| [first(row, 'Created'), first(row, 'Updated')] }
      month_first = dates.any? { |date| date&.match(NUMERIC_DATE)&.then { |match| match[1].to_i > 12 } }
      month_first ? '%m/%d/%Y %H:%M' : '%d/%m/%Y %H:%M'
    end

    def time(value)
      value && @date_formats.lazy.filter_map { |format| parse_time(value, format) }.first
    end

    def parse_time(value, format)
      DateTime.strptime(value, format).to_time.utc
    rescue Date::Error
      nil
    end

    def clean(value)
      value.to_s.gsub(/\r\n?/, "\n").gsub(CONTROL, '').strip.sub(GUARDED_FORMULA, '')
    end

    def cells(row, name)
      @columns.fetch(name, []).map { |index| clean(row[index]) }.reject(&:empty?)
    end

    def first(row, name)
      cells(row, name).first
    end
  end
end
