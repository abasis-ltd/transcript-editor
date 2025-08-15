# script/audit_fix_vtt.rb
# Usage: bundle exec rails runner script/audit_fix_vtt.rb <project_key>
# Env:
#   R2_VTT_BUCKET   (default: "vtt-transcript")
#   VTT_PREFIX      (default: "")
#   DRY_RUN=1       (don’t write updates)
# Notes:
#   - Audits transcripts with lines=0 to see which VTTs exist in bucket.
#   - Auto-fixes vendor_identifier by matching real VTT filenames (safe variants).

require "set"

PROJECT_KEY = (ARGV[0] || ENV["PROJECT_KEY"] || "").strip
abort "project_key required (argv[0])" if PROJECT_KEY.empty?

BUCKET = ENV["R2_VTT_BUCKET"].presence || "vtt-transcript"
PREFIX = (ENV["VTT_PREFIX"] || ENV["prefix"] || "").to_s.sub(/\A\//, "")
DRY    = ENV["DRY_RUN"] == "1"

# Get S3 client (use initializer if present; else build from env)
def r2_s3_client
  return R2_S3_CLIENT if defined?(R2_S3_CLIENT)
  require "aws-sdk-s3"
  endpoint = ENV["R2_ENDPOINT"] || "https://#{ENV.fetch("R2_ACCOUNT_ID")}.r2.cloudflarestorage.com"
  Aws::S3::Client.new(
    access_key_id:     ENV.fetch("R2_ACCESS_KEY_ID"),
    secret_access_key: ENV.fetch("R2_SECRET_ACCESS_KEY"),
    endpoint:          endpoint,
    region:            "auto",
    force_path_style:  true
  )
end

def prelist_vtt_keys(s3, bucket:, prefix:)
  keys = Set.new
  cont = nil
  loop do
    resp = s3.list_objects_v2(bucket: bucket, prefix: prefix.presence, continuation_token: cont)
    (resp.contents || []).each { |o| keys << o.key if o.key.downcase.end_with?(".vtt") }
    break unless resp.is_truncated
    cont = resp.next_continuation_token
  end
  keys
end

def basename_without_ext(file)
  file.sub(/\A.*\//, "").sub(/\.vtt\z/i, "")
end

# Generate safe matching variants for a title/base
def variants(base)
  out = Set.new([base])
  # strip zero padding in numeric tokens
  out << base.gsub(/_0+(\d+)/, '_\1')
  # pad numeric tokens to 3
  out << base.gsub(/(\d+)/) { |m| "%03d" % m.to_i }
  # special case: *_chunk_X_Y
  if base =~ /^(.*_chunk_)(\d+)_(\d+)$/
    a, x, y = $1, $2, $3
    out << "#{a}#{x.to_i}_#{y.to_i}"
    out << "#{a}%03d_%03d" % [x.to_i, y.to_i]
    out << "#{a}%03d_#{y.to_i}" % [x.to_i]
    out << "#{a}#{x.to_i}_%03d" % [y.to_i]
  end
  out.to_a.uniq
end

s3 = r2_s3_client
vendor = Vendor.find_by(uid: "webvtt") || Vendor.find_by(name: "webvtt")
abort "Vendor 'webvtt' missing. Create it first." unless vendor

scope = Transcript.where(vendor_id: vendor.id, project_uid: PROJECT_KEY, lines: 0)
total = scope.count
puts "Project=#{PROJECT_KEY}  Bucket=#{BUCKET}  Prefix='#{PREFIX}'"
puts "Auditing #{total} transcript(s) with lines=0…"

# STEP 1 — AUDIT (present vs missing)
key_set = prelist_vtt_keys(s3, bucket: BUCKET, prefix: PREFIX)
present = 0
missing = 0
missing_rows = []

scope.find_each(batch_size: 1000) do |t|
  k = PREFIX.present? ? "#{PREFIX}/#{t.vendor_identifier}" : t.vendor_identifier
  if key_set.include?(k)
    present += 1
  else
    missing += 1
    missing_rows << [t.id, t.title, t.vendor_identifier, k]
  end
end

puts "Audit result: total=#{total}  vtt_present=#{present}  vtt_missing=#{missing}"
if missing_rows.any?
  puts "Missing sample (id | title | vendor_identifier | expected_key):"
  missing_rows.first(20).each { |r| puts r.join(" | ") }
end

# STEP 2 — AUTO-FIX vendor_identifier by matching VTT filenames
puts "\nBuilding VTT basename → filename map from bucket…"
vtt_name = {} # base => filename
key_set.each do |k|
  next unless k.downcase.end_with?(".vtt")
  file = k.split("/").last
  base = basename_without_ext(file)
  vtt_name[base] ||= file
end
puts "Mapped #{vtt_name.size} VTT basenames."

fixed = 0
ambig = 0
none  = 0

scope.find_each(batch_size: 500) do |t|
  # Skip if current vendor_identifier already exists in bucket
  current_key = PREFIX.present? ? "#{PREFIX}/#{t.vendor_identifier}" : t.vendor_identifier
  if key_set.include?(current_key)
    next
  end

  cands = variants(t.title.to_s).map { |b| vtt_name[b] }.compact.uniq
  case cands.size
  when 1
    vi = cands.first # filename only
    if DRY
      puts "[DRY] FIX id=#{t.id}  #{t.vendor_identifier.inspect} -> #{vi.inspect}"
    else
      t.update_columns(vendor_identifier: vi, updated_at: Time.current)
    end
    fixed += 1
  when 0
    none += 1
  else
    # Multiple possible matches—don’t guess
    ambig += 1
    puts "AMBIG id=#{t.id} title=#{t.title.inspect} matches=#{cands.join(',')}" if ENV["VERBOSE"] == "1"
  end
end

puts "\nFix summary: fixed=#{fixed}  ambiguous=#{ambig}  still_none=#{none}  dry_run=#{DRY}"
puts "Re-run the importer for the project after fixes, e.g.:"
puts "  DB_POOL=16 THREADS=12 BATCH=1000 SKIP_RETRIEVED=1 QUIET=1 \\"
puts "  bundle exec rake webvtt:read_r2['#{PROJECT_KEY}'] bucket=#{BUCKET} prefix='#{PREFIX}'"
