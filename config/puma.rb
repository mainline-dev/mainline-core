# frozen_string_literal: true

preload_app!

before_fork do
  Sequel::DATABASES.each(&:disconnect)
end

before_worker_boot do
  Sequel::DATABASES.each(&:disconnect)
end
