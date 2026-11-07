FROM ruby:3.4.9

# Install system dependencies
RUN apt-get update -qq && apt-get install -y build-essential postgresql-client && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install gems first (this layer will be cached if Gemfile doesn't change)
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without deploy && bundle install --jobs 1 --retry 3

RUN useradd -m -s /bin/bash app

# Copy the rest of the app
COPY --chown=app:app . .

USER app

EXPOSE 3000

# Use bundle exec to ensure all gems are available
CMD ["sh", "-c", "bundle exec rake prod_up && bundle exec puma -p 3000 -b tcp://0.0.0.0 -w 2 -t 5:5"]