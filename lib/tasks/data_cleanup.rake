require 'json'
require 'fileutils'

namespace :data_cleanup do

  # ===================================================================
  # NEW TASK: Add this to your data_cleanup.rake file
  # ===================================================================
  desc "DANGEROUS: Deletes ALL transcripts, lines, and edits for a given project"
  task :delete_project_transcripts, [:project_key] => :environment do |_, args|
    project_key = args[:project_key]
    abort("ERROR: Please provide a project_key. Usage: rake data_cleanup:delete_project_transcripts['project-key']") if project_key.blank?

    puts "!! WARNING: This is a destructive action. !!"
    puts "This will permanently delete all transcripts, lines, and edits for project: '#{project_key}'."
    print "Are you absolutely sure you want to continue? Type 'yes' to proceed: "
    
    # Wait for user confirmation to prevent accidental deletion
    prompt = STDIN.gets.chomp
    unless prompt.downcase == 'yes'
      puts "Aborted by user."
      return
    end

    puts "\nFinding transcripts for project '#{project_key}'..."
    transcripts = Transcript.where(project_uid: project_key)
    
    if transcripts.empty?
      puts "No transcripts found for this project. Nothing to delete."
      return
    end

    puts "Found #{transcripts.count} transcripts. Deleting them and all associated data now..."
    
    # `destroy_all` ensures all dependent records (lines, edits) are also deleted.
    transcripts.destroy_all
    
    puts "\nSUCCESS: All transcripts for project '#{project_key}' have been deleted."
  end


  desc "Fix non-standard timestamps in source JSON files for a given project"
  task :fix_json_timestamps, [:project_key] => :environment do |task, args|
    project_key = args[:project_key]
    abort("ERROR: Please provide a project_key. Usage: rake data_cleanup:fix_json_timestamps['project-key']") if project_key.blank?

    json_directory = Rails.root.join('project', project_key, 'transcripts', 'custom_transcript')
    unless Dir.exist?(json_directory)
      abort("ERROR: Directory not found: #{json_directory}")
    end

    json_files = Dir.glob(json_directory.join('*.json'))
    if json_files.empty?
      puts "No JSON files found in the directory to process."
      return
    end

    puts "--- Starting Timestamp Cleanup for project '#{project_key}' ---"
    puts "Found #{json_files.length} JSON files to check."

    files_changed = 0

    json_files.each do |file_path|
      puts "\nProcessing: #{File.basename(file_path)}"
      original_content = File.read(file_path)
      data = JSON.parse(original_content)

      unless data.is_a?(Hash) && data.key?('phrases') && data['phrases'].is_a?(Array)
        puts "  - SKIPPING: File does not contain a 'phrases' array."
        next
      end

      file_needs_update = false

      data['phrases'].each do |phrase|
        ['start_time', 'end_time'].each do |key|
          timestamp_str = phrase[key]

          if timestamp_str.is_a?(String) && timestamp_str.count('.') > 1
            file_needs_update = true
            parts = timestamp_str.split('.')
            minutes = parts[0].to_i
            seconds = parts[1].to_i
            milliseconds_part = "0.#{parts[2]}".to_f
            total_seconds = (minutes * 60) + seconds + milliseconds_part
            phrase[key] = total_seconds.round(3)
          end
        end
      end

      if file_needs_update
        puts "  - SUCCESS: Timestamps reformatted. Saving changes."
        File.write(file_path, JSON.pretty_generate(data))
        files_changed += 1
      else
        puts "  - SKIPPING: Timestamps are already in a valid format."
      end
    end

    puts "\n--- Cleanup Complete ---"
    puts "Processed #{json_files.length} files."
    puts "#{files_changed} files were updated."
  end

end
