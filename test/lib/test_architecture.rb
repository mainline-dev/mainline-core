# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require 'archunit'
require 'prism'

# Reads one test case file for the steps it does itself: each call on a
# driver or on the browser page, and each raw HTTP or browser verb. "refresh"
# is left out of the verbs because the DSL has a step of that name.
class CallsPastTheDsl < Prism::Visitor
  BEHIND = %i[driver page].freeze
  VERBS = %i[
    get post put patch delete head header follow_redirect! last_request last_response
    visit go_back current_path current_url find find_all all first within within_frame
    click_on click_button click_link fill_in choose check uncheck select attach_file send_keys accept_confirm
    evaluate_script execute_script using_wait_time has_css? has_no_css? has_selector? has_no_selector? has_text? has_content?
    assert_selector assert_no_selector assert_text assert_no_text assert_current_path assert_no_current_path
  ].freeze

  def self.in(path)
    new.tap { |reader| Prism.parse_file(path).value.accept(reader) }.calls
  end

  attr_reader :calls

  def initialize
    super
    @calls = []
    @called_on = []
  end

  def visit_call_node(node)
    if behind?(node.receiver)
      @called_on << node.receiver.location.start_offset
      @calls << "#{node.receiver.name}.#{node.name}"
    elsif node.receiver.nil? && (VERBS.include?(node.name) || handed_on?(node))
      @calls << node.name.to_s
    end
    super
  end

  private

  def behind?(node)
    node.is_a?(Prism::CallNode) && node.receiver.nil? && BEHIND.include?(node.name)
  end

  # A driver or the page given to something else, with nothing called on it here.
  def handed_on?(node)
    BEHIND.include?(node.name) && !@called_on.include?(node.location.start_offset)
  end
end

# The acceptance tests are built in four tiers. Test cases say what a person
# does, in the words the team uses. The DSL turns those words into steps.
# Drivers carry the steps out against the system. The system knows none of
# it. Each tier reaches only the one below, so a change to a page or a table
# is made in one driver and no test case has to be rewritten.
#
# These read the source for which file names which, and fail when a tier
# reaches past its neighbour. They see a class or a file being named. They do
# not see which methods are called.
describe 'The four tiers of the acceptance tests' do
  def root
    File.expand_path('../..', __dir__)
  end

  # "documents" are the files beside the DSL that write what a person would
  # bring in: an export, an import file, a folder of pages.
  def tiers
    ArchUnit.project_layers(root)
      .layer('cases').defined_by(%r{\Atest/(acceptance|browser)/.*\.rb\z})
      .layer('dsl').defined_by('test/dsl/*_dsl.rb')
      .layer('drivers').defined_by(%r{\Atest/dsl/(drivers/.*|[^/]*_driver)\.rb\z})
      .layer('documents').defined_by(%r{\Atest/dsl/(?!.*_(dsl|driver)\.rb\z)[^/]+\.rb\z})
      .layer('helpers').defined_by('test/*_helper.rb')
      .layer('system').defined_by(%r{\A(lib|models|routes)/.*\.rb\z|\A[^/]+\.rb\z})
  end

  # Each breach as the file that reaches and the file it names.
  def breaches(rule)
    rule.check(ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants)).map do |breach|
      next ArchUnit.format_violations([breach], color: false) unless breach.respond_to?(:dependency)

      "#{breach.dependency.source_label} -> #{breach.dependency.target_label}"
    end
  end

  def assert_kept(rule)
    assert_empty breaches(rule)
  end

  it 'lets the DSL reach the system only through a driver' do
    rule = tiers.where_layer('dsl').may_only_depend_on_layers('drivers', 'documents')

    assert_kept rule
  end

  it 'keeps the system unaware of its tests' do
    rule = tiers.where_layer('system').may_not_depend_on_layers('cases', 'dsl', 'drivers', 'documents', 'helpers')

    assert_kept rule
  end

  # Test cases written before these rules reach past the DSL in places.
  # test/tier_breaches.txt records each one, a line apiece. The list is debt:
  # it gets shorter and never longer.
  describe 'test cases, which reach the system only through the DSL' do
    def found
      breaches(tiers.where_layer('cases').may_only_depend_on_layers('dsl', 'documents', 'helpers'))
    end

    def recorded
      File.readlines(File.join(root, 'test/tier_breaches.txt'), chomp: true)
        .map { |line| line.sub(/\s*#.*\z/, '') }.reject(&:empty?)
    end

    it 'reach past it nowhere new' do
      added = found - recorded

      assert_empty added, "A test case names the system or a driver itself. Give the DSL a step for it:\n#{added.join("\n")}"
    end

    it 'leave no line recorded for a breach that has been put right' do
      gone = recorded - found

      assert_empty gone, "Put right. Delete from test/tier_breaches.txt:\n#{gone.join("\n")}"
    end
  end

  # Naming a class is one way past the DSL. Doing a step by hand is the
  # other: a test case that calls a driver, the page or a raw verb itself.
  # test/tier_calls.txt records each such call and how often a test makes it.
  describe 'test cases, which do nothing by hand that the DSL has no step for' do
    def found
      Dir[File.join(root, 'test/{acceptance,browser}/**/*.rb')].each_with_object({}) do |path, counts|
        file = path.delete_prefix("#{root}/")
        CallsPastTheDsl.in(path).tally.each { |call, times| counts["#{file}: #{call}"] = times }
      end
    end

    def recorded
      File.readlines(File.join(root, 'test/tier_calls.txt'), chomp: true)
        .map { |line| line.sub(/\s*#.*\z/, '') }.reject(&:empty?)
        .to_h { |line| [line[/\A(.+) \d+\z/, 1], line[/\d+\z/].to_i] }
    end

    it 'make no call past it that is new, and none more often' do
      known = recorded
      grown = found.select { |call, times| times > known.fetch(call, 0) }.map { |call, times| "#{call} #{times}" }

      assert_empty grown, "A test case does a step itself. Give the DSL a step for it:\n#{grown.join("\n")}\n(#{grown.size} in all)"
    end

    it 'leave no count recorded above what a test still makes' do
      made = found
      paid = recorded.select { |call, times| times > made.fetch(call, 0) }.map { |call, _| "#{call} #{made.fetch(call, 0)}" }

      assert_empty paid, "Paid off. In test/tier_calls.txt these now read, and any at 0 goes:\n#{paid.join("\n")}\n(#{paid.size} in all)"
    end
  end
end
