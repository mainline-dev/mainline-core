# frozen_string_literal: true

require_relative '../model_spec_helper'

# The app connects as mainline_app. A function the owner adds later is not
# the app's to run until a migration grants it on purpose, so a privileged
# function can't become callable by accident.
describe 'Database function privileges' do
  before do
    @owner = Sequel.connect(ENV.fetch('TEST_DATABASE_URL'))
    @function = "added_later_#{SecureRandom.hex(4)}"
    @owner.run("CREATE FUNCTION #{@function}() RETURNS integer LANGUAGE sql SECURITY DEFINER AS 'SELECT 1'")
  end

  after do
    @owner.run("DROP FUNCTION IF EXISTS #{@function}()")
    @owner.disconnect
  end

  it 'does not let the app run a function the owner adds later' do
    error = assert_raises(Sequel::DatabaseError) { DB.transaction(savepoint: true) { DB["SELECT #{@function}()"].get } }

    assert_match(/permission denied/, error.message)
  end

  it 'lets the owner grant the app a function on purpose' do
    @owner.run("GRANT EXECUTE ON FUNCTION #{@function}() TO mainline_app")

    assert_equal 1, DB["SELECT #{@function}()"].get
  end
end
