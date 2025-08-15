import boto3
import os
import dotenv

dotenv.load_dotenv()
# === CONFIGURATION ===
R2_ACCESS_KEY_ID = os.getenv("R2_ACCESS_KEY_ID")
R2_SECRET_ACCESS_KEY = os.getenv("R2_SECRET_ACCESS_KEY")
R2_ENDPOINT_URL = os.getenv("R2_ENDPOINT")
BUCKET_NAME = os.getenv("R2_JSON_BUCKET")
TARGET_DOWNLOAD_DIR = "/home/drty-hry/Documents/transcript-editor/project/fixit-cy/transcripts/custom_transcript"  # <- Set your custom download dir here

# === SETUP CLIENT ===
session = boto3.Session()
s3 = session.client(
    service_name='s3',
    aws_access_key_id=R2_ACCESS_KEY_ID,
    aws_secret_access_key=R2_SECRET_ACCESS_KEY,
    endpoint_url=R2_ENDPOINT_URL
)

# === DOWNLOAD FUNCTION ===
def download_all_json_files():
    paginator = s3.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=BUCKET_NAME)

    for page in pages:
        for obj in page.get('Contents', []):
            key = obj['Key']
            if key.endswith('.json'):
                dest_path = os.path.join(TARGET_DOWNLOAD_DIR, key)
                os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                print(f"⬇️ Downloading {key} → {dest_path}")
                s3.download_file(BUCKET_NAME, key, dest_path)

    print("✅ Finished downloading all JSON files.")

# === RUN ===
if __name__ == "__main__":
    download_all_json_files()
