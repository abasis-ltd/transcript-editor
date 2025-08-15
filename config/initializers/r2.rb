# config/initializers/r2.rb
require "aws-sdk-s3"

R2_S3_CLIENT = Aws::S3::Client.new(
  access_key_id:     ENV.fetch("R2_ACCESS_KEY_ID"),
  secret_access_key: ENV.fetch("R2_SECRET_ACCESS_KEY"),
  endpoint:          ENV["R2_ENDPOINT"] || "https://#{ENV.fetch('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com",
  region:            "auto",
  force_path_style:  true
)

R2_S3 = Aws::S3::Resource.new(client: R2_S3_CLIENT)

R2_AUDIO_BUCKET = ENV.fetch("R2_AUDIO_BUCKET", "audio")
R2_JSON_BUCKET  = ENV.fetch("R2_JSON_BUCKET",  "json")
R2_VTT_BUCKET   = ENV.fetch("R2_VTT_BUCKET",   "vtt")

module R2
  module_function

  def each_object(bucket:, prefix:)
    token = nil
    loop do
      resp = R2_S3_CLIENT.list_objects_v2(bucket: bucket, prefix: prefix, continuation_token: token)
      (resp.contents || []).each { |o| yield o.key }
      break unless resp.is_truncated
      token = resp.next_continuation_token
    end
  end

  def get_object_string(bucket:, key:)
    R2_S3_CLIENT.get_object(bucket: bucket, key: key).body.read
  end

  def put_object(bucket:, key:, body:, content_type:)
    R2_S3_CLIENT.put_object(bucket: bucket, key: key, body: body, content_type: content_type)
  end
end
