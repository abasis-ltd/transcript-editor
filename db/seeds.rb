# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the `rails db:seed` command.

# Seed User Roles
puts "Seeding User Roles..."
[
  { name: 'guest',     hiearchy: 0,   description: 'Unregistered user' },
  { name: 'user',      hiearchy: 10,  description: 'Registered user' },
  { name: 'moderator', hiearchy: 50,  description: 'Moderator can review edits' },
  { name: 'admin',     hiearchy: 100, description: 'Administrator has all privileges' }
].each do |attributes|
  user_role = UserRole.find_or_initialize_by(name: attributes[:name])
  user_role.update(attributes)
end

# Seed Vendors
puts "Seeding Vendors..."
[
  { uid: 'pop_up_archive', name: 'Pop Up Archive', description: 'Pop Up Archive makes sound searchable using cutting edge speech-to-text technology', url: 'https://popuparchive.com/' },
  { uid: 'webvtt', name: 'WebVTT', description: 'WebVTT (Web Video Text Tracks) is a W3C standard for displaying timed text in connection with HTML5.', url: 'https://w3c.github.io/webvtt/' }
].each do |attributes|
  vendor = Vendor.find_or_initialize_by(uid: attributes[:uid])
  vendor.update(attributes)
end

# Seed Transcript Statuses
# This section is updated to include the statuses your Rake task requires.
puts "Seeding Transcript Statuses..."
[
  # Original statuses
  { name: 'initialized',            progress: 0,    description: 'Transcript initialized' },
  { name: 'audio_uploaded',         progress: 10,   description: 'Audio has been uploaded' },
  { name: 'transcript_downloaded',  progress: 30,   description: 'Transcript has been downloaded' },
  { name: 'transcript_complete',    progress: 100,  description: 'Transcript has been completed' },
  { name: 'transcript_problematic', progress: 150,  description: 'Transcript has been completed but may contain errors' },
  { name: 'transcript_archived',    progress: 200,  description: 'Transcript has been archived' },

  # Required statuses for rake tasks and general use
  { name: 'processing',             progress: 20,   description: 'Transcript is being processed.' },
  { name: 'editing',                progress: 40,   description: 'Transcript is being edited.' },
  { name: 'reviewing',              progress: 50,   description: 'Transcript is being reviewed.' },
  { name: 'completed',              progress: 100,  description: 'Transcript has been marked as complete.' },
  { name: 'error',                  progress: 150,  description: 'An error occurred during processing.' }
].each do |attributes|
  status = TranscriptStatus.find_or_initialize_by(name: attributes[:name])
  status.update(attributes)
end

# Seed Transcript Line Statuses
puts "Seeding Transcript Line Statuses..."
[
  { id: 1, name: 'initialized', progress: 0,    description: 'Line contains unedited computer-generated text. Please edit if incorrect!' },
  { id: 2, name: 'editing',     progress: 25,   description: 'Line has been edited by others. Please edit if incorrect!' },
  { id: 3, name: 'reviewing',   progress: 50,   description: 'Line is being reviewed and is no longer editable. Click \'Verify\' to review.' },
  { id: 4, name: 'completed',   progress: 100,  description: 'Line has been completed and is no longer editable' },
  { id: 5, name: 'flagged',     progress: 150,  description: 'Line has been marked as incorrect or problematic' },
  { id: 6, name: 'archived',    progress: 200,  description: 'Line has been archived' }
].each do |attributes|
  # Use a block with find_or_create_by to handle both creation and ensuring ID.
  TranscriptLineStatus.find_or_create_by(id: attributes[:id]) do |status|
    status.name = attributes[:name]
    status.progress = attributes[:progress]
    status.description = attributes[:description]
  end
end

# Seed Flag Types
puts "Seeding Flag Types..."
[
  { name: 'misspellings', label: 'Contains misspellings', category: 'error', description: 'Line contains text that is incorrect or misspelled' },
  { name: 'repeated', label: 'Contains repeated word(s)', category: 'error', description: 'Line contains text that is repeated on the same, previous, or next line' },
  { name: 'missing', label: 'Missing word(s)', category: 'error', description: 'Line is missing text that was spoken in the audio' },
  { name: 'misc_error', label: 'Other', category: 'error', description: 'Any other type of error' }
].each do |attributes|
  type = FlagType.find_or_initialize_by(name: attributes[:name])
  type.update(attributes)
end

puts "\nDatabase seeding complete!"