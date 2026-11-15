# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

# Once a team's first import is 90 days old, the museum says how much of the
# backlog it brought in was never pulled onto the map.
describe 'How much of the backlog was never pulled' do
  include MainlineDSL

  before do
    setup_team
    @alice = add_person(name: 'Alice')
    create_map(name: 'Shop')
    @task = create_task('Pay', under_activity: create_activity('Checkout', for_personas: [create_persona('Shopper')]))
    import_jira_csv(JiraExport.csv(
      { key: 'SHOP-1', id: '1', summary: 'Pay by card' },
      { key: 'SHOP-2', id: '2', summary: 'Pay by invoice' },
      { key: 'SHOP-3', id: '3', summary: 'Gift cards' },
      { key: 'SHOP-4', id: '4', summary: 'Store credit' }
    ))
    promote_museum_item('SHOP-1', title: 'Shoppers can pay by card', task: @task)
  end

  after do
    back_to_today
  end

  it 'says how much was never pulled once the first import is 90 days old' do
    days_pass(90)
    login_as(@alice)

    visit_museum

    assert_equal 75, never_pulled_percent
  end

  it 'says nothing while the first import is younger than 90 days' do
    days_pass(89)
    login_as(@alice)

    visit_museum

    assert_nil never_pulled_percent
  end
end
