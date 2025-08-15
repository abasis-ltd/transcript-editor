source 'https://rubygems.org'

ruby '3.3.0'

# Core Rails and DB
gem 'rails', '~> 6.1.7'
gem 'pg', '~> 1.5'
gem 'puma'
gem 'devise'

# Gemfile
gem "aws-sdk-s3", "~> 1.141"
gem 'activerecord-import'
gem 'parallel'
gem 'ruby-progressbar'
# API essentials
gem 'jbuilder', '~> 2.0'
gem 'rack-cors', require: 'rack/cors'
gem 'figaro' # For env variables, make sure config/application.yml is used

# Search and pagination
gem 'pg_search'
gem 'will_paginate'

# Multipart support (fix deprecated warnings, latest stable)
gem 'multipart-post', '~> 2.3'

# Ruby 3.3 native compatibility for nio4r (WebSocket, ActionCable)
gem 'nio4r', '~> 2.5.9'

# Authentication
gem 'devise_token_auth', '~> 1.2'
gem 'omniauth-google-oauth2'
gem 'omniauth-facebook'
gem 'omniauth-rails_csrf_protection', '~> 1.0'
gem 'activerecord-session_store'

# Assets (redcarpet, execjs needed for markdown, JS runtime)
gem 'redcarpet'
gem 'ejs'
gem 'execjs'

# VTT subtitle parsing
gem 'webvtt-ruby'

# Monitoring & logs on Heroku
gem 'newrelic_rpm'
gem 'rails_12factor'

# Debugging & Deployment
gem 'pry'

# Web servers: Unicorn is typical on Heroku (Passenger is optional, usually not used)
gem 'unicorn'

# API / integration clients
gem 'rest-client'
gem 'sony_ci_api', git: 'https://github.com/WGBH-MLA/sony_ci_api_rewrite.git', branch: 'main'

# Rake tasks
gem 'rake', '13.1.0'

# Environment variables in dev and production
gem 'dotenv-rails'

# Optional: Remove 'csv' and 'mutex_m' if only standard library CSV and Mutex needed
gem 'csv'
gem 'mutex_m'
