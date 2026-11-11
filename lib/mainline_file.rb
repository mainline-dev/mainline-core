# frozen_string_literal: true

require 'json'
require 'json_schemer'

# Reads a Mainline import file into items the Ticket Museum can hold, without
# touching the database. The file is stories proposed from a specification or
# research, written by a person or a model outside Mainline. It is checked
# against the published schema first, and a file with anything wrong is
# refused whole: every problem comes back at once, each naming the entry and
# field it is in, so the file can be corrected and sent again.
#
# Each entry becomes an item that says where it came from and carries what it
# suggests (a place on the map and draft scenarios). They stay suggestions:
# nothing is a story until a person promotes the exhibit.
module MainlineFile
  Read = Struct.new(:success?, :errors, :missing_columns, :header, :items, :problems, :finished, :backbone, keyword_init: true)

  SCHEMA_PATH = File.expand_path('../public/schemas/import-1.json', __dir__)
  MAX_BYTES = 10 * 1024 * 1024
  MAX_ENTRIES = 200
  TITLE_LENGTH = 200
  ISSUE_TYPE = 'Proposal'
  KEY = /\A[A-Z][A-Z0-9_]*(-[A-Z0-9_]+)+\z/
  CONTROL = /[\x00-\x08\x0B-\x1F\x7F]/
  BYTE_ORDER_MARK = "\uFEFF"
  # What a schema check calls a problem, in the words the rest of the app uses.
  PROBLEMS = {
    'required' => 'missing', 'maxLength' => 'too_long', 'minLength' => 'empty', 'pattern' => 'wrong_shape',
    'const' => 'wrong_value', 'maxItems' => 'too_many', 'minItems' => 'too_few'
  }.freeze
  SINGULAR = { 'draft_scenarios' => 'scenario', 'activities' => 'activity', 'personas' => 'persona', 'steps' => 'step' }.freeze
  SENTENCES = {
    'missing'     => 'has no %<field>s',
    'too_long'    => 'has a %<field>s that is too long',
    'empty'       => 'has an empty %<field>s',
    'wrong_shape' => 'has a %<field>s in the wrong shape',
    'wrong_value' => 'has a %<field>s Mainline does not know',
    'too_many'    => 'has too many %<field>s',
    'too_few'     => 'has too few %<field>s',
    'unknown'     => 'has a field Mainline does not know: %<field>s',
    'wrong_type'  => 'has a %<field>s of the wrong kind',
    'not_listed'  => 'names a persona the file does not list under personas',
    'repeated'    => 'uses a key another entry already uses',
    'taken'       => 'uses a key that an exhibit from somewhere else already has',
    'not_json'    => 'could not be read as JSON',
    'too_big'     => 'is over 10 MB'
  }.freeze

  def self.read(json)
    return refused([problem('', 'file', 'too_big')]) if json.bytesize > MAX_BYTES

    file = parse(json)
    return refused([problem('', 'file', 'not_json')]) unless file

    problems = schema_problems(file)
    problems = repeated_keys(file) + unlisted_personas(file) if problems.empty?
    return refused(problems) unless problems.empty?

    Read.new(success?: true, errors: [], missing_columns: [], header: [], problems: [], finished: 0,
      items: file['entries'].map { |entry| item(entry) }, backbone: backbone(file))
  end

  # Each problem as a sentence, for the page and for pasting back to a model.
  def self.sentences(problems)
    problems.map do |problem|
      where, _, field = problem['field'].rpartition(' ')
      subject = [subject(problem['entry']), (where unless where.empty?)].compact.join(', ')
      "#{subject} #{format(SENTENCES.fetch(problem['problem'], 'has a problem with its %<field>s'), field: field)}"
    end
  end

  def self.problem(entry, field, kind)
    { 'entry' => entry, 'field' => field, 'problem' => kind }
  end

  def self.subject(entry)
    return 'The file' if entry.empty?

    entry.start_with?('entry ') ? entry.capitalize : "Entry #{entry}"
  end

  def self.refused(problems)
    Read.new(success?: false, errors: sentences(problems), missing_columns: [], problems: problems)
  end

  def self.parse(json)
    text = json.dup.force_encoding(Encoding::UTF_8).delete_prefix(BYTE_ORDER_MARK)
    file = JSON.parse(text) if text.valid_encoding?
    file if file.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def self.schema
    @schema ||= JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
  end

  def self.schema_problems(file)
    schema.validate(file).flat_map { |error| problems_in(error, file) }.uniq
  end

  # One schema error as problems: a missing-fields error is one per field.
  def self.problems_in(error, file)
    path = error['data_pointer'].split('/').drop(1)
    if error['type'] == 'required'
      error.dig('details', 'missing_keys').map { |key| located(path + [key], 'missing', file) }
    elsif error['type'] == 'dependentRequired'
      # The only field needed because another is there: a backbone's map.
      [problem('', 'map', 'missing')]
    elsif error['schema_pointer'].end_with?('/additionalProperties')
      [located(path, 'unknown', file)]
    else
      [located(path, PROBLEMS.fetch(error['type'], 'wrong_type'), file)]
    end
  end

  # Turns a path into the file (entries, 2, draft_scenarios, 1, then) into the
  # entry it is in and a field a person would recognise (scenario 2 then).
  def self.located(path, kind, file)
    return problem('', field(path), kind) unless path.first == 'entries' && path[1]

    index = path[1].to_i
    key = file.dig('entries', index, 'key')
    entry = key.is_a?(String) && key.match?(KEY) ? key : "entry #{index + 1}"
    problem(entry, field(path.drop(2)), kind)
  end

  # draft_scenarios, 1, then reads as "scenario 2 then".
  def self.field(path)
    path.each_with_object([]) { |part, words|
      if part.match?(/\A\d+\z/)
        words[-1] = "#{SINGULAR.fetch(words[-1], words[-1])} #{part.to_i + 1}"
      else
        words << part
      end
    }.join(' ')
  end

  def self.repeated_keys(file)
    keys = file['entries'].map { |entry| entry['key'] }
    keys.select { |key| keys.count(key) > 1 }.uniq.map { |key| problem(key, 'key', 'repeated') }
  end

  # An activity can only be for personas the file lists.
  def self.unlisted_personas(file)
    listed = file['personas'].to_a.map { |name| line(name).downcase }
    file['activities'].to_a.each_with_index.filter_map do |activity, index|
      unlisted = activity['personas'].map { |name| line(name).downcase } - listed
      problem('', "activity #{index + 1} personas", 'not_listed') unless unlisted.empty?
    end
  end

  # The map the file proposes, if it proposes one: its name, personas and
  # activities with their steps. A name said twice is kept once.
  def self.backbone(file)
    return unless file['activities'] || file['personas']

    activities = file['activities'].to_a.map { |activity|
      { 'name' => line(activity['name']), 'personas' => names(activity['personas']), 'steps' => names(activity['steps']) }
    }
    { 'map' => line(file['map']), 'personas' => names(file['personas']),
      'activities' => activities.uniq { |activity| activity['name'].downcase } }
  end

  def self.names(list)
    list.to_a.map { |name| line(name) }.uniq(&:downcase)
  end

  def self.item(entry)
    {
      source_key: entry['key'], issue_type: ISSUE_TYPE, summary: line(entry['title']),
      description: clean(entry['why'].to_s), in_progress: false, parent_key: nil,
      labels: [], comments: [], links: [], source_created_at: nil, source_updated_at: nil,
      origin: line(entry['source']), suggested: suggested(entry)
    }
  end

  def self.suggested(entry)
    place = entry['suggested'] || {}
    scenarios = entry['draft_scenarios'].to_a.map { |scenario| scenario.transform_values { |text| line(text) } }
    { 'activity' => place['activity'] && line(place['activity']), 'step' => place['step'] && line(place['step']),
      'scenarios' => scenarios }
  end

  def self.clean(text)
    text.gsub(/\r\n?/, "\n").gsub(CONTROL, '').strip
  end

  # A title, an origin or a scenario part is one line.
  def self.line(text)
    clean(text).split.join(' ')
  end

  private_class_method :problem, :subject, :refused, :parse, :schema, :schema_problems, :problems_in, :located,
    :field, :repeated_keys, :unlisted_personas, :backbone, :names, :item, :suggested, :clean, :line
end
