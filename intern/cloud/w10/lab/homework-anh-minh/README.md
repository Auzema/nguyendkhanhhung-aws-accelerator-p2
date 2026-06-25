# Detect Sensitive Data in S3 with Amazon Macie + Email Alerts

Hands-on lab: upload synthetic PII to S3, scan it with Amazon Macie, and get
findings delivered to your email through EventBridge → SNS.

```
sample files ──> S3 bucket ──> Macie ONE_TIME job ──> findings
                                                         │
                                          EventBridge rule (source: aws.macie)
                                                         │
                                                   SNS topic ──> email
```

## Prerequisites
- AWS CLI v2 configured (`aws sts get-caller-identity` works)
- Permissions for: S3, Macie (`macie2`), SNS, EventBridge (`events`)
- Region: `us-east-1` (edit `00-config.sh` to change)

## Run

```bash
chmod +x *.sh
./run-all.sh
```

Then:
1. **Confirm the SNS email.** Open the inbox for `lemans19008@gmail.com`
   (check spam) and click the AWS confirmation link. **No alerts arrive until
   you confirm.**
2. Wait a few minutes and check findings:
   ```bash
   ./06-check.sh
   ```
3. Macie publishes findings every 15 minutes → EventBridge → SNS → your email.

## Scripts
| Script | Purpose |
|--------|---------|
| `00-config.sh`     | shared env vars (bucket, topic, email, region) |
| `01-create-bucket.sh` | private encrypted S3 bucket |
| `02-samples.sh`    | generate fake PII files + upload |
| `03-sns.sh`        | SNS topic, email subscription, topic policy |
| `04-eventbridge.sh`| enable Macie + rule + SNS target (readable email) |
| `05-run-job.sh`    | create the ONE_TIME classification job |
| `06-check.sh`      | inspect job status + findings |
| `run-all.sh`       | runs 01→05 |
| `99-teardown.sh`   | delete all resources |

## Cost
Macie classification is ~$1/GB scanned; the sample files are a few KB, so this
costs cents. **Run `./99-teardown.sh` when done** and optionally disable Macie:
```bash
aws macie2 disable-macie --region us-east-1
```

## Notes
- All sample data is synthetic test data, not real people.
- The credit-card and SSN values are standard test numbers chosen so Macie
  reliably produces `SensitiveData:S3Object/*` findings.
