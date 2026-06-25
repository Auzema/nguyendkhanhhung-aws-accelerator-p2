#!/usr/bin/env bash
# Step 2: generate SYNTHETIC PII files and upload them to the bucket.
# All data below is fake/test data, not real people.
source "$(dirname "$0")/00-config.sh"

OUT="$(dirname "$0")/sample-data"
mkdir -p "$OUT"

cat > "$OUT/employees.csv" <<'EOF'
name,email,ssn,credit_card,phone,address
John Doe,john.doe@example.com,123-45-6789,4111 1111 1111 1111,555-0142,123 Maple St Springfield IL
Jane Smith,jane.smith@example.com,987-65-4321,5500 0000 0000 0004,555-0199,456 Oak Ave Portland OR
Bob Lee,bob.lee@example.com,222-33-4444,3400 000000 00009,555-0123,789 Pine Rd Austin TX
EOF

cat > "$OUT/notes.txt" <<'EOF'
Customer escalation log (TEST DATA - synthetic, not real)
Cardholder Alice Wonder, card 4012 8888 8888 1881, exp 04/29.
SSN on file: 456-78-9012. Contact: alice.wonder@example.com, +1 555 0188.
Driver license issued in California.
EOF

echo ">> Uploading samples to s3://$BUCKET"
aws s3 cp "$OUT/" "s3://$BUCKET/" --recursive

echo "OK uploaded:"
aws s3 ls "s3://$BUCKET/"
