data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      identifiers = ["eks.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name        = "aws-eks-external-dns-viewer-${lower(var.hosted_zone_id)}-${lower(var.k8s_cluster_name)}"
  description = "Permissions required by the Kubernetes AWS EKS External Name controller to do it's job."
  path        = "/"

  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}

data "aws_iam_policy_document" "external_dns" {
  statement {
    actions = [
      "route53:ChangeResourceRecordSets",
    ]

    resources = ["arn:aws:route53:::hostedzone/*"]
  }
  statement {
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_dns" {
  name        = "aws-eks-external-dns-viewer-${lower(var.hosted_zone_id)}-${lower(var.k8s_cluster_name)}"
  description = "Allows access to resources needed to run external dns."
  policy      = data.aws_iam_policy_document.external_dns.json
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}
