# First Terraform resource: a single S3 bucket, for learning the
# init -> plan -> apply -> destroy cycle before adding anything more complex.

resource "aws_s3_bucket" "sandbox" {
  bucket = "hakusoft-mcp-test-sandbox"
}
