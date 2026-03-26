# Module 10: S3, SQS, Secrets Manager

## 1. Concept: Storage, Queues, and Credentials

**Amazon S3:** The backbone of AWS storage. We will use it for storing static assets (like images uploaded by users). S3 is secure by default, but it's easy to make a mistake and leak data. We must enforce strict policies.
**Amazon SQS:** Simple Queue Service. Our API service will drop jobs (like resizing an image) into an SQS queue. A background Worker container will pull from the queue. If a job fails 5 times, it gets sent to a Dead-Letter Queue (DLQ) for debugging rather than blocking the worker forever.
**AWS Secrets Manager:** Passwords must never live in Git or Terraform state. We create the "lockbox" in Terraform, and inject the secret dynamically.

---

## 2. Code Example: Auxilliary Services

### Part A: A Production-Grade S3 Bucket
```hcl
resource "aws_s3_bucket" "assets" {
  bucket = "${local.prefix}-assets-bucket-8921"
}

# 1. Versioning: Protects against accidental overwrites/deletions by employees
resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration { status = "Enabled" }
}

# 2. Encryption: Encrypt all data at rest securely
resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# 3. Public Access Block: Actively prevent anyone from making this bucket public
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 4. Lifecycle: Transition old files to cheaper storage
resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "move_old_versions_to_glacier"
    status = "Enabled"
    
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }
  }
}
```

### Part B: SQS with a Dead Letter Queue
```hcl
# The Dead Letter Queue (DLQ) where failed messages go
resource "aws_sqs_queue" "worker_dlq" {
  name                      = "${local.prefix}-worker-queue-dlq"
  message_retention_seconds = 1209600 # 14 days maximum
}

# The Main Queue
resource "aws_sqs_queue" "worker" {
  name                       = "${local.prefix}-worker-queue"
  visibility_timeout_seconds = 60 # How long a worker has to process it before it reappears

  # Tie the DLQ to the Main Queue
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.worker_dlq.arn
    maxReceiveCount     = 5 # After 5 failures, send to DLQ
  })
}

# Allow our specific SNS topic or EventBridge to publish to this Queue
resource "aws_sqs_queue_policy" "worker" {
  queue_url = aws_sqs_queue.worker.id
  policy = data.aws_iam_policy_document.sqs_policy.json
}
```

### Part C: Secrets Manager
```hcl
resource "aws_secretsmanager_secret" "db_password" {
  name        = "${local.prefix}/rds/mysql/master_password"
  description = "Aurora Cluster Master Password"
  
  # Automatically rotate the password every 30 days using a Lambda function
  # rotation_lambda_arn = aws_lambda_function.rotator.arn
  # rotation_rules { automatically_after_days = 30 }
}

# Generate a random password securely (this WILL be in the TF State file!)
resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}
```

---

## 3. The "Why": What breaks if I skip this?

* **Skipping `aws_s3_bucket_public_access_block`:** An employee trying to host a PDF quickly might attach a public bucket policy. Suddenly, all your user assets are leaking to the internet. The Public Access Block hard-overrides any dangerous policies placed on the bucket.
* **Skipping the DLQ in SQS:** If you deploy a bug in your Worker that fails when processing a specific message payload, the message returns to the queue. The worker grabs it again. Fails again. Endless loop. Your whole queue gets blocked by "poison pill" messages, dropping your processing throughput to zero. The DLQ isolates the poison pills.
* **Uploading config via `aws_s3_object` vs variables:** We didn't show `aws_s3_object` above, but you can use it to upload a `config.json` file to S3 on deployment. If you skip this, your app might boot up waiting for a manual user to upload the config, causing startup crash loops.

---

## 4. Hands-on Exercise

Write an `aws_s3_object` resource that takes a local file called `app-config.json` and uploads it to the `aws_s3_bucket.assets` bucket. 

Hint: Look up the `filemd5()` Terraform function. You can use it on the `etag` or `source_hash` argument of `aws_s3_object` so Terraform automatically re-uploads the JSON file if you edit it locally!
