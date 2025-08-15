require 'concurrent'

namespace :r2 do
  desc "Convert JSON transcripts from R2 to VTT and upload them to VTT bucket using threads"
  task :json_to_vtt => :environment do
    require 'aws-sdk-s3'
    require 'json'
    require 'time'

    raise "Missing R2 credentials/env" unless ENV['R2_ACCESS_KEY_ID'] && ENV['R2_SECRET_ACCESS_KEY'] && ENV['R2_ACCOUNT_ID']

    json_bucket = ENV.fetch("R2_JSON_BUCKET")
    vtt_bucket  = ENV.fetch("R2_VTT_BUCKET")
    endpoint    = "https://#{ENV['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com"

    s3 = Aws::S3::Client.new(
      access_key_id: ENV['R2_ACCESS_KEY_ID'],
      secret_access_key: ENV['R2_SECRET_ACCESS_KEY'],
      endpoint: endpoint,
      region: 'auto',
      force_path_style: true
    )

    puts "🔍 Listing .json transcripts in bucket: #{json_bucket}"

    json_keys = s3.list_objects_v2(bucket: json_bucket, prefix: "transcripts/").contents.map(&:key).select { |k| k.end_with?('.json') }

    pool = Concurrent::FixedThreadPool.new(8)

    json_keys.each do |key|
      pool.post do
        begin
          puts "⏳ Processing: #{key}"
          obj = s3.get_object(bucket: json_bucket, key: key)
          data = JSON.parse(obj.body.read)

          vtt = "WEBVTT\n\n"
          data["phrases"].each_with_index do |phrase, idx|
            start_time = format_vtt_timestamp(phrase["start_time"])
            end_time   = format_vtt_timestamp(phrase["end_time"])
            text       = phrase["text"]

            vtt += "#{idx + 1}\n#{start_time} --> #{end_time}\n#{text}\n\n"
          end

          vtt_key = key.gsub(".json", ".vtt").gsub("transcripts/", "webvtt/")

          puts "⬆️ Uploading VTT: #{vtt_key}"
          s3.put_object(
            bucket: vtt_bucket,
            key: vtt_key,
            body: vtt,
            content_type: "text/vtt"
          )
        rescue => e
          puts "❌ Error processing #{key}: #{e.message}"
        end
      end
    end

    pool.shutdown
    pool.wait_for_termination

    puts "✅ All JSON -> VTT uploads completed."
  end

  def format_vtt_timestamp(seconds)
    Time.at(seconds).utc.strftime("%H:%M:%S.%L")
  end
end
