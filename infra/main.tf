terraform {
  required_providers {
    scaleway = {
      source = "scaleway/scaleway"
    }
  }
  required_version = ">= 0.13"
}

variable "domain_name" {

}

resource "scaleway_tem_domain" "main" {
  name = var.domain_name
}

resource "scaleway_domain_record" "dkim" {
  dns_zone = scaleway_tem_domain.main.name
  type     = "TXT"
  name     = "${scaleway_tem_domain.main.project_id}._domainkey"
  data     = scaleway_tem_domain.main.dkim_config
}

resource "scaleway_domain_record" "spf" {
  dns_zone = scaleway_tem_domain.main.name
  type     = "TXT"
  name     = ""
  data     = "v=spf1 ${scaleway_tem_domain.main.spf_config} -all"
}

resource "scaleway_domain_record" "mx" {
  dns_zone = scaleway_tem_domain.main.name
  type     = "MX"
  name     = ""
  data     = "."
  priority = 0
}

/**
 * IAM Key
 */
data "scaleway_account_project" "default" {
  name = "default"
}

resource "scaleway_iam_application" "handler" {
  name = "tem-demo"
}

resource "scaleway_iam_policy" "object_read_only" {
  name           = "Emails Sender"
  application_id = scaleway_iam_application.handler.id

  rule {
    project_ids = [data.scaleway_account_project.default.id]
    permission_set_names = [
      "TransactionalEmailFullAccess",
      "DomainsDNSReadOnly"
    ]
  }
}

resource "scaleway_iam_api_key" "main" {
  application_id = scaleway_iam_application.handler.id
}

/**
 * Function
 */
resource "scaleway_function_namespace" "handler" {
  name = "tem-demo"
}

data "archive_file" "handler" {
  type        = "zip"
  source_dir  = "${path.module}/../signup-handler"
  output_path = "${path.module}/.functions/signup-handler.zip"
}

resource "scaleway_function" "handler" {
  name         = "tem-demo-signup-handler"
  namespace_id = scaleway_function_namespace.handler.id
  runtime      = "go118"
  handler      = "Handle"
  privacy      = "public"
  zip_file     = data.archive_file.handler.output_path
  zip_hash     = data.archive_file.handler.output_sha
  deploy       = true
  min_scale    = 1

  environment_variables = {
    "SENDER_NAME"            = "Amazing Super Product"
    "SENDER_EMAIL"           = "no-reply@${scaleway_tem_domain.main.name}"
    "SCW_DEFAULT_PROJECT_ID" = scaleway_iam_api_key.main.default_project_id
    "SCW_DEFAULT_REGION"     = "fr-par"
  }

  secret_environment_variables = {
    "SCW_ACCESS_KEY" = scaleway_iam_api_key.main.access_key
    "SCW_SECRET_KEY" = scaleway_iam_api_key.main.secret_key
  }
}

output "handler_url" {
  value = "https://${scaleway_function.handler.domain_name}"
}

/**
 * Website
 */
resource "scaleway_object_bucket" "main" {
  name = "tem-demo-super-product"
}

resource "scaleway_object_bucket_acl" "main" {
  bucket = scaleway_object_bucket.main.name
  acl    = "public-read"
}

resource "scaleway_object_bucket_website_configuration" "main" {
  bucket = scaleway_object_bucket.main.name
  index_document {
    suffix = "index.html"
  }
}

resource "local_file" "index" {
  filename = "${path.module}/.website/index.html"
  content = templatefile("${path.module}/../super-product/index.html.tftpl", {
    DISPATCHER_ENDPOINT = "https://${scaleway_function.handler.domain_name}"
  })
}

resource "scaleway_object" "index" {
  bucket     = scaleway_object_bucket.main.name
  key        = "index.html"
  visibility = "public-read"

  file = local_file.index.filename
  hash = local_file.index.content
}

output "url" {
  value = "https://${scaleway_object_bucket_website_configuration.main.website_endpoint}"
}
