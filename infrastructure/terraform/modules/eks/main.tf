variable "cluster_name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }

resource "aws_eks_cluster" "main" {
  name = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version = "1.28"
  
  vpc_config {
    subnet_ids = var.subnet_ids
    endpoint_public_access = true
  }
  
  depends_on = [aws_iam_role_policy_attachment.eks_policy]
}

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"
  assume_role_policy = jsonencode({
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "eks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role = aws_iam_role.eks_cluster.name
}

output "cluster_endpoint" { value = aws_eks_cluster.main.endpoint }
output "cluster_name" { value = aws_eks_cluster.main.name }