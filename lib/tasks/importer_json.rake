# lib/tasks/importer_json.rake
require 'aws-sdk-s3'
require 'json'
require 'activerecord-import'

namespace :importer do
  desc "Import transcript_lines from JSON chunks in R2 and update transcripts.lines"
  task json_lines: :environment do
    project_uid   = ENV['PROJECT_KEY'] || 'fixit-cy'
    bucket        = ENV.fetch('R2_JSON_BUCKET', 'vtt-transcript') # set to your JSON bucket
    prefix        = ENV['R2_JSON_PREFIX']                         # optional
    batch_size    = Integer(ENV.fetch('TL_BATCH_SIZE','5000'))

    s3 = Aws::S3::Client.new(
      access_key_id:     ENV.fetch("R2_ACCESS_KEY_ID"),
      secret_access_key: ENV.fetch("R2_SECRET_ACCESS_KEY"),
      endpoint:          "https://#{ENV.fetch('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com",
      region:            "auto"
    )

    # Build map: vendor_identifier (with and w/o extension) -> transcript
    txs   = Transcript.where(project_uid: project_uid).select(:id,:vendor_identifier)
    exact = txs.index_by(&:vendor_identifier)
    stem  = txs.each_with_object({}) do |t,h|
      k = File.basename(t.vendor_identifier.to_s, File.extname(t.vendor_identifier.to_s))
      h[k] = t
    end

    def parse_hms_or_seconds(str)
      s = str.to_s.strip
      if s.count('.') == 2 # H.M.S
        h,m,sec = s.split('.')
        ((h.to_i*3600 + m.to_i*60 + sec.to_i) * 1000)
      else
        (Float(s) * 1000).to_i   # "120.000"
      end
    rescue
      0
    end

    total_files = 0
    total_lines = 0
    next_token  = nil

    loop do
      resp = s3.list_objects_v2(bucket: bucket, prefix: prefix, continuation_token: next_token)
      keys = Array(resp.contents)
      break if keys.empty?

      keys.each do |obj|
        key  = obj.key
        base = File.basename(key)
        st   = File.basename(base, File.extname(base))

        t = exact[base] || exact[st] || stem[st]
        unless t
          puts "skip: no transcript for #{key}"
          next
        end

        body = s3.get_object(bucket: bucket, key: key).body.read
        data = JSON.parse(body) rescue nil
        unless data && data['phrases'].is_a?(Array)
          puts "skip: bad JSON schema in #{key}"
          next
        end

        # wipe old lines quickly
        TranscriptLine.where(transcript_id: t.id).delete_all

        buf = []
        data['phrases'].each_with_index do |ph, i|
          start_ms = parse_hms_or_seconds(ph['start_time'])
          end_ms   = parse_hms_or_seconds(ph['end_time'])
          end_ms   = start_ms if end_ms < start_ms
          text     = ph['text'].to_s.gsub(/\s+/, ' ').strip

          buf << {
            transcript_id: t.id,
            start_time:    start_ms,
            end_time:      end_ms,
            original_text: text,
            sequence:      i
          }

          if buf.size >= batch_size
            TranscriptLine.import(buf, validate:false)
            total_lines += buf.size
            buf.clear
          end
        end

        TranscriptLine.import(buf, validate:false) if buf.any?
        total_lines += buf.size

        # update cached lines count (counter caches won’t fire on bulk import)
        cnt = TranscriptLine.where(transcript_id: t.id).count
        Transcript.where(id: t.id).update_all(lines: cnt)

        total_files += 1
        puts "✓ #{key} → transcript_id=#{t.id}, lines=#{cnt}"
      end

      break unless resp.is_truncated
      next_token = resp.next_continuation_token
    end

    puts "--- Done. Files: #{total_files}, Lines: #{total_lines} ---"
  end
end
