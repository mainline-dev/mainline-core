# frozen_string_literal: true

require_relative '../web_spec_helper'
require_relative '../dsl/mainline_dsl'
require_relative '../dsl/jira_export'

# An exhibit's row has a Promote button. On a closed exhibit it opens the
# exhibit ready to type. On an open one it does what the button at the foot
# of the form does, so a person who has read the exhibit can promote it from
# where they are.
describe 'Promote on an open exhibit (browser)' do
  include MainlineDSL

  before do
    setup_team
    add_person(name: 'Alice')
    create_map(name: 'Shop')
    create_task('Pay', under_activity: create_activity('Checkout', for_personas: [create_persona('Shopper')]))
    import_jira_csv(JiraExport.csv({ key: 'SHOP-22', id: '22', summary: 'Filter by price' }))
    use_browser!
    open_museum
    open_exhibit_to_promote('SHOP-22')
  end

  it 'promotes the exhibit from the button on its row' do
    write_story_title('Shoppers can filter results by price')

    press_row_promote('SHOP-22')

    assert_predicate self, :promote_undo_offered?
    assert exhibit_gone?('SHOP-22')
  end

  it 'promotes nothing while the story has no title, as the form itself would not' do
    write_story_title('')

    press_row_promote('SHOP-22')

    refute_predicate self, :promote_undo_offered?
    assert exhibit_listed?('SHOP-22')
  end
end
