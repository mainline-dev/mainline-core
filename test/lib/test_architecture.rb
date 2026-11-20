# frozen_string_literal: true

ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest'
require 'minitest/global_expectations/autorun'
require 'archunit'

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
end
