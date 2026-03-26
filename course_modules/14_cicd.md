# Module 14: Terraform in CI/CD

## 1. Concept: Automation and Secrets

Running `terraform apply` from a laptop is fine for a solo developer, but reckless for a team.
- **Traceability:** Who ran the apply? When? Why?
- **Security:** Do all developers need full AWS Admin keys on their laptops? No.

### The Standard Pipeline
1. **Pull Request Opened:** CI runs `terraform fmt --check`, `terraform validate`, `tfsec` (for security vulnerabilities), and `terraform plan`. It posts the Plan output as a comment on the PR.
2. **Review:** A Senior Engineer reviews the Code diff *and* the Terraform Plan output simultaneously.
3. **Merge to Main:** CI detects the merge, runs `terraform apply -auto-approve`, and updates production.

**Atlantis:** Keep an eye out for [Atlantis](https://www.runatlantis.io/). It's a popular open-source tool built specifically to orchestrate this precise workflow via PR comments (e.g., typing `atlantis apply` in a GitHub comment).

---

## 2. Code Example: GitHub Actions Pipeline

Here is a mature GitHub Actions workflow utilizing **OIDC (OpenID Connect)**. OIDC allows GitHub to talk to AWS securely *without* creating long-lived IAM User Access Keys that might leak.

**`.github/workflows/terraform.yml`**
```yaml
name: 'Terraform Infrastructure'

on:
  push:
    branches: [ "main" ]
  pull_request:

permissions:
  id-token: write # Required for AWS OIDC authentication
  contents: read  # Required to checkout the code
  pull-requests: write # Required to comment on PRs

jobs:
  terraform:
    name: 'Terraform'
    runs-on: ubuntu-latest
    
    # Pass secret variables from GitHub securely using TF_VAR convention
    env:
      TF_VAR_db_password: ${{ secrets.PROD_DB_PASSWORD }}

    steps:
    - name: Checkout
      uses: actions/checkout@v3

    # 1. Secure Authentication without hardcoded keys
    - name: Configure AWS Credentials
      uses: aws-actions/configure-aws-credentials@v2
      with:
        role-to-assume: arn:aws:iam::123456789012:role/github-actions-terraform-role
        aws-region: us-east-1

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v2
      with:
        terraform_version: 1.5.0

    # 2. Syntax and Formatting validation
    - name: Terraform Format
      run: terraform fmt -check

    - name: Terraform Init
      run: terraform init

    - name: Terraform Validate
      run: terraform validate -no-color
      
    # 3. Security Scanning using TFSec / Trivy
    - name: Run tfsec
      uses: aquasecurity/tfsec-action@v1.0.0

    # 4. Generate the Plan (on Pull Requests)
    - name: Terraform Plan
      id: plan
      if: github.event_name == 'pull_request'
      run: terraform plan -no-color
      
    # 5. Comment the Plan automatically on the Pull Request
    - name: Update Pull Request
      uses: actions/github-script@v6
      if: github.event_name == 'pull_request'
      env:
        PLAN: "terraform\n${{ steps.plan.outputs.stdout }}"
      with:
        script: |
          const output = `#### Terraform Plan 📖
          <details><summary>Show Plan</summary>\n
          \`\`\`\n
          ${process.env.PLAN}
          \`\`\`\n
          </details>`;
          github.rest.issues.createComment({
            issue_number: context.issue.number,
            owner: context.repo.owner,
            repo: context.repo.repo,
            body: output
          })

    # 6. Apply strictly when code is merged to main
    - name: Terraform Apply
      if: github.ref == 'refs/heads/main' && github.event_name == 'push'
      run: terraform apply -auto-approve -input=false
```

### The Local Wrapper: Makefile
To ensure local developers run the exact same linting flags as CI, wrap Terraform in a `Makefile` at the root of your repo:
```makefile
.PHONY: init plan apply

fmt:
	terraform fmt -recursive

validate:
	terraform validate

plan:
	terraform plan -var-file="secrets.tfvars"

apply: plan
	terraform apply -auto-approve -var-file="secrets.tfvars"
```

---

## 3. The "Why": What breaks if I skip this?

* **No OIDC (Using Access Keys):** If you create an IAM User for GitHub Actions and copy `AWS_ACCESS_KEY_ID` into GitHub Secrets, what happens when an employee leaves? Or when someone accidentally prints it to the console logs? OIDC issues temporary, short-lived tokens that expire immediately after the job finishes.
* **Skipping `TF_VAR_`:** If you hardcode `db_password` in your variables file, it gets pushed to Git. If you use the environment variable `TF_VAR_db_password`, Terraform automatically maps it to `variable "db_password"`. This keeps secrets safely inside GitHub Secrets and out of source control.
* **No `tfsec` (Trivy):** Without a security scanner, a developer might accidentally add `cidr_blocks = ["0.0.0.0/0"]` to a sensitive database Security Group. CI will happily plan and apply it, instantly exposing your data.

---

## 4. Hands-on Exercise

Locate the `TF_VAR_` logic. Open your terminal in a Terraform project directory and try it yourself safely:
1. Ensure your `variables.tf` has a variable called `foo` (type string).
2. Run `export TF_VAR_foo="hello world"` in your POSIX terminal.
3. Add `output "test" { value = var.foo }` to `outputs.tf`.
4. Run `terraform apply`. Notice how Terraform automatically scooped up the environment variable!
