FROM ruby:3.3-slim

# Native client libraries for every supported engine: pg, mysql2, tiny_tds (FreeTDS).
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      build-essential libpq-dev default-libmysqlclient-dev freetds-dev libyaml-dev git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV RAILS_ENV=production PORT=3000

COPY Gemfile Gemfile.lock* ./
RUN bundle install --jobs 4

COPY . .

EXPOSE 3000
# Migrations/provisioning are explicit (see README), e.g.
#   docker compose run --rm backend bin/rails db:migrate
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
