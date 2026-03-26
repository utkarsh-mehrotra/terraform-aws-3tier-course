# Module 9: RDS Aurora and ElastiCache

## 1. Concept: The Stateful Data Tier

Compute (ECS) is stateless; we can kill and recreate containers all day. 
Data (RDS and ElastiCache) is stateful; if we kill a database, we lose the company.

**AWS Aurora (MySQL/PostgreSQL):** A cloud-native relational database. We deploy an Aurora *Cluster*. Inside the cluster, we run a Primary Writer Instance and multiple Reader Instances spread across Availability Zones for high availability. 

**AWS ElastiCache (Redis):** An in-memory cache/database. We deploy it in Cluster Mode with multiple shards to handle extreme throughput.

---

## 2. Code Example: Secure, Highly-Available Data

### Part A: Aurora MySQL
```hcl
# The Subnet Group tells RDS which subnets it is allowed to live in (Private Data Subnets!)
resource "aws_db_subnet_group" "aurora" {
  name       = "aurora-subnet-group"
  subnet_ids = module.vpc.private_database_subnets
}

# Fetch the KMS key for disk encryption (Managed by AWS natively)
data "aws_kms_alias" "rds" { name = "alias/aws/rds" }

# 1. The Cluster (The logical container for the data)
resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "app-aurora-cluster"
  engine                  = "aurora-mysql"
  engine_version          = "8.0.mysql_aurora.3.04.1"
  database_name           = "appdb"
  
  # Security!
  vpc_security_group_ids  = [aws_security_group.rds.id]
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  storage_encrypted       = true
  kms_key_id              = data.aws_kms_alias.rds.target_key_arn
  
  # Credentials (Pulled from Secrets Manager variable, NOT plain text)
  master_username         = "admin"
  master_password         = var.db_password 

  # Backups and Day 2 Ops
  backup_retention_period = 14
  preferred_backup_window = "02:00-04:00"
  
  # CRITICAL: Prevent accidental deletion of the database in production
  deletion_protection     = true
  skip_final_snapshot     = false # Force a backup before destroy

  lifecycle { prevent_destroy = true }
}

# 2. The Instances (The actual compute nodes querying the data)
resource "aws_rds_cluster_instance" "aurora_nodes" {
  # Create 3 nodes (1 writer in AZ 'a', two readers in 'b' and 'c')
  count              = 3 
  identifier         = "app-aurora-node-${count.index}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.r6g.large"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
}
```

### Part B: ElastiCache Redis
```hcl
resource "aws_elasticache_subnet_group" "redis" {
  name       = "redis-subnet-group"
  subnet_ids = module.vpc.private_database_subnets
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = "app-redis-cluster"
  description                   = "Redis cluster for app caching and sessions"
  node_type                     = "cache.m6g.large"
  port                          = 6379
  
  # Security
  subnet_group_name             = aws_elasticache_subnet_group.redis.name
  security_group_ids            = [aws_security_group.redis.id]
  at_rest_encryption_enabled    = true
  transit_encryption_enabled    = true
  
  # High Availability via Cluster Mode
  automatic_failover_enabled    = true
  multi_az_enabled              = true
  
  # 3 Shards, 2 replicas per shard
  replicas_per_node_group       = 2
  num_node_groups               = 3
}
```

---

## 3. The "Why": What breaks if I skip this?

* **Skipping `lifecycle { prevent_destroy = true }`:** If a junior developer renames `aws_rds_cluster.aurora` to `aws_rds_cluster.production_aurora` in the Terraform code and runs apply, Terraform will see that as "Destroy the old cluster and build a new one." `prevent_destroy` forces Terraform to intentionally error out and refuse to delete the database, saving the company.
* **`skip_final_snapshot = true`:** If you do manage to destroy the database (e.g. for cost saving in a dev environment), `skip_final_snapshot = false` ensures AWS takes one final, permanent backup right before deletion just in case you actually needed that data.
* **Skipping `transit_encryption_enabled = true` on Redis:** Redis sends data in plaintext by default. If your application caches OAuth tokens, user PII, or session IDs, anyone inside the VPC could hypothetically sniff that network traffic. Transit encryption forces TLS handshakes.

---

## 4. Hands-on Exercise

Notice how `aws_rds_cluster_instance` uses `count = 3` to create nodes. 
In a previous module, we used `for_each = toset(local.azs)` to create subnets.

Why might `count` be slightly problematic here if AWS retires AZ 'b' and you change the count to 2? (Hint: `count` operates on a numbered array `[0, 1, 2]`. If item `1` drops out, all subsequent items shift left, forcing Terraform to potentially rebuild `node-2` because its index changed to `1`).

Write a version of the `aws_rds_cluster_instance` block that uses `for_each` combined with a map or set instead of `count`.
