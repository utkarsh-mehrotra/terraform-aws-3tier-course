# Module 3: VPC and Networking

## 1. Concept: The Network Blueprint

A Virtual Private Cloud (VPC) is your private slice of AWS. Inside it, you create subnets (smaller networks) spread across Availability Zones (AZs - essentially independent data centers). 

For a production-grade 3-Tier Web Application, we need a robust, fault-tolerant network design:
- **Public Subnets:** Connected to the Internet Gateway. Holds our Application Load Balancer (ALB) and NAT Gateways.
- **Private Subnets (App Tier):** No direct internet access. Holds our ECS Fargate API and Worker tasks. They access the internet outbound via the NAT Gateways in the public subnets.
- **Private Subnets (Data Tier):** Maximum security. Holds RDS and ElastiCache. No internet access, inbound or outbound.

### Programming Infrastructure (`for_each`, `cidrsubnet`)
Instead of copying and pasting subnet code 9 times, we use Terraform meta-arguments like `for_each` and functions like `cidrsubnet()` to loop through data and calculate IP ranges mathematically.

---

## 2. Code Example: Building the VPC from Scratch

**`vpc.tf`**
```hcl
# 1. The VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16" # Provides 65,536 IP addresses
  enable_dns_hostnames = true          # Required for RDS and ECS
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# 2. Internet Gateway for Public access
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

locals {
  # We define our 3 Availability Zones
  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# 3. Public Subnets
resource "aws_subnet" "public" {
  for_each = toset(local.azs)
  
  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  
  # cidrsubnet(prefix, newbits, netnum)
  # 10.0.0.0/16 -> add 8 bits = /24. 
  # Index() returns 0, 1, 2 for a, b, c. Results: 10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, index(local.azs, each.key))
  map_public_ip_on_launch = true # Automatically give EC2 instances public IPs

  tags = { Name = "${local.name_prefix}-public-${each.key}" }
}

# 4. App Tier Private Subnets (We offset by 10 to avoid overlap: 10.0.10.0/24...)
resource "aws_subnet" "private_app" {
  for_each          = toset(local.azs)
  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, index(local.azs, each.key) + 10)

  tags = { Name = "${local.name_prefix}-private-app-${each.key}" }
}

# 5. Data Tier Private Subnets (Offset by 20: 10.0.20.0/24...)
resource "aws_subnet" "private_data" {
  for_each          = toset(local.azs)
  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, index(local.azs, each.key) + 20)

  tags = { Name = "${local.name_prefix}-private-data-${each.key}" }
}

# 6. NAT Gateways (One per AZ for High Availability)
resource "aws_eip" "nat" {
  for_each = toset(local.azs)
  domain   = "vpc"
}

resource "aws_nat_gateway" "nat" {
  for_each      = toset(local.azs)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  # Explicit dependency: NAT GW requires the IGW to exist before provisioning
  depends_on = [aws_internet_gateway.igw]
}

# 7. Route Tables
# Public Route Table (Sends 0.0.0.0/0 to IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables (One per AZ, sending 0.0.0.0/0 to the NAT GW in that specific AZ)
resource "aws_route_table" "private" {
  for_each = toset(local.azs)
  vpc_id   = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[each.key].id
  }
}

resource "aws_route_table_association" "private_app" {
  for_each       = aws_subnet.private_app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}
```

---

## 3. The "Why": What breaks if I skip this?

* **Hardcoding Subnet CIDRs:** If you manually type `cidr_block="10.0.1.0/24"`, adding a 4th AZ or changing the main VPC CIDR requires you to rewrite all 9 subnet blocks. `cidrsubnet()` makes your code mathematically adaptable.
* **Skipping `depends_on = [aws_internet_gateway.igw]`:** Terraform provisions objects in parallel! It might try to spin up the NAT Gateway before the IGW is attached to the VPC, failing with a bizarre AWS API error. The explicit `depends_on` forces the exact correct sequence.
* **One NAT Gateway instead of Three:** A NAT Gateway lives in one AZ. If that AZ goes down, the other AZs lose internet access. Production tier apps require one NAT Gateway *per AZ* for genuine high availability.

---

## 4. Hands-on Exercise

1. Open the Terraform `console` by running:
   ```bash
   terraform console
   ```
2. The interactive console is the perfect place to test Terraform functions safely. Enter the following commands one by one to see how `cidrsubnet()` mathematics work:
   ```hcl
   > cidrsubnet("10.0.0.0/16", 8, 0)
   > cidrsubnet("10.0.0.0/16", 8, 1)
   > cidrsubnet("10.0.0.0/16", 8, 10)
   > cidrsubnet("10.0.0.0/16", 4, 1)
   ```
3. Type `exit` or `Ctrl+C` to leave the console when you are done.
