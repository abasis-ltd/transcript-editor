require 'concurrent'
require 'aws-sdk-s3'
require 'webvtt'
require 'tempfile'

namespace :webvtt do
  desc "Read VTT files from R2 bucket and insert transcripts into the database"
  task :read_r2 => :environment do
    raise "Missing R2 credentials/env" unless ENV['R2_ACCESS_KEY_ID'] && ENV['R2_SECRET_ACCESS_KEY'] && ENV['R2_ACCOUNT_ID']

    vtt_bucket = ENV.fetch("R2_VTT_BUCKET")
    endpoint   = "https://#{ENV['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com"

    s3 = Aws::S3::Client.new(
      access_key_id: ENV['R2_ACCESS_KEY_ID'],
      secret_access_key: ENV['R2_SECRET_ACCESS_KEY'],
      endpoint: endpoint,
      region: 'auto',
      force_path_style: true
    )

    puts "🔍 Listing .vtt files in bucket: #{vtt_bucket}"
    vtt_keys = s3.list_objects_v2(bucket: vtt_bucket, prefix: "webvtt/").contents.map(&:key).select { |k| k.end_with?('.vtt') }

    vtt_keys.each do |key|
      begin
        transcript_uid = File.basename(key, ".vtt")
        existing = Transcript.find_by(uid: transcript_uid)
        if existing && TranscriptLine.exists?(transcript_id: existing.id)
          puts "⚠️ Skipping #{key}: transcript already processed"
          next
        end

        puts "⏳ Reading: #{key}"
        obj = s3.get_object(bucket: vtt_bucket, key: key)
        vtt_content = obj.body.read

        Tempfile.create(['vtt_file', '.vtt']) do |file|
          file.write(vtt_content)
          file.rewind

          parsed = WebVTT.read(file)

          transcript = existing || Transcript.new(uid: transcript_uid)
          transcript.vendor ||= Vendor.find_by(uid: 'webvtt')
          transcript.vendor_identifier = File.basename(key)
          transcript.save!

          parsed.cues.each_with_index do |cue, idx|
            begin
              TranscriptLine.create!(
                transcript: transcript,
                sequence: idx,
                start_time: cue.start.to_f,
                end_time: cue.end.to_f,
                text: cue.text
              )
            rescue ActiveRecord::RecordNotUnique => e
              puts "⚠️ Duplicate line for #{key} sequence #{idx}, skipping"
            end
          end

          puts "✅ Inserted Transcript: #{transcript_uid} with #{parsed.cues.count} lines"
        end

      rescue Aws::S3::Errors::ServiceError => e
        puts "❌ Network or AWS error processing #{key}: #{e.message}. Retrying..."
        sleep 5
        retry
      rescue => e
        puts "❌ Error processing #{key}: #{e.message}"
      end
    end

    puts "🏁 All VTT files processed."
  end
end
