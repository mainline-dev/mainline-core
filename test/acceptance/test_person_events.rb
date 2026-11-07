# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'

# Core announces when a person is deleted, before their row goes, so code that
# keeps its own records per person can remove them.
describe 'Person events' do
  include MainlineDSL

  before do
    @heard = []
    @subscription = CoreEvents.subscribe(:person_deleted) { |payload|
      @heard << [payload, Person[payload[:person_id]].nil?]
    }
    setup_team
    @alice = add_person(name: 'Alice')
  end

  after { CoreEvents.unsubscribe(@subscription) }

  it 'announces a deleted account while the person still exists' do
    DeletePerson.call(person: @alice)

    assert_equal [[{ person_id: @alice.id }, false]], @heard
  end

  it 'announces a person removed with the last team they belonged to' do
    DeleteTeam.call(team: @team)

    assert_includes @heard, [{ person_id: @alice.id }, false]
  end
end

describe 'Person events - signup' do
  include MainlineDSL

  before do
    @heard = []
    @subscription = CoreEvents.subscribe(:person_signed_up) { |payload| @heard << payload }
  end

  after { CoreEvents.unsubscribe(@subscription) }

  def signups
    @heard.map { |e| [e[:person_id], e[:provider]] }
  end

  it 'announces an email signup' do
    driver.submit_email_signup(name: 'Bea', email: 'bea@acme.co', password: 'longpassword12')

    person = Person.find_by_email('bea@acme.co')

    assert_equal [[person.id, 'email']], signups
  end

  it 'announces a sign-in provider signup' do
    driver.oauth_signup(provider: 'github', uid: 'gh-bea', email: 'bea@acme.co', name: 'Bea')

    person = Person.find_by_email('bea@acme.co')

    assert_equal [[person.id, 'github']], signups
  end

  it "hands over the visitor's session" do
    driver.submit_email_signup(name: 'Bea', email: 'bea@acme.co', password: 'longpassword12')

    assert_respond_to @heard.first[:session], :delete
  end
end
