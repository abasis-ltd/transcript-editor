# lib/tasks/db.rake
namespace :db do
  desc "⚠️ DANGEROUS: Drop and recreate PUBLIC schema (removes ALL tables, views, sequences)."
  task :nuke => :environment do
    if Rails.env.production? && ENV['ALLOW_PROD'] != '1'
      abort "Refusing to run in production. Set ALLOW_PROD=1 if you really mean it."
    end
    unless ENV['NUKE'] == '1' || ENV['CONFIRM']&.upcase == 'NUKE'
      abort "Safety check: export NUKE=1 (or CONFIRM=NUKE) to proceed."
    end

    conn = ActiveRecord::Base.connection
    conn.execute "DROP SCHEMA IF EXISTS public CASCADE;"
    conn.execute "CREATE SCHEMA public;"
    conn.execute "GRANT ALL ON SCHEMA public TO CURRENT_USER;"
    conn.execute "GRANT USAGE, CREATE ON SCHEMA public TO PUBLIC;"

    puts "✅ public schema reset. Now run: bundle exec rails db:migrate"
  end
end
