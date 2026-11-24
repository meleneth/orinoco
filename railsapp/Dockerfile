# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t orinoco .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name orinoco orinoco

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.10
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
  apt-get install --no-install-recommends -y ca-certificates curl git libffi-dev libjemalloc2 libvips postgresql-client tesseract-ocr tesseract-ocr-eng && \
  ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
  BUNDLE_DEPLOYMENT="1" \
  BUNDLE_PATH="/usr/local/bundle" \
  BUNDLE_WITHOUT="development" \
  LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS gems

# Install packages needed to build gems
RUN apt-get update -qq && \
  apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config libpq-dev && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor ./vendor
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
  rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
  # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
  bundle exec bootsnap precompile -j 1 --gemfile

# CSS compilation is a separate cacheable build target. Keep unrelated backend
# sources, screenshots and tests out of this stage.
FROM gems AS tailwind-builder
COPY app/assets/tailwind/ app/assets/tailwind/
COPY app/views/ app/views/
COPY app/components/ app/components/
COPY app/javascript/ app/javascript/
ARG TAILWIND_CACHE_BUST=0
RUN echo "Tailwind cache generation: ${TAILWIND_CACHE_BUST}" && mkdir -p app/assets/builds && \
  bundle exec tailwindcss -i app/assets/tailwind/application.css -o app/assets/builds/tailwind.css --minify && \
  test -s app/assets/builds/tailwind.css

FROM gems AS build
COPY . .
COPY --from=tailwind-builder /rails/app/assets/builds/tailwind.css /rails/app/assets/builds/tailwind.css

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
# Tailwind has already been compiled in its own target; keep Propshaft digesting
# all assets, but remove only the automatic Tailwind prerequisite.
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec ruby -e 'require "./config/application"; Rails.application.load_tasks; task = Rake::Task["assets:precompile"]; task.prerequisites.delete("tailwindcss:build"); abort "Missing compiled Tailwind CSS" unless File.size?("app/assets/builds/tailwind.css"); task.invoke'




# Final stage for app image
FROM base

RUN apt-get update -qq && \
  apt-get install --no-install-recommends -y libpq5 && \
  rm -rf /var/lib/apt/lists /var/cache/apt/archives
# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
  useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/thrust", "./bin/rails", "server", "-p", "3000", "-b", "0.0.0.0",  "-P", "/tmp/railspidfile"]
