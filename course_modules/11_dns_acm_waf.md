# Module 11: Route 53, ACM, and WAF

## 1. Concept: DNS, TLS, and Edge Security

A production app requires a custom domain, HTTPS, and a perimeter defense shield.
- **Route 53:** AWS's highly-available DNS provider.
- **ACM (AWS Certificate Manager):** Issues free TLS/HTTPS certificates. We will use DNS validation (Terraform automatically creates a Route 53 record to "prove" we own the domain).
- **WAF (Web Application Firewall):** Protects the Application Load Balancer from SQL injection, cross-site scripting (XSS), and botnets.

### The `create_before_destroy` Lifecycle
When changing a TLS certificate or an Auto Scaling Launch Template, Terraform's default behavior is "Delete the old one, then create the new one." This results in seconds or minutes of downtime! By using the `lifecycle` block, we invert it: "Create the new one, attach it, and *then* delete the old one." Zero downtime.

---

## 2. Code Example: Protecting the Perimeter

### Part A: ACM Certificate and Validation
```hcl
# Grab our existing Route 53 Hosted Zone
data "aws_route53_zone" "main" {
  name         = "mycompany.com"
  private_zone = false
}

# 1. Request the Certificate
resource "aws_acm_certificate" "cert" {
  domain_name               = "api.mycompany.com"
  subject_alternative_names = ["*.api.mycompany.com"] # Wildcard certs
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true # CRITICAL for zero-downtime certificate rotation!
  }
}

# 2. Create the DNS Record to prove we own the domain
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
}

# 3. Tell Terraform to WAIT until AWS validates the certificate before proceeding
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
```

### Part B: Pointing DNS to the ALB
```hcl
# We use an ALIAS record (native AWS tech) instead of a standard CNAME.
# ALIAS records resolve to IPs directly without secondary lookups, saving DNS time.
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.mycompany.com"
  type    = "A"

  alias {
    name                   = aws_lb.external.dns_name
    zone_id                = aws_lb.external.zone_id
    evaluate_target_health = true # Route53 won't send traffic if ALB is down
  }
}
```

### Part C: AWS WAF (Web Application Firewall)
```hcl
resource "aws_wafv2_web_acl" "main" {
  name        = "app-waf"
  description = "Security rules for ALB"
  scope       = "REGIONAL" # Use CLOUDFRONT if attaching to CloudFront

  default_action { allow {} }

  # AWS runs a curated list of malicious IP addresses. Block them natively.
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action { none {} }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-waf-metric"
    sampled_requests_enabled   = true
  }
}

# Attach the Firewall to the Load Balancer
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.external.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
```

---

## 3. The "Why": What breaks if I skip this?

* **Skipping `create_before_destroy` on ACM:** When you add a new Subject Alternative Name (e.g., `dashboard.mycompany.com`) to the certificate, AWS must issue a brand new certificate. If Terraform destroys the old one first, your Load Balancer loses its HTTPS cert. All API traffic fails with SSL handshake errors for 5 minutes while the new certificate validates. `create_before_destroy` is non-negotiable here.
* **Skipping `aws_acm_certificate_validation`:** Without this block, Terraform will assume the certificate is ready instantly and will attempt to attach it to the ALB Listener. AWS will reject the API call because the certificate status is still "PENDING_VALIDATION". This block forces Terraform to gracefully pause for the 1-2 minutes DNS validation takes.
* **Using CNAME instead of ALIAS:** Standard CNAMEs add latency. More importantly, you cannot place a CNAME at the "root apex" of your domain (e.g., `mycompany.com`). Route 53 ALIAS records solve both of these fundamental DNS limitations.

---

## 4. Hands-on Exercise

Look closely at the `aws_route53_record.cert_validation` resource. It uses a `for_each` loop powered by a `for` expression inside it.
Write out on paper (or conceptualize) what that `for` expression is doing. 

*Hint:* `aws_acm_certificate.cert.domain_validation_options` returns a list of objects. The `for` loop transforms that list into a map, using the `domain_name` (like `api.mycompany.com`) as the unique map key. This map feeds the `for_each` argument!
