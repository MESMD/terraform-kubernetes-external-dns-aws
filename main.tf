locals {
  external_dns_docker_image = "k8s.gcr.io/external-dns/external-dns:v${var.external_dns_version}"
  external_dns_version      = var.external_dns_version

  default_name = "aws-eks-external-dns-${lower(var.hosted_zone_id)}-${random_string.suffix.result}"

  iam_name = "eks-external-dns-${lower(var.hosted_zone_id)}-${lower(var.k8s_cluster_name)}-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}


resource "kubernetes_service_account" "this" {
  automount_service_account_token = true
  metadata {
    name      = local.default_name
    namespace = var.k8s_namespace
    labels = {
      "app.kubernetes.io/name"       = local.default_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_cluster_role" "this" {
  metadata {
    name = local.default_name

    labels = {
      "app.kubernetes.io/name"       = local.default_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  rule {
    api_groups = [
      "",
    ]

    resources = [
      "endpoints",
    ]

    verbs = [
      "get",
      "list",
      "watch",
    ]
  }

  rule {
    api_groups = [
      "",
    ]

    resources = [
      "services",
    ]

    verbs = [
      "get",
      "list",
      "watch",
    ]
  }

  rule {
    api_groups = [
      "",
    ]

    resources = [
      "pods",
    ]

    verbs = [
      "get",
      "list",
      "watch",
    ]
  }
  rule {
    api_groups = [
      "extensions",
    ]

    resources = [
      "ingresses",
    ]

    verbs = [
      "get",
      "watch",
      "list",
    ]
  }
  rule {
    api_groups = [
      "",
    ]

    resources = [
      "nodes",
    ]

    verbs = [
      "list",
      "watch",
    ]
  }
}

resource "kubernetes_cluster_role_binding" "this" {
  metadata {
    name = local.default_name

    labels = {
      "app.kubernetes.io/name"       = local.default_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.this.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.this.metadata[0].name
    namespace = kubernetes_service_account.this.metadata[0].namespace
  }
}

resource "kubernetes_deployment" "this" {
  depends_on = [kubernetes_cluster_role_binding.this]

  metadata {
    name      = local.default_name
    namespace = var.k8s_namespace

    labels = {
      "app.kubernetes.io/name"       = local.default_name
      "app.kubernetes.io/version"    = "v${local.external_dns_version}"
      "app.kubernetes.io/managed-by" = "terraform"
    }

    annotations = {
      "field.cattle.io/description" = "AWS External DNS"
    }
  }

  spec {

    replicas = var.k8s_replicas

    selector {
      match_labels = {
        "app.kubernetes.io/name" = local.default_name
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = merge(
          {
            "app.kubernetes.io/name"    = local.default_name
            "app.kubernetes.io/version" = local.external_dns_version
          },
          var.k8s_pod_labels
        )
      }

      spec {
        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = [local.default_name]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        automount_service_account_token = true

        dns_policy = "ClusterFirst"

        restart_policy = "Always"

        container {
          name                     = "server"
          image                    = local.external_dns_docker_image
          image_pull_policy        = "Always"
          termination_message_path = "/dev/termination-log"

          args = [
            "--source=service",
            "--source=ingress",
            "--domain-filter=${var.domain}",
            "--annotation-filter=${var.annotation_filter}",
            "--provider=aws",
            "--policy=${var.sync_policy}",
            "--aws-zone-type=${var.aws_zone_type}",
            "--registry=txt",
            "--txt-owner-id=${var.hosted_zone_id}",
          ]
        }
        security_context {
          fs_group = 65534
        }

        service_account_name             = kubernetes_service_account.this.metadata[0].name
        termination_grace_period_seconds = 60
      }
    }
  }
}
