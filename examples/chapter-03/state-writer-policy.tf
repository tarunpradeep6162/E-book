resource "aws_iam_policy" "state_writer" {
  name = "orders-prod-state-writer"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListDedicatedBackend"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.state.arn
      },
      {
        Sid    = "ReadWriteOneState"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.state.arn}/${local.state_key}"
        ]
      },
      {
        Sid    = "ManageOnlyItsLock"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.state.arn}/${local.state_key}.tflock"
        ]
      },
      {
        Sid    = "UseStateKeyThroughS3"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.state.arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.ap-south-1.amazonaws.com"
            "kms:EncryptionContext:aws:s3:arn" = [
              "${aws_s3_bucket.state.arn}/${local.state_key}",
              "${aws_s3_bucket.state.arn}/${local.state_key}.tflock"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "state_writer" {
  role       = var.state_role_name
  policy_arn = aws_iam_policy.state_writer.arn
}
