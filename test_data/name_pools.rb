# frozen_string_literal: true

module NamePools
  PEOPLE = [
    'Aisha Patel',
    'Ben Torres',
    'Carlos Reyes',
    'Dana Kim',
    'Eli Okafor',
    'Fatima Shah',
    'Grace Liu',
    'Henrik Berg',
    'Ines Moreau',
    'James Obi',
    'Kenji Sato',
    'Lena Vogt',
    'Marco Diaz',
    'Nina Gupta',
    'Oscar Holm',
    'Priya Nair',
    'Quinn Walsh',
    'Ravi Mehta',
    'Sofia Chen',
    'Tomás Rivera',
    'Uma Joshi',
    'Viktor Kos',
    'Wren Murphy',
    'Xia Zhou',
    'Yuki Tanaka',
    'Zara Abbas',
    'Amara Osei',
    'Darius Volk',
    'Freya Strand',
    'Hugo Lam'
  ].freeze

  DOMAINS = [
    {
      activity: 'Onboarding',
      tasks:    ['Registration', 'Email verification', 'Welcome tour'],
      stories:  [
        'Sign up with an email address',
        'Sign up with a Google or Apple account',
        'Confirm the email address from a link',
        'Get set up in a few guided steps',
        'See how much of setup is left',
        'Skip setup and come back to it later',
        'Agree to the terms before starting',
        "Start using the account once it's confirmed"
      ]
    },
    {
      activity: 'Payments',
      tasks:    %w[Checkout Invoicing Subscriptions],
      stories:  [
        'Pay by card',
        'See that a payment went through',
        'Get a receipt by email',
        'Move to a bigger plan',
        'Pay only for the rest of the month after upgrading',
        'Retry a failed payment',
        'Download an invoice as a PDF',
        'Cancel the subscription'
      ]
    },
    {
      activity: 'Search',
      tasks:    ['Indexing', 'Query processing', 'Results display'],
      stories:  [
        'Find a document by any word in it',
        'See suggestions while typing',
        'Narrow results by type and date',
        'Find results despite a typo',
        'Run a recent search again',
        'See what people search for and fail to find',
        'Get help when a search finds nothing',
        'See the best match first'
      ]
    },
    {
      activity: 'Notifications',
      tasks:    %w[Delivery Preferences Templates],
      stories:  [
        'Get a push notification on the phone',
        'Get a daily summary email',
        'See new notifications in the app',
        'Choose how often to be notified',
        'Choose email, push or both',
        'Unsubscribe in one click',
        'Edit the wording of notification emails',
        'Look back at past notifications'
      ]
    },
    {
      activity: 'Reporting',
      tasks:    ['Data collection', 'Visualization', 'Export'],
      stories:  [
        "Get yesterday's numbers each morning",
        'See the numbers as a chart',
        'Choose the dates a report covers',
        'Download a report as a spreadsheet',
        'Get a report by email every week',
        'Put favourite reports on one page',
        'Compare this period with the last',
        'See when the numbers were last updated'
      ]
    },
    {
      activity: 'User profiles',
      tasks:    %w[Display Editing Privacy],
      stories:  [
        'Add a profile photo',
        'Write a short bio',
        'Change the name others see',
        'Hide the profile from people outside the team',
        'See what someone has worked on lately',
        'Show earned badges on the profile',
        'See what the profile is missing',
        'Link to other accounts from the profile'
      ]
    },
    {
      activity: 'Team management',
      tasks:    %w[Invitations Roles Settings],
      stories:  [
        'Invite people with a link',
        'Give someone a role',
        'See who can do what',
        'Rename the team',
        'Remove someone from the team',
        'Add or remove paid seats',
        'See who changed what, and when',
        "Sign in with the company's single sign-on"
      ]
    },
    {
      activity: 'Content publishing',
      tasks:    %w[Editor Review Distribution],
      stories:  [
        'Format text with headings, lists and links',
        'Have drafts saved while writing',
        'Preview a post before publishing',
        'Get a post approved before it goes out',
        'Publish at a chosen time',
        'Go back to an earlier version',
        'Share a post on social media',
        'Set how a post appears in search results'
      ]
    },
    {
      activity: 'Integrations',
      tasks:    ['OAuth connections', 'Webhooks', 'Sync'],
      stories:  [
        'Connect another tool by signing in to it',
        'Stay connected without signing in again',
        'Get events sent to another tool as they happen',
        'Accept only events the other tool really sent',
        'Have failed deliveries sent again',
        'See when data last synced',
        'Hear when a connection stops working',
        'Keep syncing when the other tool limits requests'
      ]
    },
    {
      activity: 'Mobile experience',
      tasks:    ['Responsive layout', 'Offline support', 'Performance'],
      stories:  [
        'Use the app comfortably on a small screen',
        'Swipe to archive or delete',
        'Keep working without a connection',
        'Open recent pages without waiting',
        'Load images quickly on a slow connection',
        'Start reading before the whole page has loaded',
        'Pull down to refresh',
        'Reach the main sections with one thumb'
      ]
    }
  ].freeze
end
