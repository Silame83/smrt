//---------------------CI procedure-----------------------

data "aws_security_groups" "cb_sg" {
  filter {
    name = "group-name"
    values = [
      "default"]
  }
  filter {
    name = "vpc-id"
    values = [
      aws_vpc.stage_qa.id]
  }
}

resource "aws_ecr_repository" "smrt" {
  name = "smrt"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_iam_role" "cb_iam_role" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cb_iam_role" {
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ssm:DescribeParameters"
      ],
      "Resource": "*",
      "Effect": "Allow"
    },
    {
      "Action": [
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:eu-west-3:639716861848:parameter/*",
      "Effect": "Allow"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetRepositoryPolicy",
        "ecr:DescribeRepositories",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:BatchGetImage",
        "ecr:GetLifecyclePolicy",
        "ecr:GetLifecyclePolicyPreview",
        "ecr:ListTagsForResource",
        "ecr:DescribeImageScanFindings",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Resource": [
        "*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeDhcpOptions",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateNetworkInterfacePermission"
      ],
      "Resource": [
        "arn:aws:ec2:eu-west-3:639716861848:network-interface/*"
      ],
      "Condition": {
        "StringEquals": {
          "ec2:Subnet": [
            "${aws_subnet.PrivateSubnetA.arn}",
            "${aws_subnet.PrivateSubnetB.arn}",
            "${aws_subnet.PrivateSubnetC.arn}"
          ],
          "ec2:AuthorizedService": "codebuild.amazonaws.com"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "*"
      ],
      "Resource": [
        "${aws_ecr_repository.smrt.arn}",
        "${aws_ecr_repository.smrt.arn}/*"
      ]
    },
    {
      "Sid": "S3AccessPolicy",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:GetObject",
        "s3:List*",
        "s3:PutObject"
      ],
      "Resource": "*"
    },
    {
      "Sid": "VisualEditor0",
      "Effect": "Allow",
      "Action": "eks:DescribeCluster",
      "Resource": "*"
    }
  ]
}
POLICY
  role = aws_iam_role.cb_iam_role.id
}

resource "aws_s3_bucket" "smrt_bld_bckt" {
  bucket = "smrt-build"
  acl = "private"
}

resource "aws_s3_bucket" "smrt_dply_bckt" {
  bucket = "smrt-deploy"
  acl = "private"
}

resource "aws_codebuild_project" "smrt_build" {
  name = "smrt-build"
  service_role = aws_iam_role.cb_iam_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image = "aws/codebuild/standard:2.0"
    type = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode = true
  }
  source {
    type = "CODEPIPELINE"
    location = "https://github.com/Silame83/smrt.git"
    buildspec = <<EOF
version: 0.2

phases:
  install:
    runtime-versions:
      docker: 18
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - $(aws ecr get-login --region $AWS_DEFAULT_REGION --no-include-email)
      - ECR_REPO_URI=${aws_ecr_repository.smrt.repository_url}
      - echo $CODEBUILD_RESOLVED_SOURCE_VERSION
      - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - echo $COMMIT_HASH
      - git config --global user.name "Silame83"
      - git config --global user.email "silame83@gmail.com"
      - git config --global http.postBuffer 157286400
      - IMAGE_TAG=commitid-$COMMIT_HASH
      - echo $IMAGE_TAG
  build:
    commands:
      - echo Build started on `date`
      - echo Building the Docker image...
      - docker build -t $ECR_REPO_URI:latest .
      - docker tag $ECR_REPO_URI:latest $ECR_REPO_URI:$IMAGE_TAG
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker images...
      - docker push $ECR_REPO_URI:latest
      - docker push $ECR_REPO_URI:$IMAGE_TAG
EOF
    git_clone_depth = 1

    git_submodules_config {
      fetch_submodules = true
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = "log-group"
      stream_name = "log-stream"
    }
  }

  source_version = "master"

  vpc_config {
    security_group_ids = data.aws_security_groups.cb_sg.ids
    subnets = [
      aws_subnet.PrivateSubnetA.id,
      aws_subnet.PrivateSubnetB.id,
      aws_subnet.PrivateSubnetC.id
    ]
    vpc_id = aws_vpc.stage_qa.id
  }
  tags = {
    Environment = "QA"
  }
}

resource "aws_codebuild_project" "smrt_deploy" {
  name = "smrt-deploy"
  service_role = aws_iam_role.cb_iam_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image = "aws/codebuild/standard:2.0"
    type = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode = true
  }
  source {
    type = "CODEPIPELINE"
    buildspec = <<EOF
version: 0.2

phases:
  install:
    commands:
      - echo Installing app dependencies...
      - curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.15.10/2020-02-22/bin/linux/amd64/kubectl
      - chmod +x ./kubectl
      - mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
#     - echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
#     - source ~/.bashrc
  pre_build:
    commands:
      - echo Logging in to Amazon EKS...
      - AWS_CLUSTER_NAME=${aws_eks_cluster.qa_cluster.name}
      - aws eks --region $AWS_DEFAULT_REGION update-kubeconfig --name $AWS_CLUSTER_NAME
  build:
    commands:
      - echo Entered the build phase...
      - echo Change directory to secondary source
      - cd $CODEBUILD_SRC_DIR
      - echo List directory
      - ls -la
      - echo Push the latest image to cluster
      - kubectl apply -f deployment.yaml
EOF
    git_clone_depth = 1

    git_submodules_config {
      fetch_submodules = true
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = "log-group"
      stream_name = "log-stream"
    }
  }

  source_version = "master"

  vpc_config {
    security_group_ids = data.aws_security_groups.cb_sg.ids
    subnets = [
      aws_subnet.PrivateSubnetA.id,
      aws_subnet.PrivateSubnetB.id,
      aws_subnet.PrivateSubnetC.id
    ]
    vpc_id = aws_vpc.stage_qa.id
  }
  tags = {
    Environment = "QA"
  }
}

resource "aws_codebuild_source_credential" "cb_sc" {
  auth_type = "PERSONAL_ACCESS_TOKEN"
  server_type = "GITHUB"
  token = "6ba2575cc829b0172c749f103d12626ff23c6738"
}

/*resource "aws_codebuild_webhook" "cb_webhook" {
  project_name = aws_codebuild_project.spa.name

  filter_group {
    filter {
      type = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type = "HEAD_REF"
      pattern = "master"
    }
  }
}*/

//----------------------------CD procedure--------------------------

resource "aws_iam_role" "cp_role" {
  name = "cp_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "cp_policy" {
  name = "cp_policy"
  role = aws_iam_role.cp_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:GetBucketAcl",
        "s3:GetBucketLocation",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.smrt_bld_bckt.arn}",
        "${aws_s3_bucket.smrt_bld_bckt.arn}/*",
        "${aws_s3_bucket.smrt_dply_bckt.arn}",
        "${aws_s3_bucket.smrt_dply_bckt.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:DescribeImages",
        "ecr:DescribeRepositories"
      ],
      "Resource": [
        "${aws_ecr_repository.smrt.arn}",
        "${aws_ecr_repository.smrt.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ecs:*",
      "Resource": "*"
    },
    {
      "Sid": "VisualEditor0",
      "Effect": "Allow",
      "Action": "eks:DescribeCluster",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_codepipeline" "cp_build" {
  name = "ecr-pipeline"
  role_arn = aws_iam_role.cp_role.arn
  artifact_store {
    location = aws_s3_bucket.smrt_bld_bckt.bucket
    type = "S3"
  }
  stage {
    name = "Source"

    action {
      category = "Source"
      name = "Source"
      owner = "ThirdParty"
      provider = "GitHub"
      version = "1"
      output_artifacts = [
        "source_output"]

      configuration = {
        Repo = "smrt"
        Owner = "Silame83"
        Branch = "master"
        OAuthToken = "da4a97f84934094ba0c5b1bfbf45b06746de2e5b"
      }
    }
  }

  stage {
    name = "Build"

    action {
      category = "Build"
      name = "Build"
      owner = "AWS"
      provider = "CodeBuild"
      input_artifacts = [
        "source_output"]
      output_artifacts = [
        "build_output"]
      version = "1"

      configuration = {
        ProjectName = "smrt-build"
      }
    }
  }
  depends_on = [
    aws_codebuild_project.smrt_build,
    aws_codebuild_project.smrt_deploy]
}

locals {
  webhook_secret = aws_codebuild_source_credential.cb_sc.token
}

resource "aws_codepipeline" "cp_deploy" {
  name = "eks-pipeline"
  role_arn = aws_iam_role.cp_role.arn
  artifact_store {
    location = aws_s3_bucket.smrt_dply_bckt.bucket
    type = "S3"
  }
  stage {
    name = "Source"

    action {
      category = "Source"
      name = "ECR-Source"
      owner = "AWS"
      provider = "ECR"
      version = "1"
      output_artifacts = [
        "source_output"]

      configuration = {
        RepositoryName = aws_ecr_repository.smrt.name
        ImageTag = "latest"
      }
    }
  }

  stage {
    name = "Build"

    action {
      category = "Build"
      name = "Build"
      owner = "AWS"
      provider = "CodeBuild"
      input_artifacts = [
        "source_output"]
      output_artifacts = [
        "build_output"]
      version = "1"

      configuration = {
        ProjectName = "smrt-deploy"
      }
    }
  }
  depends_on = [
    aws_codebuild_project.smrt_build,
    aws_codebuild_project.smrt_deploy]
}

/*locals {
  webhook_secret = aws_codebuild_source_credential.cb_sc.token
}*/

resource "aws_codepipeline_webhook" "cp_webhook" {
  authentication = "GITHUB_HMAC"
  name = "cp_webhook"
  target_action = "Source"
  target_pipeline = aws_codepipeline.cp_build.name

  authentication_configuration {
    secret_token = local.webhook_secret
  }

  filter {
    json_path = "$.ref"
    match_equals = "refs/heads/{Branch}"
  }
}

/*resource "github_repository_webhook" "ghub_rw" {
  repository = "https://github.com/Silame83/simple-python-app"

  configuration {
    url = aws_codepipeline_webhook.cp_webhook.url
    content_type = "json"
    insecure_ssl = true
    secret = local.webhook_secret
  }

  events = [
    "push"]
}*/

