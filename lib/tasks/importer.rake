# lib/tasks/importer.rake
require 'csv'
require 'aws-sdk-s3'
require 'webvtt'
require 'activerecord-import'
require 'tempfile'

namespace :importer do
  desc "High-speed, idempotent import from CSV + R2 (Cloudflare) VTTs"
  task run_all: :environment do
    # ---- Config ----
    project_key         = ENV['PROJECT_KEY'] || 'fixit-cy'
    collections_csv     = Rails.root.join('project', project_key, 'data', 'collections_seeds.csv')
    transcripts_csv     = Rails.root.join('project', project_key, 'data', 'transcripts_seeds.csv')
    vtt_bucket          = ENV.fetch('R2_VTT_BUCKET', 'vtt-transcript')
    vtt_prefix          = ENV['R2_VTT_PREFIX'] # optional: only process keys starting with this
    TL_BATCH_SIZE       = Integer(ENV.fetch('TL_BATCH_SIZE', '5000')) # transcript_lines import batch
    TX_BATCH_SIZE       = Integer(ENV.fetch('TX_BATCH_SIZE', '2000')) # transcripts import batch

    puts "--- Import started (project=#{project_key}) ---"

    # ---- Step 1: Collections (upsert) ----
    puts "\n[1/3] Importing Collections from #{collections_csv} ..."
    collections_to_import = []
    CSV.foreach(collections_csv, headers: true, header_converters: :symbol, encoding: 'UTF-8') do |row|
      h = row.to_hash
      h.delete(:vendor) # not a column
      collections_to_import << h
    end
    if collections_to_import.any?
      Collection.import(
        collections_to_import,
        on_duplicate_key_update: { conflict_target: [:uid], columns: collections_to_import.first.keys - [:uid] },
        validate: false,
        batch_size: 2000
      )
    end
    puts "→ Collections processed: #{collections_to_import.size}"

    # ---- Step 2: Transcripts (upsert) ----
    puts "\n[2/3] Importing Transcripts from #{transcripts_csv} ..."
    # Build UID -> id maps only for UIDs we actually need (saves memory)
    needed_collection_uids = []
    needed_vendor_uids     = []

    raw_rows = []
    CSV.foreach(transcripts_csv, headers: true, header_converters: :symbol, encoding: 'UTF-8') do |row|
      raw_rows << row.to_hash
      needed_collection_uids << row[:collection]
      needed_vendor_uids     << row[:vendor]
    end
    needed_collection_uids.uniq!
    needed_vendor_uids.uniq!

    collections_map = Collection.where(uid: needed_collection_uids).pluck(:uid, :id).to_h
    vendors_map     = Vendor.where(uid: needed_vendor_uids).pluck(:uid, :id).to_h

    transcripts_to_import = raw_rows.map do |r|
      {
        uid:               r[:uid],
        title:             r[:title],
        description:       r[:description],
        audio_url:         r[:audio_url],
        image_url:         r[:image_url],
        collection_id:     collections_map[r[:collection]],
        vendor_id:         vendors_map[r[:vendor]],
        vendor_identifier: r[:vendor_identifier],
        project_uid:       project_key
      }
    end

    # sanity: drop rows missing required FKs
    missing_fk = transcripts_to_import.count { |t| t[:collection_id].nil? || t[:vendor_id].nil? }
    puts "  (warning) transcripts missing FK: #{missing_fk}" if missing_fk > 0
    transcripts_to_import.select! { |t| t[:collection_id] && t[:vendor_id] }

    if transcripts_to_import.any?
      Transcript.import(
        transcripts_to_import,
        on_duplicate_key_update: {
          conflict_target: [:uid],
          columns: [:title, :description, :audio_url, :image_url, :collection_id, :vendor_id, :vendor_identifier, :project_uid]
        },
        validate: false,
        batch_size: TX_BATCH_SIZE
      )
    end
    puts "→ Transcripts processed: #{transcripts_to_import.size}"

    # Build fast map for VTT matching (with and without extension)
    all_tx = Transcript.where(project_uid: project_key).select(:id, :vendor_identifier)
    by_exact = all_tx.index_by(&:vendor_identifier)
    by_stem  = all_tx.each_with_object({}) do |t, h|
      stem = File.basename(t.vendor_identifier.to_s, File.extname(t.vendor_identifier.to_s))
      h[stem] = t
    end

    # ---- Step 3: VTT → TranscriptLine (batched per file) ----
    puts "\n[3/3] Importing VTTs from R2 bucket=#{vtt_bucket} prefix=#{vtt_prefix.inspect} ..."
    s3 = Aws::S3::Client.new(
      access_key_id:     ENV.fetch("R2_ACCESS_KEY_ID"),
      secret_access_key: ENV.fetch("R2_SECRET_ACCESS_KEY"),
      endpoint:          "https://#{ENV.fetch('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com",
      region:            "auto"
    )

    total_files = 0
    total_lines = 0
    continuation = nil

    loop do
      resp = s3.list_objects_v2(bucket: vtt_bucket, prefix: vtt_prefix, continuation_token: continuation)
      objects = Array(resp.contents)
      break if objects.empty?

      objects.each do |obj|
        key  = obj.key
        base = File.basename(key)
        stem = File.basename(base, File.extname(base))

        transcript =
          by_exact[base] ||
          by_exact[stem] ||     # in case vendor_identifier was saved without extension
          by_stem[stem]

        unless transcript
          puts "  - skip: no transcript matched for VTT key=#{key}"
          next
        end

        # Delete old lines fast (SQL), not callbacks
        TranscriptLine.where(transcript_id: transcript.id).delete_all

        # stream object, parse to cues
        file_content = s3.get_object(bucket: vtt_bucket, key: key).body.read

        lines_buffer = []
        begin
          Tempfile.create(['vtt', '.vtt']) do |tmp|
            tmp.binmode
            tmp.write(file_content)
            tmp.flush

            vtt = WebVTT.read(tmp.path)
            vtt.cues.each_with_index do |cue, idx|
              # normalize text (strip tags and collapse whitespace)
              txt = cue.text.to_s
              txt = txt.gsub(/<[^>]+>/, ' ')
                       .gsub('&nbsp;', ' ')
                       .gsub(/\s+/, ' ')
                       .strip

              start_ms = (cue.start_in_sec.to_f * 1000).to_i
              end_ms   = (cue.end_in_sec.to_f * 1000).to_i
              end_ms   = start_ms if end_ms < start_ms # guard

              lines_buffer << {
                transcript_id: transcript.id,
                start_time:    start_ms,
                end_time:      end_ms,
                original_text: txt,
                sequence:      idx
              }

              # flush in batches to keep memory steady
              if lines_buffer.size >= TL_BATCH_SIZE
                TranscriptLine.import(lines_buffer, validate: false)
                total_lines += lines_buffer.size
                lines_buffer.clear
              end
            end
          end
        rescue => e
          puts "  - error parsing #{key}: #{e.class} #{e.message}"
          next
        end

        # final flush
        if lines_buffer.any?
          TranscriptLine.import(lines_buffer, validate: false)
          total_lines += lines_buffer.size
          lines_buffer.clear
        end

        total_files += 1
        puts "  ✓ #{key} → transcript_id=#{transcript.id}"
      end

      break unless resp.is_truncated
      continuation = resp.next_continuation_token
    end

    puts "\n--- Import complete. Files: #{total_files}, Lines: #{total_lines} ---"
  end
end
