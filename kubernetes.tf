data "aws_eks_cluster_auth" "qa_cluster_auth" {
  name = aws_eks_cluster.qa_cluster.name
}

provider "kubernetes" {
  host = aws_eks_cluster.qa_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.qa_cluster.certificate_authority[0].data)
  token = data.aws_eks_cluster_auth.qa_cluster_auth.token
  //  load_config_file = false
  # when you wish not to load the local config file
}

resource "kubernetes_certificate_signing_request" "cert_sign" {
  metadata {
    name = "certificate-signing"
  }
  auto_approve = true
  spec {
    usages = [
      "client auth",
      "server auth"]
    request = <<EOT
-----BEGIN CERTIFICATE REQUEST-----
MIHSMIGBAgEAMCoxGDAWBgNVBAoTD2V4YW1wbGUgY2x1c3RlcjEOMAwGA1UEAxMF
YWRtaW4wTjAQBgcqhkjOPQIBBgUrgQQAIQM6AASSG8S2+hQvfMq5ucngPCzK0m0C
ImigHcF787djpF2QDbz3oQ3QsM/I7ftdjB/HHlG2a5YpqjzT0KAAMAoGCCqGSM49
BAMCA0AAMD0CHQDErNLjX86BVfOsYh/A4zmjmGknZpc2u6/coTHqAhxcR41hEU1I
DpNPvh30e0Js8/DYn2YUfu/pQU19
-----END CERTIFICATE REQUEST-----
EOT
  }
  depends_on = [
    aws_eks_cluster.qa_cluster,
    aws_eks_node_group.qa_cluster_node]
}

//-----------------------------------Roles----------------------------------------------

resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name = "aws-auth"
    namespace = "kube-system"
  }
  data = {
    mapRoles = <<EOF
- rolearn: arn:aws:iam::639716861848:role/NodeInstanceRole
  username: system:node:{{EC2PrivateDNSName}}
  groups:
  - system:bootstrappers
  - system:nodes
- rolearn: arn:aws:iam::639716861848:role/codebuild-eks
  username: codebuild-eks
  groups:
  - system:masters
EOF
  }
}

//--------------------------------Billing service---------------------------------------------

resource "kubernetes_service" "smrt_svc" {
  metadata {
    name = "smrt-svc"
    labels = {
      run = "smrtapp"
    }
  }
  spec {
    port {
      port = 8000
      protocol = "TCP"
      target_port = 8000
    }
    selector = {
      run = "smrtapp"
    }
    type = "NodePort"
  }
  depends_on = [
    aws_eks_cluster.qa_cluster,
    aws_eks_node_group.qa_cluster_node,
    aws_codebuild_project.smrt_deploy]
}
