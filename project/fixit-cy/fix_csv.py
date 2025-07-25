import csv
from pathlib import Path

input_csv = Path("/home/drty-hry/Documents/transcript-editor/project/fixit-cy/data/transcripts_seeds.csv")  # your original CSV
output_csv = Path("/home/drty-hry/Documents/transcript-editor/project/fixit-cy/data/transcripts_seeds.csv")       # corrected output

PLACEHOLDER_URL = "https://example.com/placeholder"
COLLECTION = "default"  # adjust if necessary

with input_csv.open(newline="", encoding="utf-8") as fin, output_csv.open("w", newline="", encoding="utf-8") as fout:

    reader = csv.DictReader(fin)
    fieldnames = [
        "uid", "title", "description",
        "url", "audio_url", "image_url", "collection",
        "vendor", "vendor_identifier"
    ]
    writer = csv.DictWriter(fout, fieldnames=fieldnames)
    writer.writeheader()

    for row in reader:
        new_row = {
            "uid": row["uid"],
            "title": row["title"],
            "description": row.get("description", ""),
            "url": PLACEHOLDER_URL,
            "audio_url": row.get("audio_url", ""),
            "image_url": PLACEHOLDER_URL,
            "collection": COLLECTION,
            "vendor": row.get("vendor", ""),
            "vendor_identifier": row.get("vendor_identifier", ""),
        }
        writer.writerow(new_row)

print(f"✅ Written corrected CSV to: {output_csv.resolve()}")
