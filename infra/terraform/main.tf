terraform {
  required_version = ">= 1.9.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
  backend "gcs" {
    bucket = "rangel-tech-tfstate"
    prefix = "chatwoot-web"
  }
}

provider "google" {
  project = var.project
  region  = var.region
}

variable "project" {
  type    = string
  default = "rangel-tech"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "image" {
  description = "Full image ref, tagged with the commit SHA being deployed."
  type        = string
}

variable "postgres_password" {
  type      = string
  sensitive = true
}

variable "secret_key_base" {
  type      = string
  sensitive = true
}

variable "redis_url" {
  type      = string
  sensitive = true
}

variable "storage_access_key_id" {
  type      = string
  sensitive = true
}

variable "storage_secret_access_key" {
  type      = string
  sensitive = true
}

# Credenciais dos canais Meta. Vêm exclusivamente do Infisical no workflow de
# deploy; mantê-las como variáveis sensíveis garante que uma implantação nova
# não dependa de InstallationConfig preenchido manualmente no passado.
variable "fb_app_id" {
  type      = string
  sensitive = true
}
variable "fb_app_secret" {
  type      = string
  sensitive = true
}
variable "fb_verify_token" {
  type      = string
  sensitive = true
}
variable "instagram_app_id" {
  type      = string
  sensitive = true
}
variable "instagram_app_secret" {
  type      = string
  sensitive = true
}
variable "instagram_verify_token" {
  type      = string
  sensitive = true
}

# Produto-05 seção 4 (QR automático): o Rails precisa chamar rotas
# server-a-servidor da ponte (provisionamento Evolution). Lidas direto do
# Secret Manager/Cloud Run em vez de passadas pelo workflow -- não é
# credencial rotativa do Infisical, é interna desta infraestrutura GCP.
data "google_secret_manager_secret_version" "bridge_admin_token" {
  secret  = "chatwoot-bridge-admin-token"
  project = var.project
}

data "google_cloud_run_v2_service" "chatwoot_bridge" {
  name     = "chatwoot-bridge"
  project  = var.project
  location = var.region
}

resource "google_cloud_run_v2_service" "chatwoot_web" {
  name     = "chatwoot-web"
  project  = var.project
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image   = var.image
      command = ["./rt-web.sh"]

      ports {
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }

      env {
        name  = "RAILS_ENV"
        value = "production"
      }
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "INSTALLATION_ENV"
        value = "docker"
      }
      env {
        name  = "RAILS_LOG_TO_STDOUT"
        value = "true"
      }
      env {
        name  = "POSTGRES_HOST"
        value = "66.94.101.153"
      }
      env {
        name  = "POSTGRES_PORT"
        value = "5433"
      }
      env {
        name  = "POSTGRES_DATABASE"
        value = "chatwoot_prod"
      }
      env {
        name  = "POSTGRES_USERNAME"
        value = "chatwoot_app"
      }
      env {
        name  = "POSTGRES_SSL_MODE"
        value = "require"
      }
      env {
        name  = "REDIS_OPENSSL_VERIFY_MODE"
        value = "none"
      }
      env {
        name  = "FRONTEND_URL"
        value = "https://chat.rangeltech.net"
      }
      env {
        name  = "ACTIVE_STORAGE_SERVICE"
        value = "s3_compatible"
      }
      env {
        name  = "STORAGE_BUCKET_NAME"
        value = "rangel-tech-storage"
      }
      env {
        name  = "STORAGE_REGION"
        value = "us-east-1"
      }
      env {
        name  = "STORAGE_ENDPOINT"
        value = "https://storage.googleapis.com"
      }
      env {
        name  = "STORAGE_FORCE_PATH_STYLE"
        value = "true"
      }
      env {
        name  = "AWS_REQUEST_CHECKSUM_CALCULATION"
        value = "when_required"
      }
      env {
        name  = "AWS_RESPONSE_CHECKSUM_VALIDATION"
        value = "when_required"
      }
      env {
        name  = "ENABLE_ACCOUNT_SIGNUP"
        value = "false"
      }
      env {
        name  = "DEFAULT_LOCALE"
        value = "pt_BR"
      }
      env {
        name  = "POSTGRES_PASSWORD"
        value = var.postgres_password
      }
      env {
        name  = "SECRET_KEY_BASE"
        value = var.secret_key_base
      }
      env {
        name  = "REDIS_URL"
        value = var.redis_url
      }
      env {
        name  = "STORAGE_ACCESS_KEY_ID"
        value = var.storage_access_key_id
      }
      env {
        name  = "STORAGE_SECRET_ACCESS_KEY"
        value = var.storage_secret_access_key
      }
      env {
        name  = "FB_APP_ID"
        value = var.fb_app_id
      }
      env {
        name  = "FB_APP_SECRET"
        value = var.fb_app_secret
      }
      env {
        name  = "FB_VERIFY_TOKEN"
        value = var.fb_verify_token
      }
      env {
        name  = "INSTAGRAM_APP_ID"
        value = var.instagram_app_id
      }
      env {
        name  = "INSTAGRAM_APP_SECRET"
        value = var.instagram_app_secret
      }
      env {
        name  = "INSTAGRAM_VERIFY_TOKEN"
        value = var.instagram_verify_token
      }
      env {
        name  = "BRIDGE_URL"
        value = data.google_cloud_run_v2_service.chatwoot_bridge.uri
      }
      env {
        name  = "BRIDGE_ADMIN_TOKEN"
        value = data.google_secret_manager_secret_version.bridge_admin_token.secret_data
      }
    }

    scaling {
      min_instance_count = 1
      max_instance_count = 5
    }

    timeout = "600s"
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  project  = var.project
  location = var.region
  name     = google_cloud_run_v2_service.chatwoot_web.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "url" {
  value = google_cloud_run_v2_service.chatwoot_web.uri
}
