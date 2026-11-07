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
        'Sign-up form', 'Social login', 'Email confirmation link',
        'Welcome wizard', 'Progress indicator', 'Skip option',
        'Terms acceptance', 'Account activation'
      ]
    },
    {
      activity: 'Payments',
      tasks:    %w[Checkout Invoicing Subscriptions],
      stories:  [
        'Card entry form', 'Payment confirmation', 'Receipt email',
        'Plan upgrade flow', 'Proration logic', 'Failed payment retry',
        'Invoice PDF generation', 'Subscription cancellation'
      ]
    },
    {
      activity: 'Search',
      tasks:    ['Indexing', 'Query processing', 'Results display'],
      stories:  [
        'Full-text index', 'Autocomplete suggestions', 'Faceted filters',
        'Spell correction', 'Recent searches', 'Search analytics',
        'Empty state guidance', 'Result ranking'
      ]
    },
    {
      activity: 'Notifications',
      tasks:    %w[Delivery Preferences Templates],
      stories:  [
        'Push notification send', 'Email digest', 'In-app bell',
        'Frequency settings', 'Channel preferences', 'Unsubscribe flow',
        'Template editor', 'Notification history'
      ]
    },
    {
      activity: 'Reporting',
      tasks:    ['Data collection', 'Visualization', 'Export'],
      stories:  [
        'Daily summary', 'Chart rendering', 'Date range picker',
        'CSV export', 'Scheduled reports', 'Custom dashboards',
        'Comparison view', 'Data freshness indicator'
      ]
    },
    {
      activity: 'User profiles',
      tasks:    %w[Display Editing Privacy],
      stories:  [
        'Avatar upload', 'Bio field', 'Display name change',
        'Profile visibility toggle', 'Activity feed', 'Badge display',
        'Profile completeness bar', 'Social links'
      ]
    },
    {
      activity: 'Team management',
      tasks:    %w[Invitations Roles Settings],
      stories:  [
        'Invite link generation', 'Role assignment', 'Permission matrix',
        'Team name editor', 'Member removal', 'Seat management',
        'Audit log', 'SSO configuration'
      ]
    },
    {
      activity: 'Content publishing',
      tasks:    %w[Editor Review Distribution],
      stories:  [
        'Rich text editor', 'Draft autosave', 'Preview mode',
        'Approval workflow', 'Scheduled publishing', 'Version history',
        'Social sharing', 'SEO metadata'
      ]
    },
    {
      activity: 'Integrations',
      tasks:    ['OAuth connections', 'Webhooks', 'Sync'],
      stories:  [
        'OAuth flow', 'Token refresh', 'Webhook endpoint',
        'Payload validation', 'Retry logic', 'Sync status page',
        'Connection health check', 'Rate limit handling'
      ]
    },
    {
      activity: 'Mobile experience',
      tasks:    ['Responsive layout', 'Offline support', 'Performance'],
      stories:  [
        'Breakpoint adjustments', 'Touch gestures', 'Offline queue',
        'Cache strategy', 'Image optimization', 'Lazy loading',
        'Pull to refresh', 'Bottom navigation'
      ]
    }
  ].freeze
end
