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

  def assert_kept(rule)
    found = rule.check(ArchUnit::CheckOptions.new(dependency_analysis: :imports_and_constants))

    assert_empty(found, -> { ArchUnit.format_violations(found, color: false) })
  end

  it 'lets the DSL reach the system only through a driver' do
    rule = tiers.where_layer('dsl').may_only_depend_on_layers('drivers', 'documents')

    assert_kept rule
  end

  it 'keeps the system unaware of its tests' do
    rule = tiers.where_layer('system').may_not_depend_on_layers('cases', 'dsl', 'drivers', 'documents', 'helpers')

    assert_kept rule
  end
end
